// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test, console} from "forge-std/Test.sol";
import {AMM} from "../src/AMM.sol";

// Simple ERC20 Implementation for Testing
contract MockERC20 {
    string public name;
    string public symbol;
    uint8 public decimals;
    uint256 public totalSupply;

    mapping(address => uint256) private balances;
    mapping(address => mapping(address => uint256)) private allowances;

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _initialSupply
    ) {
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
        require(
            balances[msg.sender] >= amount,
            "ERC20: transfer amount exceeds balance"
        );
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function approve(address spender, uint256 amount) public returns (bool) {
        allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public returns (bool) {
        require(
            balances[sender] >= amount,
            "ERC20: transfer amount exceeds balance"
        );
        require(
            allowances[sender][msg.sender] >= amount,
            "ERC20: transfer amount exceeds allowance"
        );
        _transfer(sender, recipient, amount);
        allowances[sender][msg.sender] -= amount;
        return true;
    }

    function allowance(
        address owner,
        address spender
    ) public view returns (uint256) {
        return allowances[owner][spender];
    }

    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal {
        balances[sender] -= amount;
        balances[recipient] += amount;
        emit Transfer(sender, recipient, amount);
    }
}

// Test Contract
contract SwapTest is Test {
    AMM public amm;
    MockERC20 public usdc;
    MockERC20 public weth;

    address public user = address(0x1234);

    function setUp() public {
        amm = new AMM();
        usdc = new MockERC20("Mock USDC", "USDC", 6, 1_000_000e6);
        weth = new MockERC20("Mock WETH", "WETH", 18, 1_000_000e18);

        vm.deal(user, 10 ether);
        usdc.transfer(user, 10000e6);
        weth.transfer(user, 10000e18);
    }

    function testSwapExactInput() public {
        uint256 amountETH = 1 ether;
        uint256 amountWETH = 100e18;
        uint256 amountUSDC = 1000e6;
        uint256 priceX = 2000 * (1e38); // Approximate price of ETH/USDC
        uint256 slippage = 5e16; // 5%
        uint256 deadline = block.timestamp + 1 hours;

        // Approve tokens for deposit
        vm.prank(user);
        usdc.approve(address(amm), type(uint256).max);
        vm.prank(user);
        weth.approve(address(amm), type(uint256).max);

        // Deposit WETH and USDC into the pool
        vm.prank(user);
        amm.deposit(
            address(usdc),
            address(weth),
            amountUSDC,
            amountWETH,
            priceX,
            slippage,
            user,
            user,
            deadline
        );

        // Swap WETH for USDC
        uint256 swapAmountIn = 5e18;
        uint256 swapAmountOutMin = 0; // Minimum expected USDC
        vm.prank(user);
        weth.approve(address(amm), 50e18);
        console.log(weth.balanceOf(user));

        vm.prank(user);
        uint256 gasStart = gasleft();
        amm.swapExactInput(
            address(weth),
            address(usdc),
            1e18,
            swapAmountOutMin,
            user,
            deadline
        );
        uint256 gasUsed = gasStart - gasleft();
        console.log("GAS - swapExactInput() = ", gasUsed);

        // Verify balances after the swap
        uint256 userWethBalance = weth.balanceOf(user);
        uint256 userUsdcBalance = usdc.balanceOf(user);

        console.log("User WETH Balance After Swap: ", userWethBalance);
        console.log("User USDC Balance After Swap: ", userUsdcBalance);

        (uint256 pool, , ) = amm.getPool(address(weth), address(usdc));
        (
            ,
            ,
            uint256 priceZ,
            uint256 reserveX,
            uint256 reserveY,
            ,
            ,
            uint256 tLPX,
            uint256 tLPY
        ) = amm.PoolInfo(pool);

        console.log("Updated Pool Price: ", priceZ);
        console.log("Updated Reserve X: ", reserveX);
        console.log("Updated Reserve Y: ", reserveY);
        console.log("Total LPX: ", tLPX);
        console.log("Total LPY: ", tLPY);

        // Ensure the reserves are updated correctly
        assert(reserveX > 0);
        assert(reserveY > 0);
        assert(userUsdcBalance > 0); // User must have received USDC
    }
}
//9900000000000000000000
//1000000000000000000
