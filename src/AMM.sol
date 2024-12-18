// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IAMM} from "./interfaces/IAMM.sol";
import {IERC20} from "./interfaces/IERC20.sol";
import {TransferHelper} from "./libraries/TransferHelper.sol";
import {LPTOKEN} from "./LpToken.sol";

contract AMM is IAMM, LPTOKEN {
    mapping(uint256 => Pool) public PoolInfo;

    /// @notice get the pool id without storage reading
    function getPool(
        IERC20 token0,
        IERC20 token1
    ) public pure returns (uint256 pool, IERC20 tokenX, IERC20 tokenY) {
        require(token0 != token1, "IDENTICAL");
        tokenX = token0 < token1 ? token0 : token1;
        tokenY = token0 < token1 ? token1 : token0;
        pool = uint256(keccak256(abi.encodePacked(tokenX, tokenY)));
    }

    /// @notice This function facilitates both pool creation and liquidity deposit.
    function deposit(
        IERC20 token0, // please sort it
        IERC20 token1, // please sort it
        uint256 amountX,
        uint256 amountY,
        uint128 priceX, // please input Q64.64 price
        uint256 slippage, // price bound to dictate min,max
        address toX,
        address toY,
        uint256 deadline
    ) external returns (uint256 liquidityX, uint256 liquidityY, uint256 pool) {
        require(deadline > block.timestamp - 1, "EXPIRED");
        require(priceX != 0, "INVALID_PRICE");
        (pool, token0, token1) = getPool(token0, token1); // sort

        Pool storage _pool = PoolInfo[pool];
        //if the pool doesn't exist, create pool
        if (address(_pool.tokenX) == address(0)) {
            _pool.tokenX = token0;
            _pool.tokenY = token1;
        }

        deadline = _pool.priceX; // reuse deadline as poolPriceX
        uint256 balanceX = token0.balanceOf(address(this));
        uint256 balanceY = token1.balanceOf(address(this));

        // if any price or balance is zero, select a new price
        if (balanceX == 0 || balanceY == 0 || deadline == 0) {
            require(amountX != 0 && amountY != 0, "SINGLE_INIT");
            _pool.priceX = priceX;
            _pool.priceY = uint128((uint256(1) << 128) / priceX);
        } else {
            require(
                (deadline > priceX ? deadline - priceX : priceX - deadline) <
                    slippage + 1,
                "SLIPPAGE"
            );
        }

        if (amountX != 0) {
            TransferHelper.safeTransferFrom(
                tokenX,
                msg.sender,
                address(this),
                amountX
            );
            unchecked {
                amountX = (tokenX.balanceOf(address(this))) - balanceX;
                // get actual amountIn, reuse amountX
            }
            liquidityX = mint(amountX, true, toX);
        }

        if (amountY != 0) {
            TransferHelper.safeTransferFrom(
                tokenY,
                msg.sender,
                address(this),
                amountY
            );
            unchecked {
                amountY = (tokenY.balanceOf(address(this))) - balanceY;
                // get actual amountIn, reuse amountX
            }
            liquidityY = mint(amountY, false, toY);
        }
    }

    function withdraw(
        IERC20 tokenX,
        IERC20 tokenY,
        uint256 amountLPX,
        uint256 amountLPY,
        uint128 priceX, // please input Q64.64 price
        uint256 slippage, // price bound to dictate min,max
        address toX,
        address toY,
        uint256 deadline
    ) external returns (uint256 amountX, uint256 amountY) {
        require(deadline > block.timestamp - 1, "EXPIRED");
        require(priceX != 0, "INVALID_PRICE");

        Pool storage _pool = PoolInfo[getPool(tokenX, tokenY)];

        require(
            address(tokenX) != address(0) && address(tokenY) != address(0),
            "UNINITIALIZED"
        );
        // deadline = _pool.price
    }
}
