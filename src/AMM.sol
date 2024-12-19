// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {IAMM} from "./interfaces/IAMM.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";
// import {LPTOKEN} from "./LpToken.sol";
import {Math} from "./libraries/Math.sol";

contract AMM is IAMM {
    using Math for uint256;

    mapping(uint256 => Pool) public PoolInfo; // pool information
    mapping(address => uint256) public TokenReserve; // store virtual balance
    mapping(address => mapping(uint256 => Individual)) public Position;

    function name() public pure returns (string memory) {
        return "Ax11 Liquidity";
    }

    function symbol() public pure returns (string memory) {
        return "AX11LP";
    }

    /// @notice get the pool id without storage reading
    function getPool(
        address token0,
        address token1
    ) public pure returns (uint256 pool, address tokenX, address tokenY) {
        if (token0 < token1) {
            tokenX = token0;
            tokenY = token1;
        } else if (token0 > token1) {
            tokenX = token1;
            tokenY = token0;
        } else {
            revert INVALID_ADDRESS();
        }
        pool = uint256(keccak256(abi.encodePacked(tokenX, tokenY)));
    }

    function getPrice(
        uint256 pool
    ) public view returns (uint256 priceX, uint256 priceY) {
        Pool storage _pool = PoolInfo[pool];
        uint256 newRatio = getReserveRatio(pool);
        uint256 oldRatio = _pool.lastRatio;
        priceX = _pool.lastPriceX;
        if (newRatio != oldRatio) {
            priceX = Math.fullMulDiv(newRatio, priceX, oldRatio); //revert if `oldRatio` == 0
        }
        priceY = 1e38 / priceX;
    }

    function getReserveRatio(uint256 pool) public view returns (uint256 ratio) {
        Pool storage _pool = PoolInfo[pool];
        address tokenX = _pool.tokenX;
        address tokenY = _pool.tokenY;
        uint256 oldBalX = TokenReserve[tokenX];
        uint256 oldBalY = TokenReserve[tokenY];
        uint256 newReserveX = (IERC20(tokenX).balanceOf(address(this)) *
            _pool.reserveX) / oldBalX; // get new reserveX, division zero is fine
        uint256 newReserveY = (IERC20(tokenY).balanceOf(address(this)) *
            _pool.reserveY) / oldBalY; // get new reserveY, division zero is fine
        ratio = (newReserveY * 1e19) / newReserveX;
    }

    /// @notice This function facilitates both pool creation and liquidity deposit.
    /// TODO: update the price before makeing the deposit
    function deposit(
        address token0, // if this is native ETH, input `address(0)`
        address token1,
        uint256 amount0,
        uint256 amount1,
        uint256 priceX, // input the price of X with 19 decimals
        uint256 slippage, // price bound to dictate min,max
        address toX, // LPx recipient
        address toY, // LPy recipient
        uint256 deadline
    )
        external
        payable
        returns (uint256 liquidityX, uint256 liquidityY, uint256 pool)
    {
        require(deadline > block.timestamp - 1, EXPIRED());
        require(priceX != 0 && priceX - 1 < type(uint128).max, INVALID_PRICE());
        (pool, token0, token1) = getPool(token0, token1); // sort

        Pool storage _pool = PoolInfo[pool];

        //if the pool doesn't exist, create pool
        if (_pool.tokenY == address(0)) {
            _pool.tokenX = token0;
            _pool.tokenY = token1;
            deadline = priceX;
            _pool.lastPriceX = uint128(priceX);
        } else {
            (deadline, ) = getPrice(pool); // reuse deadline as current priceX
            require(
                (deadline > priceX ? deadline - priceX : priceX - deadline) <
                    slippage + 1,
                INVALID_PRICE()
            );
        }
        uint256 tokenReserve0 = TokenReserve[token0];
        uint256 tokenReserve1 = TokenReserve[token1];

        // Handle deposits for both tokens
        (liquidityX, amount0) = _deposit(
            token0,
            amount0,
            _pool.reserveX,
            tokenReserve0,
            _pool.totalLpX,
            deadline
        );

        (liquidityY, amount1) = _deposit(
            token1,
            amount1,
            _pool.reserveY,
            tokenReserve1,
            _pool.totalLpY,
            (1e38 / deadline)
        );

        _mint(toX, toY, pool, liquidityX, liquidityY);

        TokenReserve[token0] = tokenReserve0 + amount0;
        TokenReserve[token1] = tokenReserve1 + amount1;
        _pool.reserveX += uint128(amount0);
        _pool.reserveY += uint128(amount1);

        emit Deposit(msg.sender, pool, liquidityX, liquidityY);
    }

    function _deposit(
        address token,
        uint256 amount,
        uint256 reserve,
        uint256 totalReserve,
        uint256 totalLp,
        uint256 priceX
    ) private returns (uint256 liquidity, uint256 reserveAmount) {
        if (amount == 0) return (0, 0);

        if (token != address(0)) {
            //ERC20
            uint256 initialBalance = IERC20(token).balanceOf(address(this));
            TransferHelper.safeTransferFrom(
                IERC20(token),
                msg.sender,
                address(this),
                amount
            );
            uint256 realAmount = IERC20(token).balanceOf(address(this)) -
                initialBalance;
            if (initialBalance == 0) {
                reserveAmount = realAmount;
            } else {
                reserveAmount = (realAmount * totalReserve) / initialBalance; // Scale based on existing totalReserve
            }
        } else {
            //native
            reserveAmount = address(this).balance - totalReserve;
        }

        if (totalLp != 0) {
            liquidity = (reserveAmount * totalLp) / reserve;
        } else {
            liquidity = (reserveAmount * Math.sqrt(priceX));
        }
    }

    function _mint(
        address toX,
        address toY,
        uint256 pool,
        uint256 valueX,
        uint256 valueY
    ) private {
        Pool storage _pool = PoolInfo[pool];
        uint256 MINIMUM_LIQUIDITY = 100000;
        if (valueX != 0) {
            uint256 _totalLpX = _pool.totalLpX;
            _pool.totalLpX += valueX;
            if (_totalLpX == 0) {
                Position[address(0)][pool].liquidityX = MINIMUM_LIQUIDITY;
                valueX -= MINIMUM_LIQUIDITY;
            }
            unchecked {
                Position[toX][pool].liquidityX += valueX;
            }
        }

        if (valueY != 0) {
            uint256 _totalLpY = _pool.totalLpY;
            _pool.totalLpY += valueY;
            if (_totalLpY == 0) {
                Position[address(0)][pool].liquidityY = MINIMUM_LIQUIDITY;
                valueY -= MINIMUM_LIQUIDITY;
            }
            unchecked {
                Position[toY][pool].liquidityY += valueY;
            }
        }
    }

    // function withdraw(
    //     IERC20 tokenX,
    //     IERC20 tokenY,
    //     uint256 amountLPX,
    //     uint256 amountLPY,
    //     uint128 priceX, // please input Q64.64 price
    //     uint256 slippage, // price bound to dictate min,max
    //     address toX,
    //     address toY,
    //     uint256 deadline
    // ) external returns (uint256 amountX, uint256 amountY) {
    //     require(deadline > block.timestamp - 1, "EXPIRED");
    //     require(priceX != 0, "INVALID_PRICE");

    //     Pool storage _pool = PoolInfo[getPool(tokenX, tokenY)];

    //     require(
    //         address(tokenX) != address(0) && address(tokenY) != address(0),
    //         "UNINITIALIZED"
    //     );
    //     // deadline = _pool.price
    // }
}
