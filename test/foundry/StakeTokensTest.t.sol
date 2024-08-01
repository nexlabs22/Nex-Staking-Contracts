// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {StakeTokens} from "../../contracts/StakeTokens.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract StakeTokensTest is Test {
    StakeTokens public stakeTokens;

    MockERC20 public anfiToken;
    MockERC20 public crypto5Token;
    MockERC20 public magnificent7IndexToken;
    MockERC20 public arbitrumIndexToken;
    MockERC20 public nexLabsToken;

    uint256 constant DECIMAL = 10e18;

    address public user = address(1);
    uint256 public stakeAmount = 1000 * DECIMAL;
    uint256 public anfiTokenAPY = 5;
    uint256 public crypto5TokenAPY = 10;
    uint256 public nexLabsTokenAPY = 15;
    uint256 public magnificent7IndexTokenAPY = 20;
    uint256 public arbitrumIndexTokenAPY = 25;

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
        anfiToken = new MockERC20("ANFI", "ANFI");
        crypto5Token = new MockERC20("CRYPTO 5", "CRYPTO5");
        magnificent7IndexToken = new MockERC20("Magnificent 7", "M7I");
        arbitrumIndexToken = new MockERC20("Arbitrum Index", "AI");
        nexLabsToken = new MockERC20("NexLabs", "NXL");

        vm.startBroadcast();
        stakeTokens = new StakeTokens(
            address(nexLabsToken),
            address(anfiToken),
            address(crypto5Token),
            address(magnificent7IndexToken),
            address(arbitrumIndexToken),
            nexLabsTokenAPY,
            anfiTokenAPY,
            crypto5TokenAPY,
            magnificent7IndexTokenAPY,
            arbitrumIndexTokenAPY
        );
        vm.stopBroadcast();

        mintAndApproveTokens(user);
    }

    function mintAndApproveTokens(address _user) internal {
        nexLabsToken.mint(_user, stakeAmount);
        anfiToken.mint(_user, stakeAmount);
        crypto5Token.mint(_user, stakeAmount);

        nexLabsToken.mint(address(stakeTokens), stakeAmount * 100);
        anfiToken.mint(address(stakeTokens), stakeAmount * 100);
        crypto5Token.mint(address(stakeTokens), stakeAmount * 100);

        vm.startPrank(_user);
        nexLabsToken.approve(address(stakeTokens), stakeAmount);
        anfiToken.approve(address(stakeTokens), stakeAmount);
        crypto5Token.approve(address(stakeTokens), stakeAmount);
        vm.stopPrank();
    }

    function testPositions() public {
        vm.startPrank(user);
        stakeTokens.stake(address(anfiToken), address(nexLabsToken), stakeAmount, true);

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
        assertEq(stakeToken, address(anfiToken));
        assertEq(rewardToken, address(nexLabsToken));
        assertEq(stakeAmountRetrieved, stakeAmount);
        assertEq(rewardEarned, 0);
        assertEq(apy, anfiTokenAPY);
        assertEq(startTime, block.timestamp);
        assertTrue(autoCompound);

        vm.stopPrank();
    }

    function testStake() public {
        vm.startPrank(user);
        vm.expectEmit(true, true, true, true);
        emit Staked(1, user, address(anfiToken), address(nexLabsToken), stakeAmount, false, block.timestamp);

        stakeTokens.stake(address(anfiToken), address(nexLabsToken), stakeAmount, false);

        (address owner,,, uint256 amount,,,,) = stakeTokens.positions(1);
        assertEq(owner, user);
        assertEq(amount, stakeAmount);

        vm.stopPrank();
    }

    function testIncreaseStakeAmount() public {
        vm.startPrank(user);
        stakeTokens.stake(address(anfiToken), address(nexLabsToken), stakeAmount, false);

        uint256 additionalStake = 500 * DECIMAL;
        anfiToken.mint(user, additionalStake);
        anfiToken.approve(address(stakeTokens), additionalStake);

        vm.expectEmit(true, true, true, true);
        emit StakedIncreased(1, user, address(anfiToken), additionalStake, block.timestamp);

        stakeTokens.increaseStakeAmount(1, additionalStake);

        (,,, uint256 totalStakeAmount,,,,) = stakeTokens.positions(1);
        assertEq(totalStakeAmount, stakeAmount + additionalStake);

        vm.stopPrank();
    }

    function testUnstake() public {
        vm.startPrank(user);
        stakeTokens.stake(address(anfiToken), address(nexLabsToken), stakeAmount, false);

        vm.expectEmit(true, true, true, true);
        emit UnStaked(1, user, address(anfiToken), stakeAmount, block.timestamp);
        stakeTokens.unStake(1);

        (,,, uint256 finalStakeAmount,,,,) = stakeTokens.positions(1);
        assertEq(finalStakeAmount, 0);

        vm.stopPrank();
    }

    function testUnstakeWithAutoCompoundWithDifferentTokenReward() public {
        vm.startPrank(user);
        stakeTokens.stake(address(anfiToken), address(nexLabsToken), stakeAmount, true);

        vm.warp(block.timestamp + 365 days);
        uint256 expectedReward = compoundInterest(stakeAmount, anfiTokenAPY, 365, true);

        uint256 userRewardBalanceBeforeUnstake = nexLabsToken.balanceOf(user);
        uint256 userAnfiBalanceBeforeUnstake = anfiToken.balanceOf(user);
        assertEq(userAnfiBalanceBeforeUnstake, 0);

        stakeTokens.unStake(1);
        uint256 userRewardBalanceAfterUnstake = nexLabsToken.balanceOf(user);
        uint256 userAnfiBalanceAfterUnstake = anfiToken.balanceOf(user);

        assertGt(userRewardBalanceAfterUnstake, userRewardBalanceBeforeUnstake);
        assertEq(userAnfiBalanceAfterUnstake, stakeAmount);

        vm.stopPrank();
    }

    function testUnstakeWithoutAutoCompoundWithDifferentTokenReward() public {
        vm.startPrank(user);
        stakeTokens.stake(address(anfiToken), address(nexLabsToken), stakeAmount, false);

        vm.warp(block.timestamp + 365 days);
        uint256 expectedReward = compoundInterest(stakeAmount, anfiTokenAPY, 365, false);

        uint256 userRewardBalanceBeforeUnstake = nexLabsToken.balanceOf(user);
        uint256 userAnfiBalanceBeforeUnstake = anfiToken.balanceOf(user);
        assertEq(userAnfiBalanceBeforeUnstake, 0);

        stakeTokens.unStake(1);
        uint256 userRewardBalanceAfterUnstake = nexLabsToken.balanceOf(user);
        uint256 userAnfiBalanceAfterUnstake = anfiToken.balanceOf(user);

        assertEq(userRewardBalanceBeforeUnstake + expectedReward, userRewardBalanceAfterUnstake);
        assertEq(userAnfiBalanceAfterUnstake, stakeAmount);

        vm.stopPrank();
    }

    function testUnstakeWithAutoCompoundWithSameTokenReward() public {
        vm.startPrank(user);
        stakeTokens.stake(address(anfiToken), address(anfiToken), stakeAmount, true);

        vm.warp(block.timestamp + 365 days);
        uint256 expectedReward = compoundInterest(stakeAmount, anfiTokenAPY, 365, true);

        stakeTokens.unStake(1);

        (,,, uint256 finalStakeAmount, uint256 rewardEarned,,,) = stakeTokens.positions(1);
        assertEq(finalStakeAmount, 0);
        assertEq(rewardEarned, 0);

        uint256 userBalance = anfiToken.balanceOf(user);
        assertEq(userBalance, stakeAmount + expectedReward);

        vm.stopPrank();
    }

    function testUnstakeWithoutAutoCompoundWithSameTokenReward() public {
        vm.startPrank(user);
        stakeTokens.stake(address(anfiToken), address(anfiToken), stakeAmount, false);

        vm.warp(block.timestamp + 365 days);
        uint256 expectedReward = compoundInterest(stakeAmount, anfiTokenAPY, 365, false);

        stakeTokens.unStake(1);

        (,,, uint256 finalStakeAmount, uint256 rewardEarned,,,) = stakeTokens.positions(1);
        assertEq(finalStakeAmount, 0);
        assertEq(rewardEarned, 0);

        uint256 userBalance = anfiToken.balanceOf(user);
        assertEq(userBalance, stakeAmount + expectedReward);

        vm.stopPrank();
    }

    function testWithdrawRewardWithAutoCompound() public {
        vm.startPrank(user);
        stakeTokens.stake(address(anfiToken), address(nexLabsToken), stakeAmount, true);

        vm.warp(block.timestamp + 365 days);

        (,,, uint256 stakeAmountBeforeReward, uint256 rewardBeforeEarned,,,) = stakeTokens.positions(1);
        uint256 expectedReward = compoundInterest(stakeAmount, anfiTokenAPY, 365, true);
        console.log("Expected Reward", expectedReward);

        stakeTokens.withdrawReward(1);

        (,,, uint256 stakeAmountAfterReward, uint256 rewardAfterEarned,,,) = stakeTokens.positions(1);

        stakeAmountBeforeReward += expectedReward;
        assertEq(stakeAmountAfterReward, stakeAmountBeforeReward);
        assertEq(rewardBeforeEarned, rewardAfterEarned);

        vm.stopPrank();
    }

    function testWithdrawRewardWithoutAutoCompound() public {
        vm.startPrank(user);
        stakeTokens.stake(address(anfiToken), address(nexLabsToken), stakeAmount, false);

        vm.warp(block.timestamp + 365 days);

        (,,,, uint256 rewardBeforeEarned,,,) = stakeTokens.positions(1);
        uint256 expectedReward = compoundInterest(stakeAmount, anfiTokenAPY, 365, false);

        console.log("Expected Reward", expectedReward);

        stakeTokens.withdrawReward(1);

        (,,,, uint256 rewardAfterEarned,,,) = stakeTokens.positions(1);
        uint256 userRewardBalance = nexLabsToken.balanceOf(user);

        assertEq(rewardBeforeEarned, rewardAfterEarned);
        // assertEq(userRewardBalance, expectedReward);

        vm.stopPrank();
    }

    function testInvalidRewardToken() public {
        vm.startPrank(user);
        vm.expectRevert("Invalid reward token.");
        stakeTokens.stake(address(anfiToken), address(crypto5Token), stakeAmount, false);
        vm.stopPrank();
    }

    function testZeroStakeAmount() public {
        vm.startPrank(user);
        vm.expectRevert("Staking amount must be greater than zero.");
        stakeTokens.stake(address(anfiToken), address(nexLabsToken), 0, false);
        vm.stopPrank();
    }

    function testOnlyOwnerCanIncreaseStake() public {
        vm.startPrank(user);
        stakeTokens.stake(address(anfiToken), address(nexLabsToken), stakeAmount, false);
        vm.stopPrank();

        vm.expectRevert("Only owner can increase the staked amount!");
        stakeTokens.increaseStakeAmount(1, 500 * DECIMAL);
    }

    function testNumberOfStakersByTokenAddress() public {
        vm.startPrank(user);
        stakeTokens.stake(address(anfiToken), address(nexLabsToken), stakeAmount, true);

        uint256 initialStakers = stakeTokens.numberOfStakersByTokenAddress(address(anfiToken));
        assertEq(initialStakers, 1);

        address user2 = address(2);
        anfiToken.mint(user2, stakeAmount);
        vm.startPrank(user2);
        anfiToken.approve(address(stakeTokens), stakeAmount);
        stakeTokens.stake(address(anfiToken), address(nexLabsToken), stakeAmount, false);

        uint256 secondStakers = stakeTokens.numberOfStakersByTokenAddress(address(anfiToken));
        assertEq(secondStakers, 2);

        uint256 finalStakers = stakeTokens.numberOfStakersByTokenAddress(address(anfiToken));
        assertEq(finalStakers, 2);

        vm.stopPrank();
    }

    function compoundInterest(uint256 principal, uint256 rate, uint256 durationInDays, bool autoCompound)
        internal
        pure
        returns (uint256)
    {
        uint256 originalPrincipal = principal;
        uint256 dailyRate = rate * 1e18 / 365; // Calculate daily rate with precision

        if (autoCompound) {
            for (uint256 i = 0; i < durationInDays; i++) {
                uint256 interest = (principal * dailyRate) / 1e20; // Dividing by 1e20 to maintain precision
                principal += interest;
            }
        } else {
            principal += (principal * dailyRate * durationInDays) / 1e20;
        }

        return principal - originalPrincipal;
    }
}
