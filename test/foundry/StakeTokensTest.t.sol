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

    struct StakePositions {
        address owner;
        address stakeToken;
        address rewardToken;
        uint256 stakeAmount;
        uint256 rewardEarned;
        uint256 apy;
        uint256 startTime;
        bool autoCompound;
    }

    mapping(uint256 => StakePositions) public _positions;

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

    function testPositions() public {
        vm.startPrank(user);

        stakeTokens.stake(address(usdcToken), address(nexLabsToken), stakeAmount, true);

        (
            address owner,
            address stakeToken,
            address rewardToken,
            uint256 stakeAmountRetrieved,
            uint256 rewardEarned,
            uint256 apy,
            uint256 startTime,
            bool autoCompound
        ) = stakeTokens.positions(1);

        assertEq(owner, user);
        assertEq(stakeToken, address(usdcToken));
        assertEq(rewardToken, address(nexLabsToken));
        assertEq(stakeAmountRetrieved, stakeAmount);
        assertEq(rewardEarned, 0);
        assertEq(apy, usdcTokenAPY);
        assertEq(startTime, block.timestamp);
        assertTrue(autoCompound);

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

    function testUnstakeWithAutoCompoundWithDifferentTokenReward() public {
        vm.startPrank(user);

        stakeTokens.stake(address(usdcToken), address(nexLabsToken), stakeAmount, true);

        vm.warp(block.timestamp + 365 days);

        uint256 expectedReward = compoundInterest(stakeAmount, usdcTokenAPY, 1, true);
        console.log("Stake amount", stakeAmount / DECIMAL);
        console.log("Expected reward", expectedReward / DECIMAL);
        uint256 userRewardBalanceBeforeUnstake = nexLabsToken.balanceOf(user);
        uint256 userUsdcBalanceBeforeUnstake = usdcToken.balanceOf(user);

        console.log("User Reward Balance Before Unstake", userRewardBalanceBeforeUnstake / DECIMAL);
        console.log("User USDC Balance Before Unstake", userUsdcBalanceBeforeUnstake / DECIMAL);

        assertEq(userUsdcBalanceBeforeUnstake, 0);

        stakeTokens.unStake(1);
        uint256 userRewardBalanceAfterUnstake = nexLabsToken.balanceOf(user);
        uint256 userUsdcBalanceAfterUnstake = usdcToken.balanceOf(user);

        console.log("User Reward Balance After Unstake", userRewardBalanceAfterUnstake / DECIMAL);
        console.log("User USDC Balance After Unstake", userUsdcBalanceAfterUnstake / DECIMAL);

        assertEq(userRewardBalanceBeforeUnstake + expectedReward, userRewardBalanceAfterUnstake);
        assertEq(userUsdcBalanceAfterUnstake, stakeAmount);

        vm.stopPrank();
    }

    function testUnstakeWithoutAutoCompoundWithDifferentTokenReward() public {
        vm.startPrank(user);

        stakeTokens.stake(address(usdcToken), address(nexLabsToken), stakeAmount, false);

        vm.warp(block.timestamp + 365 days);

        uint256 expectedReward = compoundInterest(stakeAmount, usdcTokenAPY, 1, false);
        console.log("Stake amount", stakeAmount / DECIMAL);
        console.log("Expected reward", expectedReward / DECIMAL);
        uint256 userRewardBalanceBeforeUnstake = nexLabsToken.balanceOf(user);
        uint256 userUsdcBalanceBeforeUnstake = usdcToken.balanceOf(user);

        console.log("User Reward Balance Before Unstake", userRewardBalanceBeforeUnstake / DECIMAL);
        console.log("User USDC Balance Before Unstake", userUsdcBalanceBeforeUnstake / DECIMAL);

        assertEq(userUsdcBalanceBeforeUnstake, 0);

        stakeTokens.unStake(1);
        uint256 userRewardBalanceAfterUnstake = nexLabsToken.balanceOf(user);
        uint256 userUsdcBalanceAfterUnstake = usdcToken.balanceOf(user);

        console.log("User Reward Balance After Unstake", userRewardBalanceAfterUnstake / DECIMAL);
        console.log("User USDC Balance After Unstake", userUsdcBalanceAfterUnstake / DECIMAL);

        assertEq(userRewardBalanceBeforeUnstake + expectedReward, userRewardBalanceAfterUnstake);
        assertEq(userUsdcBalanceAfterUnstake, stakeAmount);

        vm.stopPrank();
    }

    function testUnstakeWithAutoCompoundWithSameTokenReward() public {
        vm.startPrank(user);

        stakeTokens.stake(address(usdcToken), address(usdcToken), stakeAmount, true);

        vm.warp(block.timestamp + 365 days);

        uint256 expectedReward = (stakeAmount * usdcTokenAPY * 365 days) / (365 days * 100);

        stakeTokens.unStake(1);

        (,,, uint256 finalStakeAmount, uint256 rewardEarned,,,) = stakeTokens.positions(1);
        assertEq(finalStakeAmount, 0);
        assertEq(rewardEarned, 0);

        uint256 userBalance = usdcToken.balanceOf(user);
        assertEq(userBalance, stakeAmount + expectedReward);

        vm.stopPrank();
    }

    function testUnstakeWithoutAutoCompoundWithSameTokenReward() public {
        vm.startPrank(user);

        stakeTokens.stake(address(usdcToken), address(usdcToken), stakeAmount, false);

        vm.warp(block.timestamp + 365 days);

        uint256 expectedReward = (stakeAmount * usdcTokenAPY * 365 days) / (365 days * 100);

        stakeTokens.unStake(1);

        (,,, uint256 finalStakeAmount, uint256 rewardEarned,,,) = stakeTokens.positions(1);
        assertEq(finalStakeAmount, 0);
        assertEq(rewardEarned, 0);

        uint256 userBalance = usdcToken.balanceOf(user);
        assertEq(userBalance, stakeAmount + expectedReward);

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

    function testNumberOfStakersByTokenAddress() public {
        vm.startPrank(user);

        stakeTokens.stake(address(usdcToken), address(nexLabsToken), stakeAmount, true);

        uint256 initialStakers = stakeTokens.numberOfStakersByTokenAddress(address(usdcToken));
        assertEq(initialStakers, 1);

        address user2 = address(2);
        usdcToken.mint(user2, stakeAmount);
        vm.startPrank(user2);
        usdcToken.approve(address(stakeTokens), stakeAmount);
        stakeTokens.stake(address(usdcToken), address(nexLabsToken), stakeAmount, false);

        uint256 secondStakers = stakeTokens.numberOfStakersByTokenAddress(address(usdcToken));
        assertEq(secondStakers, 2);

        uint256 finalStakers = stakeTokens.numberOfStakersByTokenAddress(address(usdcToken));
        assertEq(finalStakers, 2);

        vm.stopPrank();
    }

    function compoundInterest(uint256 principal, uint256 rate, uint256 periods, bool autoCompound)
        internal
        pure
        returns (uint256)
    {
        uint256 originalPrincipal = principal;
        if (autoCompound) {
            for (uint256 i = 0; i < periods; i++) {
                uint256 interest = (principal * rate) / 100;
                principal += interest;
            }
        } else {
            principal += (principal * rate * periods) / 100;
        }
        return principal - originalPrincipal;
    }
}
