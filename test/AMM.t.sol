// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";

import {AMM} from "../src/AMM.sol"; // Replace with the actual path to your contract

// Simple ERC20 Implementation for Testing
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    mapping(address => uint256) private balances;
    mapping(address => mapping(address => uint256)) private allowances;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    constructor(string memory _name, string memory _symbol, uint8 _decimals, uint256 _initialSupply) {
        name = _name;
        symbol = _symbol;
        decimals = _decimals;
        totalSupply = _initialSupply;
        balances[msg.sender] = _initialSupply;
    }

    function balanceOf(address account) public view returns (uint256) {
        return balances[account];
    }

    function transfer(address recipient, uint256 amount) public returns (bool) {
        require(balances[msg.sender] >= amount, "ERC20: transfer amount exceeds balance");
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount) public returns (bool) {
        require(balances[sender] >= amount, "ERC20: transfer amount exceeds balance");
        require(allowances[sender][msg.sender] >= amount, "ERC20: transfer amount exceeds allowance");
        _transfer(sender, recipient, amount);
        allowances[sender][msg.sender] -= amount;
        return true;
    }

    function allowance(address owner, address spender) public view returns (uint256) {
        return allowances[owner][spender];
    }

    function _transfer(address sender, address recipient, uint256 amount) internal {
        balances[sender] -= amount;
        balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
    }
}

// Test Contract
contract DepositTest is Test {
    AMM public amm;
    MockERC20 public usdc;

    address public user = address(0x1234);
    address public lpRecipientX = address(0xABCD);
    address public lpRecipientY = address(0x5678);

    function setUp() public {
        // Deploy contract and mock USDC token
        amm = new AMM();
        usdc = new MockERC20("Mock USDC", "USDC", 6, 1_000_000e6); // 1M USDC (6 decimals)

        // Fund user with ETH and USDC
        vm.deal(user, 10 ether); // Fund user with 10 ETH
        usdc.transfer(user, 10_000e6); // Fund user with 10,000 USDC
    }

    function testDepositETHUSDC() public {
        uint256 amountETH = 1 ether; // 1 ETH
        uint256 amountUSDC = 1000e6; // 1,000 USDC
        uint256 priceX = 4195 * (1e19); // Approximate price of ETH/USDC with 19 decimals
        uint256 slippage = 5e16; // 0.05 (5%)
        uint256 deadline = block.timestamp + 1 hours;

        // Approve USDC transfer
        vm.prank(user);
        usdc.approve(address(amm), amountUSDC);

        // Start measuring gas
        uint256 gasStart = gasleft();

        // Deposit ETH/USDC
        vm.prank(user);
        amm.deposit{value: amountETH}(
            address(0), // ETH
            address(usdc),
            amountETH,
            amountUSDC,
            priceX,
            slippage,
            lpRecipientX,
            lpRecipientY,
            deadline
        );

        // Measure gas used
        uint256 gasUsed = gasStart - gasleft();

        console.log("Gas Used for deposit function:", gasUsed);

        //  Verify LP tokens were minted
        uint256 pool;
        (pool,,) = amm.getPool(address(0), address(usdc));
        uint256 lpX;
        uint256 lpY;
        (lpX,) = amm.balanceOf(lpRecipientX, pool); // Replace `0` with the pool ID
        (, lpY) = amm.balanceOf(lpRecipientY, pool); // Replace `0` with the pool ID

        console.log("lpX:", lpX);
        console.log("lpY:", lpY);
        (,,,,,,, lpX, lpY) = amm.PoolInfo(pool);
        console.log("lpX:", lpX);
        console.log("lpY:", lpY);
    }
}
