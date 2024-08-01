// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {StakeTokens} from "../../contracts/StakeTokens.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract StakeTokensTest is Test {
    StakeTokens public stakeTokens;

    MockERC20 public usdcToken;
    MockERC20 public dinariUsdcToken;
    MockERC20 public nexLabsToken;

    uint256 constant DECIMAL = 10e18;

    address public user = address(1);
    uint256 public stakeAmount = 1000 * DECIMAL;
    uint256 public usdcTokenAPY = 10;
    uint256 public dinariUsdcTokenAPY = 15;
    uint256 public nexLabsTokenAPY = 20;

    event Staked(
        uint256 indexed positionId,
        address indexed user,
        address token,
        address rewardToken,
        uint256 amount,
        bool autoCompound,
        uint256 timestamp
    );
    event StakedIncreased(
        uint256 indexed positionId, address indexed user, address token, uint256 amount, uint256 timestamp
    );
    event UnStaked(uint256 indexed positionId, address indexed user, address token, uint256 amount, uint256 timestamp);
    event RewardWithdrawan(uint256 indexed positionId, address indexed user, uint256 amount, uint256 timestamp);

    function setUp() public {
        usdcToken = new MockERC20("USD Coin", "USDC");
        dinariUsdcToken = new MockERC20("Dinari USD Coin", "DUSDC+");
        nexLabsToken = new MockERC20("NexLabs", "NXL");

        vm.startBroadcast();
        stakeTokens = new StakeTokens(
            address(nexLabsToken),
            address(usdcToken),
            address(dinariUsdcToken),
            nexLabsTokenAPY,
            usdcTokenAPY,
            dinariUsdcTokenAPY
        );
        vm.stopBroadcast();

        nexLabsToken.mint(user, stakeAmount);
        usdcToken.mint(user, stakeAmount);
        dinariUsdcToken.mint(user, stakeAmount);

        nexLabsToken.mint(address(stakeTokens), stakeAmount * 100);
        usdcToken.mint(address(stakeTokens), stakeAmount * 100);
        dinariUsdcToken.mint(address(stakeTokens), stakeAmount * 100);

        vm.startPrank(user);
        nexLabsToken.approve(address(stakeTokens), stakeAmount);
        usdcToken.approve(address(stakeTokens), stakeAmount);
        dinariUsdcToken.approve(address(stakeTokens), stakeAmount);
        vm.stopPrank();
    }

    function testStake() public {
        vm.startPrank(user);

        vm.expectEmit(true, true, true, true);
        emit Staked(1, user, address(usdcToken), address(nexLabsToken), stakeAmount, false, block.timestamp);
        stakeTokens.stake(address(usdcToken), address(nexLabsToken), stakeAmount, false);

        (address owner,,, uint256 amount,,,,) = stakeTokens.positions(1);
        assertEq(owner, user);
        assertEq(amount, stakeAmount);

        vm.stopPrank();
    }

    function testIncreaseStakeAmount() public {
        vm.startPrank(user);

        stakeTokens.stake(address(usdcToken), address(nexLabsToken), stakeAmount, false);
        uint256 additionalStake = 500 * DECIMAL;

        usdcToken.mint(user, additionalStake);
        usdcToken.approve(address(stakeTokens), additionalStake);

        vm.expectEmit(true, true, true, true);
        emit StakedIncreased(1, user, address(usdcToken), additionalStake, block.timestamp);
        stakeTokens.increaseStakeAmount(1, additionalStake);

        (,,, uint256 totalStakeAmount,,,,) = stakeTokens.positions(1);
        assertEq(totalStakeAmount, stakeAmount + additionalStake);

        vm.stopPrank();
    }

    function testUnstake() public {
        vm.startPrank(user);

        stakeTokens.stake(address(usdcToken), address(nexLabsToken), stakeAmount, false);
        vm.expectEmit(true, true, true, true);
        emit UnStaked(1, user, address(usdcToken), stakeAmount, block.timestamp);
        stakeTokens.unStake(1);

        (,,, uint256 finalStakeAmount,,,,) = stakeTokens.positions(1);
        assertEq(finalStakeAmount, 0);

        vm.stopPrank();
    }

    function testWithdrawRewardWithAutoCompound() public {
        vm.startPrank(user);

        stakeTokens.stake(address(usdcToken), address(nexLabsToken), stakeAmount, true);

        vm.warp(block.timestamp + 365 days);

        (,,, uint256 stakeAmountBeforeReward, uint256 rewardBeforeEarned,,,) = stakeTokens.positions(1);
        console.log("Stake amount Before Reward", stakeAmountBeforeReward / DECIMAL);

        uint256 expectedReward = (stakeAmount * usdcTokenAPY * 365 days) / (365 days * 100);

        stakeTokens.withdrawReward(1);

        (,,, uint256 stakeAmountAfterReward, uint256 rewardAfterEarned,,,) = stakeTokens.positions(1);
        console.log("Expected Reward", expectedReward / DECIMAL);
        console.log("Stake amount After Reward", stakeAmountAfterReward / DECIMAL);

        stakeAmountBeforeReward += expectedReward;

        assertEq(stakeAmountAfterReward, stakeAmountBeforeReward);
        assertEq(rewardBeforeEarned, rewardAfterEarned);

        vm.stopPrank();
    }

    function testWithdrawRewardWithoutAutoCompound() public {
        vm.startPrank(user);

        stakeTokens.stake(address(usdcToken), address(nexLabsToken), stakeAmount, false);

        vm.warp(block.timestamp + 365 days);

        (,,, uint256 stakeAmountBeforeReward, uint256 rewardBeforeEarned,,,) = stakeTokens.positions(1);
        console.log("Stake amount Before Reward", stakeAmountBeforeReward / DECIMAL);

        uint256 expectedReward = (stakeAmount * usdcTokenAPY * 365 days) / (365 days * 100);

        stakeTokens.withdrawReward(1);

        (,,, uint256 stakeAmountAfterReward, uint256 rewardAfterEarned,,,) = stakeTokens.positions(1);
        console.log("Stake amount After Reward", stakeAmountAfterReward / DECIMAL);
        console.log("Expected Reward", expectedReward / DECIMAL);

        stakeAmountBeforeReward += expectedReward;

        uint256 userRewardBalance = nexLabsToken.balanceOf(user);

        assertEq(rewardBeforeEarned, rewardAfterEarned);

        assertEq(userRewardBalance, expectedReward + stakeAmount);

        vm.stopPrank();
    }

    function testInvalidRewardToken() public {
        vm.startPrank(user);

        vm.expectRevert("Invalid reward token.");
        stakeTokens.stake(address(usdcToken), address(dinariUsdcToken), stakeAmount, false);

        vm.stopPrank();
    }

    function testZeroStakeAmount() public {
        vm.startPrank(user);

        vm.expectRevert("Staking amount must be greater than zero.");
        stakeTokens.stake(address(usdcToken), address(nexLabsToken), 0, false);

        vm.stopPrank();
    }

    function testOnlyOwnerCanIncreaseStake() public {
        vm.startPrank(user);

        stakeTokens.stake(address(usdcToken), address(nexLabsToken), stakeAmount, false);

        vm.stopPrank();

        vm.expectRevert("Only owner can increase the staked amount!");
        stakeTokens.increaseStakeAmount(1, 500 * DECIMAL);
    }
}
