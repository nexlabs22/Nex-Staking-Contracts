// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISwapRouter} from "@uniswap/v3-periphery/contracts/interfaces/ISwapRouter.sol";
import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IUniswapV3Factory} from "@uniswap/v3-core/contracts/interfaces/IUniswapV3Factory.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/contracts/access/OwnableUpgradeable.sol";

import {MockERC20} from "../mocks/MockERC20.sol";
import {NexStaking} from "../../../contracts/NexStaking.sol";
import {FeeManager} from "../../../contracts/FeeManager.sol";
import {ERC4626Factory} from "../../../contracts/factory/ERC4626Factory.sol";
import {IWETH9} from "../../../contracts/interfaces/IWETH9.sol";
import {CalculationHelpers} from "../../../contracts/libraries/CalculationHelpers.sol";
import {INonfungiblePositionManager} from "../../../contracts/uniswap/INonfungiblePositionManager.sol";
import {SwapHelpers} from "../../../contracts/libraries/SwapHelpers.sol";

contract NexStakingTest is Test {
    NexStaking public nexStaking;
    FeeManager public feeManager;
    ERC4626Factory public erc4626Factory;
    IWETH9 public weth;
    ISwapRouter public swapRouterV3;

    MockERC20 public indexToken1;
    MockERC20 public indexToken2;
    MockERC20 public rewardToken1;
    MockERC20 public rewardToken2;
    MockERC20 public nexLabsToken;

    address user = address(1);
    address user2 = address(2);
    address owner = address(10);

    uint256 mainnetFork;

    address uniswapV3Router = 0xE592427A0AEce92De3Edee1F18E0157C05861564;
    address wethAddress = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address unsiwapV2Router = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address uniswapV3FactoryAddress = 0x1F98431c8aD98523631AE4a59f267346ea31F984;
    address nonfungiblePositionManagerAddress = 0xC36442b4a4522E871399CD717aBDD847Ab11FE88;

    IUniswapV3Factory uniswapV3Factory = IUniswapV3Factory(uniswapV3FactoryAddress);
    INonfungiblePositionManager nonfungiblePositionManager =
        INonfungiblePositionManager(nonfungiblePositionManagerAddress);

    IERC20[] indexTokens;
    IERC20[] rewardTokens;

    uint256 public initialBalance = 1000e18;

    event Staked(
        address indexed user,
        address indexed tokenAddress,
        uint256 indexed amount,
        uint256 totalStakedAmount,
        uint256 poolSize,
        address vault,
        uint256 shares,
        uint256 timestamp
    );

    event Unstaked(
        address indexed user,
        address indexed tokenAddress,
        uint256 unstakedAmount,
        uint256 rewardAmount,
        uint256 poolSize,
        address vault,
        uint256 sharesRedeemed,
        uint256 timestamp
    );

    event RewardTokensSwapped(
        address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut, address user
    );

    event RewardTokensUpdated(address[] newRewardTokens);

    event PoolTokensUpdated(address[] newPoolTokens);

    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    function setUp() public {
        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);

        deal(address(this), 10000 ether);

        swapRouterV3 = ISwapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
        weth = IWETH9(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2);

        deployTokens();

        deployAndInitializeContracts();

        addLiquidityToAllPools();

        console.log("Setup complete.");
    }

    function testStakeTokens() public {
        console.log("-----------------testStakeTokens-----------------");

        vm.startPrank(user);

        deal(address(indexTokens[0]), user, 500e18);

        (, uint256 amountAfterFee) = CalculationHelpers.calculateAmountAfterFeeAndFee(500e18, 3);

        address vault = erc4626Factory.tokenAddressToVaultAddress(address(indexTokens[0]));

        indexTokens[0].approve(address(nexStaking), 500e18);
        vm.expectEmit(true, true, true, true);
        emit Staked(
            user,
            address(indexTokens[0]),
            amountAfterFee,
            amountAfterFee,
            amountAfterFee,
            vault,
            amountAfterFee,
            block.timestamp
        );
        nexStaking.stake(address(indexTokens[0]), 500e18);

        uint256 sharesAfterStake = nexStaking.getUserShares(user, address(indexTokens[0]));
        assertGt(sharesAfterStake, 0, "Shares should increase after staking");

        vm.stopPrank();

        console.log("-----------------testStakeTokens-----------------");
    }

    function testUnstake() public {
        vm.startPrank(user);

        deal(address(indexTokens[0]), user, 500e18);

        (, uint256 amountAfterFee) = CalculationHelpers.calculateAmountAfterFeeAndFee(500e18, 3);

        address vault = erc4626Factory.tokenAddressToVaultAddress(address(indexTokens[0]));

        indexTokens[0].approve(address(nexStaking), 500e18);
        vm.expectEmit(true, true, true, true);
        emit Staked(
            user,
            address(indexTokens[0]),
            amountAfterFee,
            amountAfterFee,
            amountAfterFee,
            vault,
            amountAfterFee,
            block.timestamp
        );
        nexStaking.stake(address(indexTokens[0]), 500e18);

        uint256 userBalanceAfterStake = indexTokens[0].balanceOf(user);

        uint256 sharesAfterStake = nexStaking.getUserShares(user, address(indexTokens[0]));
        assertGt(sharesAfterStake, 0, "Shares should increase after staking");

        console.log("Vault Index token balance: ", indexTokens[0].balanceOf(vault));
        ERC4626(vault).approve(address(nexStaking), 50000e18);

        nexStaking.unstake(address(indexTokens[0]), address(indexTokens[0]), amountAfterFee);

        uint256 userBalanceAfterUnStake = indexTokens[0].balanceOf(user);

        assertGt(userBalanceAfterUnStake, userBalanceAfterStake);

        uint256 remainingShares = nexStaking.getUserShares(user, address(indexTokens[0]));
        assertEq(remainingShares, 0, "All shares should be redeemed");

        console.log("Vault balance at the end: ", indexTokens[0].balanceOf(vault));
        console.log("User balance at the end: ", indexTokens[0].balanceOf(user));

        vm.stopPrank();
    }

    function testUnstakeAllTokensWithSameTokenReward() public {
        vm.startPrank(user);
        deal(address(indexTokens[0]), user, 1000e18);

        deal(address(indexTokens[0]), user, 500e18);

        address vault = erc4626Factory.tokenAddressToVaultAddress(address(indexTokens[0]));
        (, uint256 amountAfterFee) = CalculationHelpers.calculateAmountAfterFeeAndFee(500e18, 3);

        indexTokens[0].approve(address(nexStaking), 500e18);
        nexStaking.stake(address(indexTokens[0]), 500e18);

        uint256 userBalanceAfterStake = indexTokens[0].balanceOf(user);

        ERC4626(vault).approve(address(nexStaking), 500e18);

        deal(address(indexTokens[0]), vault, 1000e18);

        console.log("Vault balance: ", ERC4626(vault).balanceOf(user));

        uint256 sharesToRedeem = nexStaking.getSharesToRedeemAmount(address(indexTokens[0]), user, amountAfterFee);
        uint256 rewardAmount = nexStaking.getPureRewardAmount(address(indexTokens[0]), user, amountAfterFee);

        console.log("Share to redeem", sharesToRedeem);
        console.log("Reward Amount", rewardAmount);

        nexStaking.unstake(address(indexTokens[0]), address(indexTokens[0]), amountAfterFee);

        uint256 userBalanceAfterUnStake = indexTokens[0].balanceOf(user);

        assertGt(userBalanceAfterUnStake, userBalanceAfterStake);

        uint256 remainingShares = nexStaking.getUserShares(user, address(indexTokens[0]));
        assertEq(remainingShares, 0, "All shares should be redeemed");

        console.log("Vault balance at the end: ", indexTokens[0].balanceOf(vault));
        console.log("User balance at the end: ", indexTokens[0].balanceOf(user));

        vm.stopPrank();
    }

    function testUnstakeSomeTokensWithSameTokenReward() public {
        vm.startPrank(user);

        deal(address(indexTokens[0]), user, 500e18);

        indexTokens[0].approve(address(nexStaking), 500e18);
        nexStaking.stake(address(indexTokens[0]), 500e18);

        uint256 userBalanceBeforeUnStake = indexTokens[0].balanceOf(user);

        address vault = erc4626Factory.tokenAddressToVaultAddress(address(indexTokens[0]));
        ERC4626(vault).approve(address(nexStaking), type(uint256).max);

        console.log("Vault total assets: ", ERC4626(vault).totalAssets());

        deal(address(indexTokens[0]), vault, 1000e18);

        console.log("Vault balance: ", ERC4626(vault).balanceOf(user));

        (, uint256 amountAfterFee) = CalculationHelpers.calculateAmountAfterFeeAndFee(250e18, 3);

        uint256 stakingContractBalance = indexTokens[0].balanceOf(address(nexStaking));

        console.log("Staking contract balance before unstake: ", stakingContractBalance);

        nexStaking.unstake(address(indexTokens[0]), address(indexTokens[0]), amountAfterFee);

        uint256 userBalanceAfterUnStake = indexTokens[0].balanceOf(user);

        console.log("User balance after unstake: ", userBalanceAfterUnStake);

        assertGt(userBalanceAfterUnStake, userBalanceBeforeUnStake);

        uint256 remainingShares = nexStaking.getUserShares(user, address(indexTokens[0]));
        uint256 expectedRemainingShares = ERC4626(vault).balanceOf(user);

        console.log("Remaining shares: ", remainingShares);
        assertEq(remainingShares, expectedRemainingShares, "All shares should be redeemed");

        vm.stopPrank();
    }

    function testUnstakeAllTokensWithDifferentRewardToken() public {
        console.log(
            "----------------------------testUnstakeAllTokensWithDifferentRewardToken----------------------------"
        );
        vm.startPrank(user);
        deal(address(indexTokens[0]), user, 500e18);

        indexTokens[0].approve(address(nexStaking), 500e18);
        nexStaking.stake(address(indexTokens[0]), 500e18);

        uint256 userBalanceBeforeUnStake = indexTokens[0].balanceOf(user);

        address vault = erc4626Factory.tokenAddressToVaultAddress(address(indexTokens[0]));
        ERC4626(vault).approve(address(nexStaking), type(uint256).max);

        console.log("Vault total assets: ", ERC4626(vault).totalAssets());

        deal(address(indexTokens[0]), vault, 1000e18);

        console.log("Vault balance: ", ERC4626(vault).balanceOf(user));

        (, uint256 amountAfterFee) = CalculationHelpers.calculateAmountAfterFeeAndFee(500e18, 3);

        uint256 userRewardTokenBalanceBeforeUnstake = rewardTokens[1].balanceOf(user);
        uint256 stakingContractBalance = indexTokens[0].balanceOf(address(nexStaking));

        console.log("User reward token balance before unstake: ", userRewardTokenBalanceBeforeUnstake);
        console.log("Staking contract balance before unstake: ", stakingContractBalance);

        nexStaking.unstake(address(indexTokens[0]), address(rewardTokens[1]), amountAfterFee);

        uint256 userRewardTokenBalanceAfterUnstake = rewardTokens[1].balanceOf(user);
        uint256 userBalanceAfterUnStake = indexTokens[0].balanceOf(user);

        console.log("User reward token balance after unstake: ", userRewardTokenBalanceAfterUnstake);
        console.log("User balance after unstake: ", userBalanceAfterUnStake);

        assertGt(userRewardTokenBalanceAfterUnstake, userRewardTokenBalanceBeforeUnstake);
        assertGt(userBalanceAfterUnStake, userBalanceBeforeUnStake);

        uint256 remainingShares = nexStaking.getUserShares(user, address(indexTokens[0]));
        console.log("Remaining shares: ", remainingShares);
        assertEq(remainingShares, 0, "All shares should be redeemed");

        console.log("Vault balance at the end: ", indexTokens[0].balanceOf(vault));

        vm.stopPrank();
        console.log(
            "----------------------------testUnstakeAllTokensWithDifferentRewardToken----------------------------"
        );
    }

    function testUnstakeSomeTokensWithDifferentRewardToken() public {
        vm.startPrank(user);

        deal(address(indexTokens[0]), user, 500e18);
        indexTokens[0].approve(address(nexStaking), 500e18);
        nexStaking.stake(address(indexTokens[0]), 500e18);

        (,,, uint256 stakeAmountAfterStake,) = nexStaking.positions(user, address(indexTokens[0]));

        uint256 userBalanceBeforeUnStake = indexTokens[0].balanceOf(user);

        address vault = erc4626Factory.tokenAddressToVaultAddress(address(indexTokens[0]));
        ERC4626(vault).approve(address(nexStaking), type(uint256).max);

        console.log("Vault total assets: ", ERC4626(vault).totalAssets());

        deal(address(indexTokens[0]), vault, 1000e18);

        console.log("Vault balance: ", ERC4626(vault).balanceOf(user));

        (, uint256 amountAfterFee) = CalculationHelpers.calculateAmountAfterFeeAndFee(200e18, 3);

        uint256 userRewardTokenBalanceBeforeUnstake = rewardTokens[1].balanceOf(user);
        uint256 stakingContractBalance = indexTokens[0].balanceOf(address(nexStaking));

        console.log("User reward token balance before unstake: ", userRewardTokenBalanceBeforeUnstake);
        console.log("Staking contract balance before unstake: ", stakingContractBalance);

        nexStaking.unstake(address(indexTokens[0]), address(rewardTokens[1]), amountAfterFee);

        (,,, uint256 stakeAmountAfterUnStake,) = nexStaking.positions(user, address(indexTokens[0]));

        uint256 userRewardTokenBalanceAfterUnstake = rewardTokens[1].balanceOf(user);
        uint256 userBalanceAfterUnStake = indexTokens[0].balanceOf(user);

        console.log("User reward token balance after unstake: ", userRewardTokenBalanceAfterUnstake);
        console.log("User balance after unstake: ", userBalanceAfterUnStake);

        assertGt(userRewardTokenBalanceAfterUnstake, userRewardTokenBalanceBeforeUnstake);
        assertGt(userBalanceAfterUnStake, userBalanceBeforeUnStake);

        uint256 expectedRemainingShares = ERC4626(vault).balanceOf(user);
        uint256 remainingShares = nexStaking.getUserShares(user, address(indexTokens[0]));

        console.log("Expected shares: ", expectedRemainingShares);
        console.log("Remaining shares: ", remainingShares);

        assertEq(remainingShares, expectedRemainingShares, "All shares should be redeemed");
        assertLt(stakeAmountAfterUnStake, stakeAmountAfterStake);

        vm.stopPrank();
    }

    function testUnstakeAllTokensWithTwoUsersWitDifferentReward() public {
        vm.startPrank(user);
        deal(address(indexTokens[0]), user, 800e18);
        // User stakes 500 tokens
        indexTokens[0].approve(address(nexStaking), 800e18);
        nexStaking.stake(address(indexTokens[0]), 800e18);

        uint256 userBalanceBeforeUnStake = indexTokens[0].balanceOf(user);

        address vault = erc4626Factory.tokenAddressToVaultAddress(address(indexTokens[0]));
        ERC4626(vault).approve(address(nexStaking), type(uint256).max);

        console.log("Vault total assets: ", ERC4626(vault).totalAssets());

        vm.stopPrank();

        vm.startPrank(user2);
        deal(address(indexTokens[0]), user2, 200e18);
        // User stakes 500 tokens
        indexTokens[0].approve(address(nexStaking), 200e18);
        nexStaking.stake(address(indexTokens[0]), 200e18);

        uint256 user2BalanceBeforeUnStake = indexTokens[0].balanceOf(user2);

        address vault2 = erc4626Factory.tokenAddressToVaultAddress(address(indexTokens[0]));
        ERC4626(vault2).approve(address(nexStaking), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user);
        deal(address(indexTokens[0]), vault, 1000e18);

        console.log("Vault balance: ", ERC4626(vault).balanceOf(user));

        (, uint256 amountAfterFee) = CalculationHelpers.calculateAmountAfterFeeAndFee(800e18, 3);

        uint256 userRewardTokenBalanceBeforeUnstake = rewardTokens[1].balanceOf(user);
        uint256 stakingContractBalance = indexTokens[0].balanceOf(address(nexStaking));

        console.log("User reward token balance before unstake: ", userRewardTokenBalanceBeforeUnstake);
        console.log("Staking contract balance before unstake: ", stakingContractBalance);

        nexStaking.unstake(address(indexTokens[0]), address(rewardTokens[1]), amountAfterFee);

        uint256 userRewardTokenBalanceAfterUnstake = rewardTokens[1].balanceOf(user);
        uint256 userBalanceAfterUnStake = indexTokens[0].balanceOf(user);

        console.log("User reward token balance after unstake: ", userRewardTokenBalanceAfterUnstake);
        console.log("User balance after unstake: ", userBalanceAfterUnStake);

        assertGt(userRewardTokenBalanceAfterUnstake, userRewardTokenBalanceBeforeUnstake);
        assertGt(userBalanceAfterUnStake, userBalanceBeforeUnStake);

        uint256 remainingShares = nexStaking.getUserShares(user, address(indexTokens[0]));
        console.log("Remaining shares: ", remainingShares);
        assertEq(remainingShares, 0, "All shares should be redeemed");
        vm.stopPrank();

        vm.startPrank(user2);

        console.log("Vault balance: ", ERC4626(vault).balanceOf(user2));

        (, uint256 amountAfterFee2) = CalculationHelpers.calculateAmountAfterFeeAndFee(200e18, 3);

        uint256 user2RewardTokenBalanceBeforeUnstake = rewardTokens[1].balanceOf(user2);
        uint256 staking2ContractBalance = indexTokens[0].balanceOf(address(nexStaking));

        console.log("User reward token balance before unstake: ", user2RewardTokenBalanceBeforeUnstake);
        console.log("Staking contract balance before unstake: ", staking2ContractBalance);

        nexStaking.unstake(address(indexTokens[0]), address(rewardTokens[1]), amountAfterFee2);

        uint256 user2RewardTokenBalanceAfterUnstake = rewardTokens[1].balanceOf(user2);
        uint256 user2BalanceAfterUnStake = indexTokens[0].balanceOf(user2);

        console.log("User reward token balance after unstake: ", user2RewardTokenBalanceAfterUnstake);
        console.log("User balance after unstake: ", user2BalanceAfterUnStake);

        assertGt(user2RewardTokenBalanceAfterUnstake, user2RewardTokenBalanceBeforeUnstake);
        assertGt(user2BalanceAfterUnStake, user2BalanceBeforeUnStake);

        uint256 remainingShares2 = nexStaking.getUserShares(user2, address(indexTokens[0]));
        console.log("Remaining shares: ", remainingShares2);
        assertEq(remainingShares2, 0, "All shares should be redeemed");
        vm.stopPrank();
    }

    function testUnstakeSomeTokensWithTwoUsersWithDifferentTokenReward() public {
        vm.startPrank(user);
        deal(address(indexTokens[0]), user, 500e18);

        indexTokens[0].approve(address(nexStaking), 500e18);
        nexStaking.stake(address(indexTokens[0]), 500e18);

        uint256 userBalanceBeforeUnStake = indexTokens[0].balanceOf(user);

        address vault = erc4626Factory.tokenAddressToVaultAddress(address(indexTokens[0]));
        ERC4626(vault).approve(address(nexStaking), type(uint256).max);

        console.log("Vault total assets: ", ERC4626(vault).totalAssets());

        vm.stopPrank();

        vm.startPrank(user2);
        deal(address(indexTokens[0]), user2, 200e18);

        indexTokens[0].approve(address(nexStaking), 200e18);
        nexStaking.stake(address(indexTokens[0]), 200e18);

        uint256 user2BalanceBeforeUnStake = indexTokens[0].balanceOf(user2);

        address vault2 = erc4626Factory.tokenAddressToVaultAddress(address(indexTokens[0]));
        ERC4626(vault2).approve(address(nexStaking), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user);
        deal(address(indexTokens[0]), vault, 1000e18);

        console.log("Vault balance: ", ERC4626(vault).balanceOf(user));

        (, uint256 amountAfterFee) = CalculationHelpers.calculateAmountAfterFeeAndFee(250e18, 3);

        uint256 userRewardTokenBalanceBeforeUnstake = rewardTokens[1].balanceOf(user);
        uint256 stakingContractBalance = indexTokens[0].balanceOf(address(nexStaking));

        console.log("User reward token balance before unstake: ", userRewardTokenBalanceBeforeUnstake);
        console.log("Staking contract balance before unstake: ", stakingContractBalance);

        nexStaking.unstake(address(indexTokens[0]), address(rewardTokens[1]), amountAfterFee);

        uint256 userRewardTokenBalanceAfterUnstake = rewardTokens[1].balanceOf(user);
        uint256 userBalanceAfterUnStake = indexTokens[0].balanceOf(user);

        console.log("User reward token balance after unstake: ", userRewardTokenBalanceAfterUnstake);
        console.log("User balance after unstake: ", userBalanceAfterUnStake);

        assertGt(userRewardTokenBalanceAfterUnstake, userRewardTokenBalanceBeforeUnstake);
        assertGt(userBalanceAfterUnStake, userBalanceBeforeUnStake);

        uint256 remainingShares = nexStaking.getUserShares(user, address(indexTokens[0]));
        uint256 expectedRemainingShares = ERC4626(vault).balanceOf(user);

        console.log("Remaining shares: ", remainingShares);
        assertEq(remainingShares, expectedRemainingShares, "All shares should be redeemed");
        vm.stopPrank();

        vm.startPrank(user2);

        console.log("Vault balance: ", ERC4626(vault).balanceOf(user2));

        (, uint256 amountAfterFee2) = CalculationHelpers.calculateAmountAfterFeeAndFee(100e18, 3);

        uint256 user2RewardTokenBalanceBeforeUnstake = rewardTokens[1].balanceOf(user2);
        uint256 staking2ContractBalance = indexTokens[0].balanceOf(address(nexStaking));

        console.log("User reward token balance before unstake: ", user2RewardTokenBalanceBeforeUnstake);
        console.log("Staking contract balance before unstake: ", staking2ContractBalance);

        nexStaking.unstake(address(indexTokens[0]), address(rewardTokens[1]), amountAfterFee2);

        uint256 user2RewardTokenBalanceAfterUnstake = rewardTokens[1].balanceOf(user2);
        uint256 user2BalanceAfterUnStake = indexTokens[0].balanceOf(user2);

        console.log("User reward token balance after unstake: ", user2RewardTokenBalanceAfterUnstake);
        console.log("User balance after unstake: ", user2BalanceAfterUnStake);

        assertGt(user2RewardTokenBalanceAfterUnstake, user2RewardTokenBalanceBeforeUnstake);
        assertGt(user2BalanceAfterUnStake, user2BalanceBeforeUnStake);

        uint256 remainingShares2 = nexStaking.getUserShares(user2, address(indexTokens[0]));
        uint256 expectedRemainingShares2 = ERC4626(vault2).balanceOf(user2);

        console.log("Remaining shares: ", remainingShares2);
        assertEq(remainingShares2, expectedRemainingShares2, "All shares should be redeemed");
        vm.stopPrank();
    }

    function testUnstakeAllTokensWithTwoUsersWitSameTokenReward() public {
        vm.startPrank(user);
        deal(address(indexTokens[0]), user, 500e18);

        indexTokens[0].approve(address(nexStaking), 500e18);
        nexStaking.stake(address(indexTokens[0]), 500e18);

        uint256 userBalanceBeforeUnStake = indexTokens[0].balanceOf(user);

        address vault = erc4626Factory.tokenAddressToVaultAddress(address(indexTokens[0]));
        ERC4626(vault).approve(address(nexStaking), type(uint256).max);

        console.log("Vault total assets: ", ERC4626(vault).totalAssets());

        vm.stopPrank();

        vm.startPrank(user2);
        deal(address(indexTokens[0]), user2, 200e18);

        indexTokens[0].approve(address(nexStaking), 200e18);
        nexStaking.stake(address(indexTokens[0]), 200e18);

        uint256 user2BalanceBeforeUnStake = indexTokens[0].balanceOf(user2);

        address vault2 = erc4626Factory.tokenAddressToVaultAddress(address(indexTokens[0]));
        ERC4626(vault2).approve(address(nexStaking), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user);
        deal(address(indexTokens[0]), vault, 1000e18);

        console.log("Vault balance: ", ERC4626(vault).balanceOf(user));

        (, uint256 amountAfterFee) = CalculationHelpers.calculateAmountAfterFeeAndFee(500e18, 3);

        uint256 stakingContractBalance = indexTokens[0].balanceOf(address(nexStaking));

        console.log("Staking contract balance before unstake: ", stakingContractBalance);

        nexStaking.unstake(address(indexTokens[0]), address(indexTokens[0]), amountAfterFee);

        uint256 userBalanceAfterUnStake = indexTokens[0].balanceOf(user);

        console.log("User balance after unstake: ", userBalanceAfterUnStake);

        assertGt(userBalanceAfterUnStake, userBalanceBeforeUnStake);

        uint256 remainingShares = nexStaking.getUserShares(user, address(indexTokens[0]));
        console.log("Remaining shares: ", remainingShares);
        assertEq(remainingShares, 0, "All shares should be redeemed");
        vm.stopPrank();

        vm.startPrank(user2);

        console.log("Vault balance: ", ERC4626(vault).balanceOf(user2));

        (, uint256 amountAfterFee2) = CalculationHelpers.calculateAmountAfterFeeAndFee(200e18, 3);

        uint256 staking2ContractBalance = indexTokens[0].balanceOf(address(nexStaking));

        console.log("Staking contract balance before unstake: ", staking2ContractBalance);

        nexStaking.unstake(address(indexTokens[0]), address(indexTokens[0]), amountAfterFee2);

        uint256 user2BalanceAfterUnStake = indexTokens[0].balanceOf(user2);

        console.log("User balance after unstake: ", user2BalanceAfterUnStake);

        assertGt(user2BalanceAfterUnStake, user2BalanceBeforeUnStake);

        uint256 remainingShares2 = nexStaking.getUserShares(user2, address(indexTokens[0]));
        console.log("Remaining shares: ", remainingShares2);
        assertEq(remainingShares2, 0, "All shares should be redeemed");
        vm.stopPrank();
    }

    function testUnstakeSomeTokensWithTwoUsersWitSameTokenReward() public {
        vm.startPrank(user);
        deal(address(indexTokens[0]), user, 500e18);

        indexTokens[0].approve(address(nexStaking), 500e18);
        nexStaking.stake(address(indexTokens[0]), 500e18);

        uint256 userBalanceBeforeUnStake = indexTokens[0].balanceOf(user);

        address vault = erc4626Factory.tokenAddressToVaultAddress(address(indexTokens[0]));
        ERC4626(vault).approve(address(nexStaking), type(uint256).max);

        console.log("Vault total assets: ", ERC4626(vault).totalAssets());

        vm.stopPrank();

        vm.startPrank(user2);
        deal(address(indexTokens[0]), user2, 200e18);

        indexTokens[0].approve(address(nexStaking), 200e18);
        nexStaking.stake(address(indexTokens[0]), 200e18);

        uint256 user2BalanceBeforeUnStake = indexTokens[0].balanceOf(user2);

        address vault2 = erc4626Factory.tokenAddressToVaultAddress(address(indexTokens[0]));
        ERC4626(vault2).approve(address(nexStaking), type(uint256).max);
        vm.stopPrank();

        vm.startPrank(user);
        deal(address(indexTokens[0]), vault, 1000e18);

        console.log("Vault balance: ", ERC4626(vault).balanceOf(user));

        (, uint256 amountAfterFee) = CalculationHelpers.calculateAmountAfterFeeAndFee(250e18, 3);

        uint256 stakingContractBalance = indexTokens[0].balanceOf(address(nexStaking));

        console.log("Staking contract balance before unstake: ", stakingContractBalance);

        nexStaking.unstake(address(indexTokens[0]), address(indexTokens[0]), amountAfterFee);

        uint256 userBalanceAfterUnStake = indexTokens[0].balanceOf(user);

        console.log("User balance after unstake: ", userBalanceAfterUnStake);

        assertGt(userBalanceAfterUnStake, userBalanceBeforeUnStake);

        uint256 remainingShares = nexStaking.getUserShares(user, address(indexTokens[0]));
        uint256 expectedRemainingShares = ERC4626(vault).balanceOf(user);

        console.log("Remaining shares: ", remainingShares);
        assertEq(remainingShares, expectedRemainingShares, "All shares should be redeemed");
        vm.stopPrank();

        vm.startPrank(user2);

        console.log("Vault balance: ", ERC4626(vault).balanceOf(user2));

        (, uint256 amountAfterFee2) = CalculationHelpers.calculateAmountAfterFeeAndFee(100e18, 3);

        uint256 staking2ContractBalance = indexTokens[0].balanceOf(address(nexStaking));

        console.log("Staking contract balance before unstake: ", staking2ContractBalance);

        nexStaking.unstake(address(indexTokens[0]), address(indexTokens[0]), amountAfterFee2);

        uint256 user2BalanceAfterUnStake = indexTokens[0].balanceOf(user2);

        console.log("User balance after unstake: ", user2BalanceAfterUnStake);

        assertGt(user2BalanceAfterUnStake, user2BalanceBeforeUnStake);

        uint256 remainingShares2 = nexStaking.getUserShares(user2, address(indexTokens[0]));
        uint256 expectedRemainingShares2 = ERC4626(vault).balanceOf(user2);

        console.log("Remaining shares: ", remainingShares2);
        assertEq(remainingShares2, expectedRemainingShares2, "All shares should be redeemed");
        vm.stopPrank();
    }

    function testSwapIndexToReward() public {
        console.log("-----------------testSwapIndexToReward-----------------");

        vm.startPrank(user);

        deal(address(indexTokens[0]), user, 500e18);

        indexTokens[0].approve(address(swapRouterV3), 500e18);

        address[] memory path = new address[](3);
        path[0] = address(indexTokens[0]);
        path[1] = address(weth);
        path[2] = address(rewardTokens[1]);

        uint256 initialRewardBalance = rewardTokens[1].balanceOf(user);
        uint256 initialIndexBalance = indexTokens[0].balanceOf(user);

        uint256 amountIn = 500e18;
        uint256 amountOut = SwapHelpers.swapIndexToReward(swapRouterV3, path, amountIn, user);

        uint256 finalRewardBalance = rewardTokens[1].balanceOf(user);
        uint256 finalIndexBalance = indexTokens[0].balanceOf(user);

        assertGt(finalRewardBalance, initialRewardBalance, "Reward token balance should increase after the swap");
        assertLt(finalIndexBalance, initialIndexBalance, "Index token balance should decrease after the swap");

        console.log("Amount Out: ", amountOut);
        console.log("Reward Token Balance After Swap: ", finalRewardBalance);

        vm.stopPrank();

        console.log("-----------------testSwapIndexToReward-----------------");
    }

    function testCalculateAmountAfterFee() public pure {
        (uint256 fee, uint256 amountAfterFee) = CalculationHelpers.calculateAmountAfterFeeAndFee(1e18, 1);
        uint256 expectedFee = (1e18 * 1) / 10000;
        uint256 expectedAmount = 1e18 - expectedFee;
        assertEq(fee, expectedFee, "Fee should be 0.1%");
        assertEq(amountAfterFee, expectedAmount, "Amount after fee should be 95%");
    }

    function testSetFeePercent() public {
        uint8 initialFeePercent = 3;
        uint8 newFeePercent = 10;

        assertEq(nexStaking.feePercent(), initialFeePercent);

        vm.startPrank(owner);
        nexStaking.setFeePercent(newFeePercent);
        vm.stopPrank();

        assertEq(nexStaking.feePercent(), newFeePercent);
    }

    function testInitializeStaking() public view {
        assertEq(nexStaking.poolTokensAddresses(0), address(indexTokens[0]), "Index Token 1 is incorrect");
        assertEq(nexStaking.poolTokensAddresses(1), address(indexTokens[1]), "Index Token 2 is incorrect");

        assertEq(
            nexStaking.rewardTokensAddresses(0),
            address(indexTokens[0]),
            "Reward Token 1 is incorrect (should be Index Token 1)"
        );
        assertEq(
            nexStaking.rewardTokensAddresses(1),
            address(rewardTokens[1]),
            "Reward Token 2 is incorrect (specific reward token or index token)"
        );
        assertEq(
            nexStaking.rewardTokensAddresses(2),
            address(indexTokens[1]),
            "Reward Token 3 is incorrect (should be Index Token 2)"
        );
    }

    function testGetSharesToRedeemAmount() public {
        vm.startPrank(user);

        deal(address(indexTokens[0]), user, 1000e18);
        indexTokens[0].approve(address(nexStaking), 1000e18);
        nexStaking.stake(address(indexTokens[0]), 1000e18);

        address vault = erc4626Factory.tokenAddressToVaultAddress(address(indexTokens[0]));
        deal(address(indexTokens[0]), vault, 1000e18);

        uint256 amountToUnstake = 750e18;

        (, uint256 amountAfterFee) = CalculationHelpers.calculateAmountAfterFeeAndFee(amountToUnstake, 3);

        uint256 sharesToRedeem = nexStaking.getSharesToRedeemAmount(address(indexTokens[0]), user, amountAfterFee);

        uint256 totalUserStake = 1000e18;
        (, uint256 totalAmountAfterFee) = CalculationHelpers.calculateAmountAfterFeeAndFee(totalUserStake, 3);
        uint256 unstakePercentage = (amountAfterFee * 1e18) / totalAmountAfterFee;

        uint256 userShares = ERC4626(vault).balanceOf(user);

        console.log("User Shares", userShares);

        uint256 expectedSharesToRedeem = (userShares * unstakePercentage) / 1e18;

        ERC4626(vault).approve(address(nexStaking), sharesToRedeem);
        nexStaking.unstake(address(indexTokens[0]), address(indexTokens[0]), amountAfterFee);

        assertEq(sharesToRedeem, expectedSharesToRedeem, "Shares to redeem should match expected value");

        vm.stopPrank();
    }

    function testGetPureRewardAmount() public {
        vm.startPrank(user);

        deal(address(indexTokens[0]), user, 500e18);
        indexTokens[0].approve(address(nexStaking), 500e18);
        nexStaking.stake(address(indexTokens[0]), 500e18);

        address vault = erc4626Factory.tokenAddressToVaultAddress(address(indexTokens[0]));
        deal(address(indexTokens[0]), vault, 1000e18);

        uint256 amountToUnstake = 250e18;

        (, uint256 amountAfterFee) = CalculationHelpers.calculateAmountAfterFeeAndFee(amountToUnstake, 3);

        uint256 rewardAmount = nexStaking.getPureRewardAmount(address(indexTokens[0]), user, amountAfterFee);

        uint256 sharesToRedeem = nexStaking.getSharesToRedeemAmount(address(indexTokens[0]), user, amountAfterFee);

        uint256 redeemAmount = ERC4626(vault).previewRedeem(sharesToRedeem);

        uint256 expectedRewardAmount = redeemAmount > amountAfterFee ? redeemAmount - amountAfterFee : 0;

        assertEq(rewardAmount, expectedRewardAmount, "Reward amount should match expected value");

        vm.stopPrank();
    }

    function testStakeAndUnstakeStateUpdates() public {
        vm.startPrank(user);

        deal(address(indexTokens[0]), user, 1000e18);
        indexTokens[0].approve(address(nexStaking), 1000e18);
        nexStaking.stake(address(indexTokens[0]), 1000e18);

        (,,, uint256 stakeAmountAfterStake,) = nexStaking.positions(user, address(indexTokens[0]));

        uint8 feePercent = nexStaking.feePercent();
        (, uint256 amountAfterStakeFee) = CalculationHelpers.calculateAmountAfterFeeAndFee(1000e18, feePercent);

        assertEq(stakeAmountAfterStake, amountAfterStakeFee, "Stake amount should match amount after fee");

        address vault = erc4626Factory.tokenAddressToVaultAddress(address(indexTokens[0]));
        ERC4626(vault).approve(address(nexStaking), type(uint256).max);
        deal(address(indexTokens[0]), vault, 1000e18);

        uint256 unstakeAmount = 500e18;

        (, uint256 amountAfterUnstakeFee) = CalculationHelpers.calculateAmountAfterFeeAndFee(unstakeAmount, feePercent);

        nexStaking.unstake(address(indexTokens[0]), address(indexTokens[0]), amountAfterUnstakeFee);

        (,,, uint256 stakeAmountAfterUnStake,) = nexStaking.positions(user, address(indexTokens[0]));

        uint256 expectedRemainingStake = stakeAmountAfterStake - amountAfterUnstakeFee;

        assertEq(
            stakeAmountAfterUnStake, expectedRemainingStake, "Stake amount should be reduced by the unstaked amount"
        );

        if (expectedRemainingStake == 0) {
            (address ownerAfterUnstake,,,,) = nexStaking.positions(user, address(indexTokens[0]));
            assertEq(ownerAfterUnstake, address(0), "Position should be deleted when stake amount is zero");
        }

        uint256 remainingShares = nexStaking.getUserShares(user, address(indexTokens[0]));
        uint256 expectedRemainingShares = ERC4626(vault).balanceOf(user);

        assertEq(
            remainingShares,
            expectedRemainingShares,
            "Remaining shares should match expected remaining shares after unstake"
        );

        vm.stopPrank();
    }

    function testSetRewardTokensAddresses() public {
        console.log("------------ testSetRewardTokensAddresses ------------");

        MockERC20 newRewardToken1 = new MockERC20("New Reward Token 1", "NRT1");
        MockERC20 newRewardToken2 = new MockERC20("New Reward Token 2", "NRT2");

        address[] memory newRewardTokens = new address[](2);
        newRewardTokens[0] = address(newRewardToken1);
        newRewardTokens[1] = address(newRewardToken2);

        vm.startPrank(owner);

        vm.recordLogs();

        nexStaking.setRewardTokensAddresses(newRewardTokens);

        Vm.Log[] memory entries = vm.getRecordedLogs();

        bool foundEvent = false;
        bytes32 eventSignature = keccak256("RewardTokensUpdated(address[])");
        for (uint256 i = 0; i < entries.length; i++) {
            Vm.Log memory logEntry = entries[i];
            if (logEntry.topics[0] == eventSignature) {
                foundEvent = true;
                break;
            }
        }
        assertTrue(foundEvent, "RewardTokensUpdated event was not emitted");

        assertEq(nexStaking.rewardTokensAddresses(0), newRewardTokens[0], "Reward token address at index 0 mismatch");
        assertEq(nexStaking.rewardTokensAddresses(1), newRewardTokens[1], "Reward token address at index 1 mismatch");

        bool isSupported0 = nexStaking.supportedRewardTokens(newRewardTokens[0]);
        assertTrue(isSupported0, "Reward token 0 should be supported");
        bool isSupported1 = nexStaking.supportedRewardTokens(newRewardTokens[1]);
        assertTrue(isSupported1, "Reward token 1 should be supported");

        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        nexStaking.setRewardTokensAddresses(newRewardTokens);

        console.log("------------ testSetRewardTokensAddresses ------------");
    }

    function testSetPoolTokensAddresses() public {
        console.log("------------ testSetPoolTokensAddresses ------------");

        MockERC20 newPoolToken1 = new MockERC20("New Pool Token 1", "NPT1");
        MockERC20 newPoolToken2 = new MockERC20("New Pool Token 2", "NPT2");

        address[] memory newPoolTokens = new address[](2);
        newPoolTokens[0] = address(newPoolToken1);
        newPoolTokens[1] = address(newPoolToken2);

        vm.startPrank(owner);

        vm.recordLogs();

        nexStaking.setPoolTokensAddresses(newPoolTokens);

        Vm.Log[] memory entries = vm.getRecordedLogs();

        bool foundEvent = false;
        bytes32 eventSignature = keccak256("PoolTokensUpdated(address[])");
        for (uint256 i = 0; i < entries.length; i++) {
            Vm.Log memory logEntry = entries[i];
            if (logEntry.topics[0] == eventSignature) {
                foundEvent = true;
                break;
            }
        }
        assertTrue(foundEvent, "PoolTokensUpdated event was not emitted");

        assertEq(nexStaking.poolTokensAddresses(0), newPoolTokens[0], "Pool token address at index 0 mismatch");
        assertEq(nexStaking.poolTokensAddresses(1), newPoolTokens[1], "Pool token address at index 1 mismatch");

        bool isSupported0 = nexStaking.supportedTokens(newPoolTokens[0]);
        assertTrue(isSupported0, "Pool token 0 should be supported");
        bool isSupported1 = nexStaking.supportedTokens(newPoolTokens[1]);
        assertTrue(isSupported1, "Pool token 1 should be supported");

        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        nexStaking.setPoolTokensAddresses(newPoolTokens);

        console.log("------------ testSetPoolTokensAddresses ------------");
    }

    function deployTokens() internal {
        nexLabsToken = new MockERC20("NexLabs Token", "NEX");
        // usdc = new MockERC20("USD Coin", "USDC", 6);

        nexLabsToken.mint(address(this), 1e24);
        // deal(address(usdc), address(this), 1e24);

        for (uint256 i = 0; i < 3; i++) {
            MockERC20 indexToken = new MockERC20(
                string(abi.encodePacked("Index Token ", uint8(i + 1))), string(abi.encodePacked("IDX", uint8(i + 1)))
            );
            indexTokens.push(indexToken);

            indexToken.mint(address(this), 100000e24);
            indexToken.mint(address(this), 100000e24);
            indexToken.mint(msg.sender, 100000e24);
            indexToken.mint(msg.sender, 100000e24);

            rewardTokens.push(indexToken);

            MockERC20 rewardToken = new MockERC20(
                string(abi.encodePacked("Reward Token ", uint8(i + 1))), string(abi.encodePacked("RWD", uint8(i + 1)))
            );
            rewardTokens.push(rewardToken);

            rewardToken.mint(address(this), 1e24);
            rewardToken.mint(address(this), 100000e24);
            rewardToken.mint(address(this), 100000e24);
            rewardToken.mint(msg.sender, 100000e24);
            rewardToken.mint(msg.sender, 100000e24);

            console.log("Index Token ", i, " deployed at: ", address(indexToken));
        }
    }

    function testSetERC4626Factory() public {
        console.log("------------ testSetERC4626Factory ------------");

        ERC4626Factory newFactory = new ERC4626Factory();

        vm.startPrank(owner);

        nexStaking._setERC4626Factory(newFactory);

        assertEq(address(nexStaking.erc4626Factory()), address(newFactory), "ERC4626Factory address mismatch");

        vm.stopPrank();

        vm.prank(user);
        vm.expectRevert(abi.encodeWithSelector(OwnableUpgradeable.OwnableUnauthorizedAccount.selector, user));
        nexStaking._setERC4626Factory(newFactory);
        vm.stopPrank();

        console.log("------------ testSetERC4626Factory ------------");
    }

    function deployAndInitializeContracts() internal {
        erc4626Factory = new ERC4626Factory();
        console.log("ERC4626Factory deployed");

        erc4626Factory.initialize(addressArray(indexTokens));
        console.log("ERC4626Factory initialized with index tokens");

        nexStaking = new NexStaking();
        console.log("Deploying NexStaking");

        uint8[] memory swapVersions = new uint8[](indexTokens.length);
        for (uint256 i = 0; i < swapVersions.length; i++) {
            swapVersions[i] = 3;
        }

        vm.startPrank(owner);
        nexStaking.initialize(
            addressArray(indexTokens),
            addressArray(rewardTokens),
            swapVersions,
            address(erc4626Factory),
            uniswapV3Router,
            address(weth),
            3
        );
        vm.stopPrank();

        console.log("Nex Staking deployed at: ", address(nexStaking));

        feeManager = new FeeManager();
        feeManager.initialize(
            nexStaking,
            addressArray(indexTokens),
            addressArray(rewardTokens),
            swapVersions,
            uniswapV3Router,
            // unsiwapV2Router,
            address(uniswapV3Factory),
            nonfungiblePositionManagerAddress,
            address(weth),
            address(rewardToken1),
            1, // Threshold
            address(erc4626Factory)
        );

        console.log("FeeManager initialized.");
    }

    function addLiquidityToAllPools() internal {
        for (uint256 i = 0; i < indexTokens.length; i++) {
            addLiquidity(indexTokens[i]);
        }

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            addLiquidity(rewardTokens[i]);
        }
    }

    function addLiquidity(IERC20 indexToken) internal {
        // Wrap ETH into WETH
        wrapEthToWeth();

        uint256 wethBalance = weth.balanceOf(address(this));
        uint256 indexTokenBalance = indexToken.balanceOf(address(this));

        require(wethBalance >= 5e18, "Not enough WETH for liquidity");
        require(indexTokenBalance >= 1000e18, "Not enough index tokens for liquidity");

        address token0 = address(weth) < address(indexToken) ? address(weth) : address(indexToken);
        address token1 = address(weth) > address(indexToken) ? address(weth) : address(indexToken);

        uint160 initialPrice = encodePriceSqrt(1000, 1);
        console.log("Initial price sqrt: ", uint256(initialPrice));

        address pool = uniswapV3Factory.getPool(token0, token1, 3000);

        if (pool == address(0)) {
            console.log("Pool does not exist, creating and initializing pool");

            INonfungiblePositionManager(nonfungiblePositionManager).createAndInitializePoolIfNecessary(
                token0, token1, 3000, initialPrice
            );
        } else {
            console.log("Pool already exists: ", pool);
        }

        weth.approve(address(nonfungiblePositionManager), type(uint256).max);
        indexToken.approve(address(nonfungiblePositionManager), type(uint256).max);

        uint256 amount0Desired;
        uint256 amount1Desired;

        if (token0 == address(weth)) {
            amount0Desired = 5e18;
            amount1Desired = 1000e18;
        } else {
            amount0Desired = 1000e18;
            amount1Desired = 5e18;
        }

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: 3000,
            tickLower: getMinTick(3000),
            tickUpper: getMaxTick(3000),
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            amount0Min: 0,
            amount1Min: 0,
            recipient: address(this),
            deadline: block.timestamp + 1200
        });

        INonfungiblePositionManager(nonfungiblePositionManager).mint(params);
        console.log("Liquidity added for Index Token ", address(indexToken));
    }

    function wrapEthToWeth() public {
        IWETH9 wethContract = IWETH9(address(weth));
        wethContract.deposit{value: 10 ether}();
    }

    function encodePriceSqrt(uint256 reserve1, uint256 reserve0) public pure returns (uint160) {
        return uint160(sqrt((reserve1 * (2 ** 192)) / reserve0));
    }

    function sqrt(uint256 y) public pure returns (uint256 z) {
        if (y > 3) {
            z = y;
            uint256 x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }

    function getMinTick(int24 tickSpacing) public pure returns (int24) {
        return int24((int256(-887272) / int256(tickSpacing) + 1) * int256(tickSpacing));
    }

    function getMaxTick(int24 tickSpacing) public pure returns (int24) {
        return int24((int256(887272) / int256(tickSpacing)) * int256(tickSpacing));
    }

    function addressArray(IERC20[] memory tokens) internal pure returns (address[] memory) {
        address[] memory addresses = new address[](tokens.length);
        for (uint256 i = 0; i < tokens.length; i++) {
            addresses[i] = address(tokens[i]);
        }
        return addresses;
    }
}
