// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {IERC20} from "./IERC20.sol";

interface IAMM {
    error INVALID_ADDRESS();
    error INVALID_PRICE();
    error OVERFLOW();
    error EXPIRED();
    error UNINITIALIZED();

    event Deposit(address indexed user, uint256 indexed pool, uint256 liquidityX, uint256 liquidityY);

    event Approval(address indexed owner, address indexed spender, uint256 indexed id, uint256 amount);

    event Transfer(address indexed from, address indexed to, uint256 indexed id, bool isX, uint256 amount);

    struct Pool {
        address tokenX;
        address tokenY;
        uint128 reserveX; // virtual
        uint128 reserveY; // virtual
        uint128 lastBalanceX; // real
        uint128 lastBalanceY; //real
        uint128 lastPriceX; // 19 decimals
        uint256 totalLpX;
        uint256 totalLpY;
    }

    struct Position {
        uint256 liquidityX;
        uint256 liquidityY;
    }
}
