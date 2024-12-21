// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {IAMM} from "./interfaces/IAMM.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";
// import {LPTOKEN} from "./LpToken.sol";
import {Math} from "./libraries/Math.sol";
import {ReentrancyGuard} from "./abstracts/ReentrancyGuard.sol";

contract AMM is IAMM, ReentrancyGuard {
    using Math for uint256;

    mapping(uint256 => Pool) public PoolInfo; // pool information
    mapping(address => uint256) public TokenReserve; // store virtual balance
    mapping(address => mapping(uint256 => Position)) public balanceOf;
    mapping(address => mapping(address => mapping(uint256 => Position)))
        public allowance;

    function name() public pure returns (string memory) {
        return "Ax11 Liquidity";
    }

    function symbol() public pure returns (string memory) {
        return "Ax11-LP";
    }

    function decimals() public pure returns (uint8) {
        return 18;
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
        (uint256 realReserveX, uint256 realReserveY) = getReserve(pool);
        (priceX, priceY) = _getPrice(pool, realReserveX, realReserveY);
    }

    function _getPrice(
        uint256 pool,
        uint256 realReserveX,
        uint256 realReserveY
    ) private view returns (uint256 priceX, uint256 priceY) {
        Pool storage _pool = PoolInfo[pool];
        priceX = Math.fullMulDiv(
            realReserveY * _pool.lastBalanceX,
            _pool.lastPriceX,
            realReserveX * _pool.lastBalanceY
        );
        if (priceX == 0) return (0, 0);
        priceY = 1e76 / priceX;
    }

    function getReserve(
        uint256 pool
    ) public view returns (uint256 realReserveX, uint256 realReserveY) {
        Pool storage _pool = PoolInfo[pool];
        address tokenX = _pool.tokenX;
        address tokenY = _pool.tokenY;
        uint256 balanceX = tokenX == address(0)
            ? TokenReserve[tokenX]
            : _getBalance(tokenX);
        uint256 balanceY = _getBalance(tokenY);
        realReserveX = _getReserve(
            _pool.reserveX,
            TokenReserve[tokenX],
            balanceX
        );
        realReserveY = _getReserve(
            _pool.reserveY,
            TokenReserve[tokenY],
            balanceY
        );
    }

    function _getReserve(
        uint256 reserve,
        uint256 totalReserve,
        uint256 balance
    ) private pure returns (uint256 realReserve) {
        if (totalReserve == 0) return 0;
        realReserve = (balance * reserve) / totalReserve; // get  real reserve, division zero is fine
    }

    function _getBalance(address token) private view returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    function _slippageCheck(
        uint256 realPrice,
        uint256 targetPrice,
        uint256 slippage
    ) private pure {
        require(
            (
                realPrice > targetPrice
                    ? realPrice - targetPrice
                    : targetPrice - realPrice
            ) < slippage + 1,
            INVALID_PRICE()
        );
    }

    function _checkValue(uint256 first, uint256 second) private pure {
        require(first != 0 && first - 1 < second, INVALID_VALUE());
    }

    /// @notice This function facilitates both pool creation and liquidity deposit.
    /// TODO: update the price before makeing the deposit
    function deposit(
        address token0, // if this is native ETH, input `address(0)`
        address token1,
        uint256 amount0,
        uint256 amount1,
        uint256 priceX, // input the price of X with 38 decimals
        uint256 slippage, // price bound to dictate min,max
        address toX, // LPx recipient
        address toY, // LPy recipient
        uint256 deadline
    )
        external
        payable
        nonReentrant
        returns (uint256 pool, uint256 liquidityX, uint256 liquidityY)
    {
        address sender = msg.sender;
        _checkValue(block.timestamp, deadline); // check deadline
        _checkValue(priceX, type(uint256).max); // check priceX
        (pool, token0, token1) = getPool(token0, token1); // sort

        Pool storage _pool = PoolInfo[pool];
        uint256 reserve0 = _pool.reserveX;
        uint256 reserve1 = _pool.reserveY;
        uint256 tokenReserve0 = TokenReserve[token0];
        uint256 tokenReserve1 = TokenReserve[token1];
        uint256 balanceToken0 = token0 == address(0)
            ? tokenReserve0
            : _getBalance(token0);

        uint256 balanceToken1 = _getBalance(token1);
        uint256 realReserveX = _getReserve(
            reserve0,
            tokenReserve0,
            balanceToken0
        );
        uint256 realReserveY = _getReserve(
            reserve1,
            tokenReserve1,
            balanceToken1
        );
        uint256 totalLPX = _pool.totalLpX;
        uint256 totalLPY = _pool.totalLpY;

        //if the pool doesn't exist, create pool
        if (_pool.tokenY == address(0)) {
            _pool.tokenX = token0;
            _pool.tokenY = token1;
            deadline = priceX; // reuse deadline as current priceX
        } else {
            (deadline, ) = _getPrice(pool, realReserveX, realReserveY); // reuse deadline as current priceX
            _slippageCheck(deadline, priceX, slippage);
        }

        _pool.lastPriceX = deadline;

        // Handle deposits for both tokens
        // reuse variable `slippage` to handle real input amount
        (liquidityX, slippage, amount0) = _deposit(
            sender,
            token0,
            amount0,
            reserve0,
            tokenReserve0,
            balanceToken0,
            totalLPX
        );
        _pool.lastBalanceX = _safeCast128(realReserveX + slippage);

        // reuse variable `slippage` to handle real input amount
        (liquidityY, slippage, amount1) = _deposit(
            sender,
            token1,
            amount1,
            reserve1,
            tokenReserve1,
            balanceToken1,
            totalLPY
        );
        _pool.lastBalanceY = _safeCast128(realReserveY + slippage);
        _mint(toX, toY, pool, liquidityX, liquidityY, totalLPX, totalLPY);

        TokenReserve[token0] = tokenReserve0 + amount0;
        TokenReserve[token1] = tokenReserve1 + amount1;
        _pool.reserveX = _safeCast128(reserve0 + amount0);
        _pool.reserveY = _safeCast128(reserve1 + amount1);
        _pool.totalLpX = _safeCast128(liquidityX + totalLPX);
        _pool.totalLpY = _safeCast128(liquidityY + totalLPY);

        emit Deposit(sender, pool, liquidityX, liquidityY);
    }

    function _deposit(
        address sender,
        address token,
        uint256 amount,
        uint256 poolReserve,
        uint256 totalReserve,
        uint256 totalBalance,
        uint256 totalLp
    )
        private
        returns (uint256 liquidity, uint256 realAmount, uint256 reserveAmount)
    {
        if (amount == 0) return (0, 0, 0);
        if (token != address(0)) {
            //ERC20
            TransferHelper.safeTransferFrom(
                token,
                sender,
                address(this),
                amount
            );
            realAmount = _getBalance(token) - totalBalance;
            // Scale reserve amount based on existing totalReserve and totalBalance
            reserveAmount = (totalBalance != 0)
                ? (realAmount * totalReserve) / totalBalance
                : realAmount;
        } else {
            //native
            realAmount = address(this).balance - totalReserve;
            reserveAmount = realAmount;
        }

        liquidity = totalLp != 0
            ? ((reserveAmount * totalLp) / poolReserve)
            : reserveAmount;
    }

    function _safeCast128(uint256 input) private pure returns (uint128) {
        require(input - 1 < type(uint128).max, OVERFLOW());
        return uint128(input);
    }

    function _mint(
        address toX,
        address toY,
        uint256 pool,
        uint256 valueX,
        uint256 valueY,
        uint256 totalX,
        uint256 totalY
    ) private {
        uint256 MINIMUM_LIQUIDITY = 1000;
        if (valueX != 0) {
            if (totalX == 0) {
                balanceOf[address(0)][pool].liquidityX = MINIMUM_LIQUIDITY;
                valueX -= MINIMUM_LIQUIDITY;
            }
            unchecked {
                balanceOf[toX][pool].liquidityX += valueX;
            }
        }

        if (valueY != 0) {
            if (totalY == 0) {
                balanceOf[address(0)][pool].liquidityY = MINIMUM_LIQUIDITY;
                valueY -= MINIMUM_LIQUIDITY;
            }
            unchecked {
                balanceOf[toY][pool].liquidityY += valueY;
            }
        }
    }

    function transfer(
        uint256 id,
        address toX,
        address toY,
        uint256 amount0,
        uint256 amount1
    ) public returns (bool) {
        address sender = msg.sender;
        if (amount0 != 0) {
            balanceOf[sender][id].liquidityX -= amount0;
            unchecked {
                balanceOf[toX][id].liquidityX += amount0;
            }
            emit Transfer(sender, toX, id, true, amount0);
        }
        if (amount1 != 0) {
            balanceOf[sender][id].liquidityY -= amount1;
            unchecked {
                balanceOf[toX][id].liquidityX += amount0;
            }
            emit Transfer(sender, toY, id, false, amount1);
        }
        return true;
    }

    function transferFrom(
        uint256 id,
        address fromX,
        address fromY,
        address toX,
        address toY,
        uint256 amount0,
        uint256 amount1
    ) public returns (bool) {
        address sender = msg.sender;
        if (amount0 != 0) {
            uint256 allowedX = allowance[fromX][sender][id].liquidityX;
            if (allowedX != type(uint256).max) {
                allowance[fromX][toX][id].liquidityX = allowedX - amount0;
            }
            balanceOf[fromX][id].liquidityX -= amount0;
            unchecked {
                balanceOf[toX][id].liquidityX += amount0;
            }
            emit Transfer(fromX, toX, id, true, amount0);
        }

        if (amount1 != 0) {
            uint256 allowedY = allowance[fromY][sender][id].liquidityY;
            if (allowedY != type(uint256).max) {
                allowance[fromY][toY][id].liquidityY = allowedY - amount1;
            }
            balanceOf[fromY][id].liquidityY -= amount1;
            unchecked {
                balanceOf[toY][id].liquidityY += amount1;
            }
            emit Transfer(fromY, toY, id, false, amount1);
        }

        return true;
    }

    function approve(
        uint256 id,
        address spenderX,
        address spenderY,
        uint256 amount0,
        uint256 amount1
    ) public returns (bool) {
        address sender = msg.sender;
        if (amount0 != 0) {
            allowance[sender][spenderX][id].liquidityX = amount0;
            emit Approval(sender, spenderX, id, amount0);
        }

        if (amount1 != 0) {
            allowance[sender][spenderY][id].liquidityY = amount1;
            emit Approval(sender, spenderY, id, amount1);
        }
        return true;
    }

    function withdraw(
        address token0, // if this is native ETH, input `address(0)`
        address token1,
        uint256 amount0,
        uint256 amount1,
        uint256 priceX, // input the price of X with 38 decimals
        uint256 slippage, // price bound to dictate min,max
        address toX, // tokenX recipient
        address toY, // tokenY recipient
        uint256 deadline
    )
        external
        payable
        nonReentrant
        returns (uint256 pool, uint256 amountX, uint256 amountY)
    {
        address sender = msg.sender;
        _checkValue(block.timestamp, deadline); // check deadline
        _checkValue(priceX, type(uint256).max); // check priceX
        (pool, token0, token1) = getPool(token0, token1); // sort

        Pool storage _pool = PoolInfo[pool];
        require(_pool.tokenY != address(0), UNINITIALIZED());

        uint256 reserve0 = _pool.reserveX;
        uint256 reserve1 = _pool.reserveY;
        uint256 tokenReserve0 = TokenReserve[token0];
        uint256 tokenReserve1 = TokenReserve[token1];
        uint256 balanceToken0 = token0 == address(0)
            ? tokenReserve0
            : _getBalance(token0);

        uint256 balanceToken1 = _getBalance(token1);
        uint256 realReserveX = _getReserve(
            reserve0,
            tokenReserve0,
            balanceToken0
        );
        uint256 realReserveY = _getReserve(
            reserve1,
            tokenReserve1,
            balanceToken1
        );

        (deadline, ) = _getPrice(pool, realReserveX, realReserveY); // reuse deadline as current priceX
        _slippageCheck(deadline, priceX, slippage);
        _pool.lastPriceX = deadline;

        uint256 totalLPX = _pool.totalLpX;
        uint256 totalLPY = _pool.totalLpY;

        (amountX, amount0) = _burn(
            sender,
            toX,
            token0,
            pool,
            amount0,
            reserve0,
            tokenReserve0,
            balanceToken0,
            totalLPX,
            true
        );
        (amountY, amount1) = _burn(
            sender,
            toY,
            token1,
            pool,
            amount1,
            reserve1,
            tokenReserve1,
            balanceToken1,
            totalLPY,
            false
        );

        TokenReserve[token0] = tokenReserve0 - amount0;
        TokenReserve[token1] = tokenReserve1 - amount1;
        _pool.reserveX = _safeCast128(reserve0 - amount0);
        _pool.reserveY = _safeCast128(reserve1 - amount1);
        _pool.lastBalanceX = _safeCast128(realReserveX - amountX);
        _pool.lastBalanceY = _safeCast128(realReserveY - amountY);

        unchecked {
            // overflow check in `_burn`
            _pool.totalLpX = _safeCast128(totalLPX - amount0);
            _pool.totalLpY = _safeCast128(totalLPY - amount1);
        }

        emit Withdrawal(sender, pool, amountX, amountY);
    }

    function _burn(
        address from,
        address recipeint,
        address token,
        uint256 pool,
        uint256 liquidity,
        uint256 poolReserve,
        uint256 totalReserve,
        uint256 totalBalance,
        uint256 totalLp,
        bool option
    ) private returns (uint256 realAmount, uint256 reserveAmount) {
        if (liquidity == 0) return (0, 0);
        if (option) {
            balanceOf[from][pool].liquidityX -= liquidity;
        } else {
            balanceOf[from][pool].liquidityY -= liquidity;
        }

        reserveAmount = (liquidity * poolReserve) / totalLp;
        if (token != address(0)) {
            //ERC20
            realAmount = (reserveAmount * totalBalance) / totalReserve;
            TransferHelper.safeTransfer(token, recipeint, realAmount);
        } else {
            realAmount = reserveAmount;
            TransferHelper.safeTransferETH(recipeint, realAmount);
        }
    }
}
