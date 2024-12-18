// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {IERC20} from "./IERC20.sol";

interface IAMM {
    error INVALID_ADDRESS();
    error OVERFLOW();

    struct Pool {
        IERC20 tokenX;
        // uint96 reserveX;
        IERC20 tokenY;
        // uint96 reserveY;
        uint128 priceX;
        uint128 priceY;
    }
}
