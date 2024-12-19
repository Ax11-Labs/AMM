// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {IERC20} from "./IERC20.sol";

interface IAMM {
    error INVALID_ADDRESS();
    error INVALID_PRICE();
    error OVERFLOW();
    error EXPIRED();

    event Deposit(
        address indexed user,
        uint256 indexed pool,
        uint256 liquidityX,
        uint256 liquidityY
    );

    struct Pool {
        address tokenX;
        address tokenY;
        uint128 reserveX;
        uint128 reserveY;
        uint256 lastRatio; // 19 decimals
        uint128 lastPriceX; // 19 decimals
        uint256 totalLpX;
        uint256 totalLpY;
    }

    struct Individual {
        uint256 liquidityX;
        uint256 liquidityY;
    }
}
