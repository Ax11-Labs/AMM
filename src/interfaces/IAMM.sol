// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.28;

import {IERC20} from "./IERC20.sol";

interface IAMM {
    error INVALID_ADDRESS();
    error INVALID_PRICE();
    error OVERFLOW();
    error EXPIRED();
    error UNINITIALIZED();
    error INVALID_VALUE();
    error INSUFFICIENT_AMOUNT();
    error SLIPPAGE_EXCEEDED();

    event Deposit(
        address indexed user,
        uint256 indexed pool,
        uint256 liquidityX,
        uint256 liquidityY
    );

    event Withdrawal(
        address indexed user,
        uint256 indexed pool,
        uint256 amountX,
        uint256 amountY
    );

    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 indexed id,
        uint256 amount
    );

    event Transfer(
        address indexed from,
        address indexed to,
        uint256 indexed id,
        bool isX,
        uint256 amount
    );

    struct Pool {
        address tokenX;
        address tokenY;
        uint256 lastPriceX; // 38 decimals
        uint128 reserveX; // virtual
        uint128 reserveY; // virtual
        uint128 lastBalanceX; // real
        uint128 lastBalanceY; //real
        uint128 totalLpX;
        uint128 totalLpY;
    }

    struct Position {
        uint256 liquidityX;
        uint256 liquidityY;
    }
}
