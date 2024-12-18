// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

abstract contract LPTOKEN {
    function mint(
        uint256 amount,
        bool tokenSide,
        address recipient
    ) internal pure returns (uint256 lpToken) {
        if (tokenSide) {
            lpToken = amount;
        } else {
            lpToken = amount;
        }
        recipient = address(0);
    }

    /// we'll take some LP tokens and send it to burn address, DONT FORGET ITS IMPORTANT
}
