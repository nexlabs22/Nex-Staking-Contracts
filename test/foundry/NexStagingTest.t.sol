// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {NexStaging} from "../../contracts/NexStaging.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract NexStagingTest is Test {
    NexStaging public nexStaging;

    MockERC20 public nexLabsToken;
    MockERC20 public indexToken1;
    MockERC20 public indexToken2;

    uint256 constant DECIMAL = 10e18;
    uint256 public feePercent;

    address public user = address(1);
    uint256 public stakeAmount = 1000 * DECIMAL;
    uint256 public contractInitialBalance = 100000 * DECIMAL;
    uint256 public nexLabsTokenAPY = 15;
    uint256 public indexToken1APY = 10;
    uint256 public indexToken2APY = 20;

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
    event UnStaked(
        uint256 indexed positionId,
        address indexed user,
        address token,
        uint256 amountUstaked,
        uint256 rewardAmountUnstaked,
        uint256 timestamp
    );
    event RewardWithdrawn(uint256 indexed positionId, address indexed user, uint256 amount, uint256 timestamp);

    function setUp() public {
        nexLabsToken = new MockERC20("NexLabs", "NXL");
        indexToken1 = new MockERC20("Index Token 1", "IDX1");
        indexToken2 = new MockERC20("Index Token 2", "IDX2");

        address[] memory tokenAddresses = new address[](3);
        tokenAddresses[0] = address(nexLabsToken);
        tokenAddresses[1] = address(indexToken1);
        tokenAddresses[2] = address(indexToken2);

        uint256[] memory tokenAPYs = new uint256[](3);
        tokenAPYs[0] = nexLabsTokenAPY;
        tokenAPYs[1] = indexToken1APY;
        tokenAPYs[2] = indexToken2APY;

        feePercent = 3;

        vm.startBroadcast();
        nexStaging = new NexStaging(address(nexLabsToken), tokenAddresses, tokenAPYs, feePercent);
        vm.stopBroadcast();

        mintAndApproveTokens(user);
    }

    function mintAndApproveTokens(address _user) internal {
        nexLabsToken.mint(_user, stakeAmount);
        indexToken1.mint(_user, stakeAmount);
        indexToken2.mint(_user, stakeAmount);

        nexLabsToken.mint(address(nexStaging), contractInitialBalance);
        indexToken1.mint(address(nexStaging), contractInitialBalance);
        indexToken2.mint(address(nexStaging), contractInitialBalance);

        vm.startPrank(_user);
        nexLabsToken.approve(address(nexStaging), stakeAmount);
        indexToken1.approve(address(nexStaging), stakeAmount);
        indexToken2.approve(address(nexStaging), stakeAmount);
        vm.stopPrank();
    }

    function testPositions() public {
        vm.startPrank(user);
        nexStaging.stake(address(indexToken1), address(nexLabsToken), stakeAmount, true);

        (, uint256 amountAfterFee) = calculateAmountAfterFeeAndFee(stakeAmount);

        (
            address owner,
            address stakeToken,
            address rewardToken,
            uint256 stakeAmountRetrieved,
            uint256 rewardEarned,
            uint256 apy,
            uint256 startTime,
            bool autoCompound
        ) = nexStaging.positions(1);

        assertEq(owner, user);
        assertEq(stakeToken, address(indexToken1));
        assertEq(rewardToken, address(nexLabsToken));
        assertEq(stakeAmountRetrieved, amountAfterFee);
        assertEq(rewardEarned, 0);
        assertEq(apy, indexToken1APY);
        assertEq(startTime, block.timestamp);
        assertTrue(autoCompound);

        vm.stopPrank();
    }

    function testStake() public {
        vm.startPrank(user);
        vm.expectEmit(true, true, true, true);
        (, uint256 amountAfterFee) = calculateAmountAfterFeeAndFee(stakeAmount);
        emit Staked(1, user, address(indexToken1), address(nexLabsToken), amountAfterFee, false, block.timestamp);

        nexStaging.stake(address(indexToken1), address(nexLabsToken), stakeAmount, false);

        (address owner,,, uint256 amount,,,,) = nexStaging.positions(1);
        assertEq(owner, user);
        assertEq(amount, amountAfterFee);

        vm.stopPrank();
    }

    function testIncreaseStakeAmount() public {
        vm.startPrank(user);

        vm.expectEmit(true, true, true, true);
        (, uint256 amountAfterFee) = calculateAmountAfterFeeAndFee(stakeAmount);
        emit Staked(1, user, address(indexToken1), address(nexLabsToken), amountAfterFee, false, block.timestamp);
        nexStaging.stake(address(indexToken1), address(nexLabsToken), stakeAmount, false);

        uint256 additionalStake = 500 * DECIMAL;
        indexToken1.mint(user, additionalStake);
        indexToken1.approve(address(nexStaging), additionalStake);

        vm.expectEmit(true, true, true, true);
        (, uint256 additionalAmountAfterFee) = calculateAmountAfterFeeAndFee(500 * DECIMAL);
        emit StakedIncreased(1, user, address(indexToken1), additionalAmountAfterFee, block.timestamp);

        nexStaging.increaseStakeAmount(1, additionalStake);

        (,,, uint256 totalStakeAmount,,,,) = nexStaging.positions(1);
        (, uint256 totalStakeAmountAfterFee) = calculateAmountAfterFeeAndFee(500 * DECIMAL);
        assertEq(totalStakeAmount, amountAfterFee + totalStakeAmountAfterFee);

        vm.stopPrank();
    }

    function testUnstakeWithAutoCompoundWithDifferentTokenReward() public {
        vm.startPrank(user);

        vm.expectEmit(true, true, true, true);
        ( /*uint256 fee*/ , uint256 amountAfterFee) = calculateAmountAfterFeeAndFee(stakeAmount);
        emit Staked(1, user, address(indexToken1), address(nexLabsToken), amountAfterFee, true, block.timestamp);
        nexStaging.stake(address(indexToken1), address(nexLabsToken), stakeAmount, true);

        vm.warp(block.timestamp + 365 days);
        uint256 expectedReward = compoundInterest(amountAfterFee, indexToken1APY, 365, true);

        vm.expectEmit(true, true, true, true);
        (, uint256 unstakeAmountAfterFee) = calculateAmountAfterFeeAndFee(amountAfterFee);
        emit UnStaked(1, user, address(indexToken1), unstakeAmountAfterFee, expectedReward, block.timestamp);
        nexStaging.unStake(1);

        vm.stopPrank();
    }

    function testUnstakeWithoutAutoCompoundWithDifferentTokenReward() public {
        vm.startPrank(user);

        vm.expectEmit(true, true, true, true);
        (, uint256 amountAfterFee) = calculateAmountAfterFeeAndFee(stakeAmount);
        emit Staked(1, user, address(indexToken1), address(nexLabsToken), amountAfterFee, false, block.timestamp);
        nexStaging.stake(address(indexToken1), address(nexLabsToken), stakeAmount, false);

        vm.warp(block.timestamp + 365 days);
        uint256 expectedReward = compoundInterest(amountAfterFee, indexToken1APY, 365, false);

        uint256 userRewardBalanceBeforeUnstake = nexLabsToken.balanceOf(user);
        uint256 userIndexToken1BalanceBeforeUnstake = indexToken1.balanceOf(user);
        assertEq(userIndexToken1BalanceBeforeUnstake, 0);

        vm.expectEmit(true, true, true, true);
        (, uint256 unstakeAmountAfterFee) = calculateAmountAfterFeeAndFee(amountAfterFee);
        emit UnStaked(1, user, address(indexToken1), unstakeAmountAfterFee, expectedReward, block.timestamp);
        nexStaging.unStake(1);
        uint256 userRewardBalanceAfterUnstake = nexLabsToken.balanceOf(user);
        uint256 userIndexToken1BalanceAfterUnstake = indexToken1.balanceOf(user);

        assertEq(userRewardBalanceBeforeUnstake + expectedReward, userRewardBalanceAfterUnstake);
        assertEq(userIndexToken1BalanceAfterUnstake, unstakeAmountAfterFee);

        vm.stopPrank();
    }

    function testUnstakeWithAutoCompoundWithSameTokenReward() public {
        vm.startPrank(user);

        vm.expectEmit(true, true, true, true);
        (, uint256 amountAfterFee) = calculateAmountAfterFeeAndFee(stakeAmount);
        emit Staked(1, user, address(indexToken1), address(indexToken1), amountAfterFee, true, block.timestamp);
        nexStaging.stake(address(indexToken1), address(indexToken1), stakeAmount, true);

        vm.warp(block.timestamp + 365 days);
        uint256 expectedReward = compoundInterest(amountAfterFee, indexToken1APY, 365, true);

        vm.expectEmit(true, true, true, true);
        (, uint256 unstakeAmountAfterFee) = calculateAmountAfterFeeAndFee(amountAfterFee);
        emit UnStaked(1, user, address(indexToken1), unstakeAmountAfterFee, expectedReward, block.timestamp);
        nexStaging.unStake(1);

        (,,, uint256 finalStakeAmount, uint256 rewardEarned,,,) = nexStaging.positions(1);
        assertEq(finalStakeAmount, 0);
        assertEq(rewardEarned, 0);

        uint256 userBalance = indexToken1.balanceOf(user);
        assertEq(userBalance, unstakeAmountAfterFee + expectedReward);

        vm.stopPrank();
    }

    function testUnstakeWithoutAutoCompoundWithSameTokenReward() public {
        vm.startPrank(user);

        vm.expectEmit(true, true, true, true);
        (, uint256 amountAfterFee) = calculateAmountAfterFeeAndFee(stakeAmount);
        emit Staked(1, user, address(indexToken1), address(indexToken1), amountAfterFee, false, block.timestamp);
        nexStaging.stake(address(indexToken1), address(indexToken1), stakeAmount, false);

        vm.warp(block.timestamp + 365 days);
        uint256 expectedReward = compoundInterest(amountAfterFee, indexToken1APY, 365, false);

        vm.expectEmit(true, true, true, true);
        (, uint256 unstakeAmountAfterFee) = calculateAmountAfterFeeAndFee(amountAfterFee);
        emit UnStaked(1, user, address(indexToken1), unstakeAmountAfterFee, expectedReward, block.timestamp);
        nexStaging.unStake(1);

        (,,, uint256 finalStakeAmount, uint256 rewardEarned,,,) = nexStaging.positions(1);
        assertEq(finalStakeAmount, 0);
        assertEq(rewardEarned, 0);

        uint256 userBalance = indexToken1.balanceOf(user);
        assertEq(userBalance, unstakeAmountAfterFee + expectedReward);

        vm.stopPrank();
    }

    function testWithdrawRewardWithAutoCompound() public {
        vm.startPrank(user);

        vm.expectEmit(true, true, true, true);
        (, uint256 amountAfterFee) = calculateAmountAfterFeeAndFee(stakeAmount);
        emit Staked(1, user, address(indexToken1), address(nexLabsToken), amountAfterFee, true, block.timestamp);
        nexStaging.stake(address(indexToken1), address(nexLabsToken), stakeAmount, true);

        vm.warp(block.timestamp + 365 days);

        (,,, uint256 stakeAmountBeforeReward, uint256 rewardBeforeEarned,,,) = nexStaging.positions(1);
        uint256 expectedReward = compoundInterest(amountAfterFee, indexToken1APY, 365, true);

        vm.expectEmit(true, true, true, true);
        emit RewardWithdrawn(1, user, expectedReward, block.timestamp);
        nexStaging.withdrawReward(1);

        (,,, uint256 stakeAmountAfterReward, uint256 rewardAfterEarned,,,) = nexStaging.positions(1);

        stakeAmountBeforeReward += expectedReward;
        assertEq(stakeAmountAfterReward, stakeAmountBeforeReward);
        assertEq(rewardBeforeEarned, rewardAfterEarned);

        vm.stopPrank();
    }

    function testWithdrawRewardWithoutAutoCompound() public {
        vm.startPrank(user);

        vm.expectEmit(true, true, true, true);
        (, uint256 amountAfterFee) = calculateAmountAfterFeeAndFee(stakeAmount);
        emit Staked(1, user, address(indexToken1), address(nexLabsToken), amountAfterFee, false, block.timestamp);
        nexStaging.stake(address(indexToken1), address(nexLabsToken), stakeAmount, false);

        vm.warp(block.timestamp + 365 days);

        (,,,, uint256 rewardBeforeEarned,,,) = nexStaging.positions(1);
        uint256 expectedReward = compoundInterest(amountAfterFee, indexToken1APY, 365, false);

        vm.expectEmit(true, true, true, true);
        emit RewardWithdrawn(1, user, expectedReward, block.timestamp);
        nexStaging.withdrawReward(1);

        (,,,, uint256 rewardAfterEarned,,,) = nexStaging.positions(1);
        uint256 userRewardBalance = nexLabsToken.balanceOf(user);

        assertEq(rewardBeforeEarned, rewardAfterEarned);
        assertEq(userRewardBalance, expectedReward + stakeAmount);

        vm.stopPrank();
    }

    function testInvalidRewardToken() public {
        vm.startPrank(user);
        vm.expectRevert("Invalid reward token.");
        nexStaging.stake(address(indexToken1), address(indexToken2), stakeAmount, false);
        vm.stopPrank();
    }

    function testZeroStakeAmount() public {
        vm.startPrank(user);
        vm.expectRevert("Staking amount must be greater than zero.");
        nexStaging.stake(address(indexToken1), address(nexLabsToken), 0, false);
        vm.stopPrank();
    }

    function testOnlyOwnerCanIncreaseStake() public {
        vm.startPrank(user);
        nexStaging.stake(address(indexToken1), address(nexLabsToken), stakeAmount, false);
        vm.stopPrank();

        vm.expectRevert("Only owner can increase the staked amount!");
        nexStaging.increaseStakeAmount(1, 500 * DECIMAL);
    }

    function testNumberOfStakersByTokenAddress() public {
        vm.startPrank(user);
        nexStaging.stake(address(indexToken1), address(nexLabsToken), stakeAmount, true);

        uint256 initialStakers = nexStaging.numberOfStakersByTokenAddress(address(indexToken1));
        assertEq(initialStakers, 1);

        address user2 = address(2);
        indexToken1.mint(user2, stakeAmount);
        vm.startPrank(user2);
        indexToken1.approve(address(nexStaging), stakeAmount);
        nexStaging.stake(address(indexToken1), address(nexLabsToken), stakeAmount, false);

        uint256 secondStakers = nexStaging.numberOfStakersByTokenAddress(address(indexToken1));
        assertEq(secondStakers, 2);

        uint256 finalStakers = nexStaging.numberOfStakersByTokenAddress(address(indexToken1));
        assertEq(finalStakers, 2);

        vm.stopPrank();
    }

    function compoundInterest(uint256 principal, uint256 rate, uint256 durationInDays, bool autoCompound)
        internal
        pure
        returns (uint256)
    {
        uint256 originalPrincipal = principal;
        uint256 dailyRate = rate * 1e18 / 365;

        if (autoCompound) {
            for (uint256 i = 0; i < durationInDays; i++) {
                uint256 interest = (principal * dailyRate) / 1e20;
                principal += interest;
            }
        } else {
            principal += (principal * dailyRate * durationInDays) / 1e20;
        }

        return principal - originalPrincipal;
    }

    function calculateAmountAfterFeeAndFee(uint256 amount) internal view returns (uint256, uint256) {
        uint256 fee = (amount * feePercent) / 10000;
        uint256 amountAfterFee = amount - fee;
        return (fee, amountAfterFee);
    }
}
