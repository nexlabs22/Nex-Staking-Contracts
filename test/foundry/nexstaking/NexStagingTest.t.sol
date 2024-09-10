// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import "forge-std/Test.sol";
import "../../../contracts/NexStaking.sol";
import "../../../contracts/factory/ERC4626Factory.sol";
import "../mocks/MockERC20.sol";
import "../../../contracts/interfaces/IWETH9.sol";
import "../../../contracts/libraries/CalculationHelpers.sol";
import "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";

contract NexStakingTest is Test {
    NexStaking public nexStaking;
    ERC4626Factory public erc4626Factory;
    IWETH9 public weth;
    ISwapRouter public swapRouterV3;

    address public owner;
    address public user1;
    address public user2;

    IERC20 public nexLabsToken;
    IERC20 public indexToken1;
    IERC20 public indexToken2;
    IERC20 public rewardToken1;
    IERC20 public rewardToken2;

    address wethAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // WETH Mainnet
    address uniswapV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564; // Uniswap V3 Mainnet

    uint256 mainnetFork;

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        // Fork the Ethereum mainnet
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);

        console.log("msg.sender", msg.sender);
        console.log("address(this)", address(this));

        // Define the owner and users
        owner = address(this); // Set the test contract as the owner
        user1 = address(1);
        user2 = address(2);

        // Set up tokens using mainnet addresses
        nexLabsToken = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // USDC on mainnet
        indexToken1 = IERC20(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599); // WBTC on mainnet
        indexToken2 = IERC20(0x514910771AF9Ca656af840dff83E8264EcF986CA); // LINK on mainnet
        rewardToken1 = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // USDC on mainnet
        rewardToken2 = IERC20(0xdAC17F958D2ee523a2206206994597C13D831ec7); // USDT on mainnet

        weth = IWETH9(wethAddress);
        swapRouterV3 = ISwapRouter(uniswapV3Router);

        // Deploy ERC4626 Factory on forked chain and initialize it
        erc4626Factory = new ERC4626Factory();
        // erc4626Factory.initialize();

        // Deploy and initialize NexStaking with correct ownership
        deployAndInitializeNexStaking();

        // Deal tokens to users
        deal(address(indexToken1), user1, 1000e18);
        deal(address(indexToken2), user2, 1000e18);
        deal(address(rewardToken1), user1, 500e18);
        deal(address(rewardToken2), user2, 500e18);
    }

    function deployAndInitializeNexStaking() internal {
        address[] memory indexTokens = new address[](2);
        address[] memory rewardTokens = new address[](2);
        uint8[] memory swapVersions = new uint8[](2);

        indexTokens[0] = address(indexToken1);
        indexTokens[1] = address(indexToken2);
        rewardTokens[0] = address(rewardToken1);
        rewardTokens[1] = address(rewardToken2);
        swapVersions[0] = 3; // Uniswap V3 for IDX1
        swapVersions[1] = 3; // Uniswap V3 for IDX2

        nexStaking = new NexStaking();

        // Initialize NexStaking with the correct owner context
        nexStaking.initialize(
            address(nexLabsToken),
            indexTokens,
            rewardTokens,
            swapVersions,
            address(erc4626Factory),
            address(swapRouterV3),
            address(weth),
            3 // Fee set to 5%
        );
    }

    function testInitializeStaking() public {
        // Test the initialization process of the NexStaking contract

        assertEq(address(nexStaking.nexLabsToken()), address(nexLabsToken), "NexLabs Token is incorrect");
        assertEq(nexStaking.poolTokensAddresses(0), address(indexToken1), "Index Token 1 is incorrect");
        assertEq(nexStaking.poolTokensAddresses(1), address(indexToken2), "Index Token 2 is incorrect");
        assertEq(nexStaking.rewardTokensAddresses(0), address(rewardToken1), "Reward Token 1 is incorrect");
        assertEq(nexStaking.rewardTokensAddresses(1), address(rewardToken2), "Reward Token 2 is incorrect");
    }

    function testStakeTokens() public {
        // Test nexStaking functionality
        vm.startPrank(user1);

        uint256 initialShares = nexStaking.getUserShares(user1, address(indexToken1));
        assertEq(initialShares, 0, "Initial shares should be zero");

        indexToken1.approve(address(nexStaking), 500e18);
        nexStaking.stake(address(indexToken1), 500e18);

        uint256 sharesAfterStake = nexStaking.getUserShares(user1, address(indexToken1));
        assertGt(sharesAfterStake, 0, "Shares should increase after nexStaking");

        vm.stopPrank();
    }

    function testUnstakeTokens() public {
        // Test unstaking functionality
        vm.startPrank(user1);

        indexToken1.approve(address(nexStaking), 500e18);
        nexStaking.stake(address(indexToken1), 500e18);

        // Unstake partial amount
        nexStaking.unstake(address(indexToken1), address(indexToken1), 250e18);

        uint256 remainingShares = nexStaking.getUserShares(user1, address(indexToken1));
        assertEq(remainingShares, 250e18, "Shares after partial unstake should be 250");

        vm.stopPrank();
    }

    function testUnstakeWithRewards() public {
        // Test unstaking functionality with reward tokens
        vm.startPrank(user2);

        indexToken2.approve(address(nexStaking), 400e18);
        nexStaking.stake(address(indexToken2), 400e18);

        // Unstake and swap to a reward token
        nexStaking.unstake(address(indexToken2), address(rewardToken2), 200e18);

        uint256 remainingShares = nexStaking.getUserShares(user2, address(indexToken2));
        assertEq(remainingShares, 200e18, "Shares after partial unstake should be 200");

        vm.stopPrank();
    }

    function testCalculateAmountAfterFee() public {
        // Test the fee deduction logic
        (uint256 fee, uint256 amountAfterFee) = CalculationHelpers.calculateAmountAfterFeeAndFee(1e18, 3);
        uint256 expectedFee = (1e18 * 3) / 10000;
        uint256 expectedAmount = 1e18 - expectedFee;
        assertEq(fee, expectedFee, "Fee should be 3%");
        assertEq(amountAfterFee, expectedAmount, "Amount after fee should be 95%");
    }
}
