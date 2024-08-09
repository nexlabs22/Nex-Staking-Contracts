// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console} from "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

import {NexStaging} from "../../contracts/NexStaging.sol";
import {CalculationHelper} from "../../contracts/libraries/CalculationHelper.sol";
import {MockERC20} from "./mocks/MockERC20.sol";
import {DeployNexStaging} from "../../script/DeployNexStaging.s.sol";

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
        // Initialize mock tokens
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

        // Deploy the logic contract
        NexStaging nexStagingImplementation = new NexStaging();

        // Deploy the proxy and initialize the implementation
        bytes memory data = abi.encodeWithSignature(
            "initialize(address,address[],uint256[],uint256)",
            address(nexLabsToken),
            tokenAddresses,
            tokenAPYs,
            feePercent
        );
        ERC1967Proxy proxy = new ERC1967Proxy(address(nexStagingImplementation), data);

        nexStaging = NexStaging(address(proxy));

        vm.stopBroadcast();

        mintAndApproveTokens(user);
    }

    /// @notice Mints and approves tokens for the user
    /// @param _user Address of the user
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

    /// @notice Tests the positions function
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

        // Assertions to verify the correct position details
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

    /// @notice Tests the stake function
    function testStake() public {
        vm.startPrank(user);
        vm.expectEmit(true, true, true, true);
        (, uint256 amountAfterFee) = calculateAmountAfterFeeAndFee(stakeAmount);
        emit Staked(1, user, address(indexToken1), address(nexLabsToken), amountAfterFee, false, block.timestamp);

        nexStaging.stake(address(indexToken1), address(nexLabsToken), stakeAmount, false);

        (address owner,,, uint256 amount,,,,) = nexStaging.positions(1);
        // Assertions to verify the correct staking details
        assertEq(owner, user);
        assertEq(amount, amountAfterFee);

        vm.stopPrank();
    }

    /// @notice Tests increasing the stake amount
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
        // Assertion to verify the total stake amount after increase
        assertEq(totalStakeAmount, amountAfterFee + totalStakeAmountAfterFee);

        vm.stopPrank();
    }

    /// @notice Tests unstaking with auto-compound and different token rewards
    function testUnstakeWithAutoCompoundWithDifferentTokenReward() public {
        vm.startPrank(user);

        vm.expectEmit(true, true, true, true);
        ( /*uint256 fee*/ , uint256 amountAfterFee) = calculateAmountAfterFeeAndFee(stakeAmount);
        emit Staked(1, user, address(indexToken1), address(nexLabsToken), amountAfterFee, true, block.timestamp);
        nexStaging.stake(address(indexToken1), address(nexLabsToken), stakeAmount, true);

        vm.warp(block.timestamp + 365 days);
        uint256 expectedReward = compoundInterest(amountAfterFee, indexToken1APY, 365, true);

        vm.expectEmit(true, true, true, true);
        (, uint256 rewardAmountAfterFee) = calculateAmountAfterFeeAndFee(expectedReward);
        emit UnStaked(1, user, address(indexToken1), amountAfterFee, rewardAmountAfterFee, block.timestamp);
        nexStaging.unStake(1);

        vm.stopPrank();
    }

    /// @notice Tests unstaking without auto-compound and different token rewards
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
        (uint256 fee, uint256 rewardAmountAfterFee) = calculateAmountAfterFeeAndFee(expectedReward);
        emit UnStaked(1, user, address(indexToken1), amountAfterFee, rewardAmountAfterFee, block.timestamp);
        nexStaging.unStake(1);
        uint256 userRewardBalanceAfterUnstake = nexLabsToken.balanceOf(user);
        // uint256 userIndexToken1BalanceAfterUnstake = indexToken1.balanceOf(user);

        // Assertions to verify balances after unstaking
        assertGt(userRewardBalanceAfterUnstake, userRewardBalanceBeforeUnstake);

        assertEq(rewardAmountAfterFee + fee, expectedReward);

        vm.stopPrank();
    }

    /// @notice Tests unstaking with auto-compound and same token rewards
    function testUnstakeWithAutoCompoundWithSameTokenReward() public {
        vm.startPrank(user);

        vm.expectEmit(true, true, true, true);
        (, uint256 amountAfterFee) = calculateAmountAfterFeeAndFee(stakeAmount);
        emit Staked(1, user, address(indexToken1), address(indexToken1), amountAfterFee, true, block.timestamp);
        nexStaging.stake(address(indexToken1), address(indexToken1), stakeAmount, true);

        vm.warp(block.timestamp + 365 days);
        uint256 expectedReward = compoundInterest(amountAfterFee, indexToken1APY, 365, true);

        vm.expectEmit(true, true, true, true);
        (, uint256 rewardAmountAfterFee) = calculateAmountAfterFeeAndFee(expectedReward);
        emit UnStaked(1, user, address(indexToken1), amountAfterFee, rewardAmountAfterFee, block.timestamp);
        nexStaging.unStake(1);

        (,,, uint256 finalStakeAmount, uint256 rewardEarned,,,) = nexStaging.positions(1);
        // Assertions to verify balances and state after unstaking
        assertEq(finalStakeAmount, 0);
        assertEq(rewardEarned, 0);

        uint256 userBalance = indexToken1.balanceOf(user);
        assertEq(userBalance, amountAfterFee + rewardAmountAfterFee);

        vm.stopPrank();
    }

    /// @notice Tests unstaking without auto-compound and same token rewards
    function testUnstakeWithoutAutoCompoundWithSameTokenReward() public {
        vm.startPrank(user);

        vm.expectEmit(true, true, true, true);
        (, uint256 amountAfterFee) = calculateAmountAfterFeeAndFee(stakeAmount);
        emit Staked(1, user, address(indexToken1), address(indexToken1), amountAfterFee, false, block.timestamp);
        nexStaging.stake(address(indexToken1), address(indexToken1), stakeAmount, false);

        vm.warp(block.timestamp + 365 days);
        uint256 expectedReward = compoundInterest(amountAfterFee, indexToken1APY, 365, false);

        vm.expectEmit(true, true, true, true);
        (, uint256 rewardAmountAfterFee) = calculateAmountAfterFeeAndFee(expectedReward);
        emit UnStaked(1, user, address(indexToken1), amountAfterFee, rewardAmountAfterFee, block.timestamp);
        nexStaging.unStake(1);

        (,,, uint256 finalStakeAmount, uint256 rewardEarned,,,) = nexStaging.positions(1);
        // Assertions to verify balances and state after unstaking
        assertEq(finalStakeAmount, 0);
        assertEq(rewardEarned, 0);

        uint256 userBalance = indexToken1.balanceOf(user);
        assertEq(userBalance, amountAfterFee + rewardAmountAfterFee);

        vm.stopPrank();
    }

    /// @notice Tests withdrawing rewards with auto-compound
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

        // Assertions to verify balances and state after reward withdrawal
        stakeAmountBeforeReward += expectedReward;
        assertEq(stakeAmountAfterReward, stakeAmountBeforeReward);
        assertEq(rewardBeforeEarned, rewardAfterEarned);

        vm.stopPrank();
    }

    /// @notice Tests withdrawing rewards without auto-compound
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

        // Assertions to verify balances and state after reward withdrawal
        assertEq(rewardBeforeEarned, rewardAfterEarned);
        assertEq(userRewardBalance, expectedReward + stakeAmount);

        vm.stopPrank();
    }

    /// @notice Tests staking with an invalid reward token
    function testInvalidRewardToken() public {
        vm.startPrank(user);
        vm.expectRevert("Invalid reward token.");
        nexStaging.stake(address(indexToken1), address(indexToken2), stakeAmount, false);
        vm.stopPrank();
    }

    /// @notice Tests staking with zero amount
    function testZeroStakeAmount() public {
        vm.startPrank(user);
        vm.expectRevert("Staking amount must be greater than zero.");
        nexStaging.stake(address(indexToken1), address(nexLabsToken), 0, false);
        vm.stopPrank();
    }

    /// @notice Tests that only the owner can increase the stake amount
    function testOnlyOwnerCanIncreaseStake() public {
        vm.startPrank(user);
        nexStaging.stake(address(indexToken1), address(nexLabsToken), stakeAmount, false);
        vm.stopPrank();

        vm.expectRevert("Only owner can increase the staked amount!");
        nexStaging.increaseStakeAmount(1, 500 * DECIMAL);
    }

    /// @notice Tests the number of stakers by token address
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

    function testIncreaseStakeAmountByZero() public {
        vm.startPrank(user);

        nexStaging.stake(address(indexToken1), address(nexLabsToken), stakeAmount, false);

        // Try to increase stake amount by 0
        vm.expectRevert("Increase amount must be greater than zero.");
        nexStaging.increaseStakeAmount(1, 0);

        vm.stopPrank();
    }

    function testIncreaseStakeAmountByNonOwner() public {
        vm.startPrank(user);

        address user2 = address(2);

        nexStaging.stake(address(indexToken1), address(nexLabsToken), stakeAmount, false);
        vm.stopPrank();

        // Try to increase stake amount by non-owner
        vm.startPrank(user2);
        uint256 additionalStake = 500 * DECIMAL;
        indexToken1.mint(user2, additionalStake);
        indexToken1.approve(address(nexStaging), additionalStake);

        vm.expectRevert("Only owner can increase the staked amount!");
        nexStaging.increaseStakeAmount(1, additionalStake);

        vm.stopPrank();
    }

    function testIncreaseStakeAmountForNonExistentPosition() public {
        vm.startPrank(user);

        // Try to increase stake amount for a non-existent position
        uint256 additionalStake = 500 * DECIMAL;
        indexToken1.mint(user, additionalStake);
        indexToken1.approve(address(nexStaging), additionalStake);

        vm.expectRevert(); // Expect a revert because the position does not exist
        nexStaging.increaseStakeAmount(9999, additionalStake); // Using a high number to simulate non-existent position

        vm.stopPrank();
    }

    function testNexStagingCalculationFunction() public {
        vm.startPrank(user);
        (uint256 testContractFee, uint256 testContractAmountAfterFee) = calculateAmountAfterFeeAndFee(stakeAmount);
        (uint256 mainContractFee, uint256 mainContractAmountAfterFee) =
            CalculationHelper.calculateAmountAfterFeeAndFee(stakeAmount, feePercent);
        nexStaging.stake(address(indexToken1), address(nexLabsToken), stakeAmount, false);

        assertEq(testContractFee, mainContractFee);
        assertEq(testContractAmountAfterFee, mainContractAmountAfterFee);

        vm.warp(block.timestamp + 365);

        vm.stopPrank();
    }

    /// @notice This function is for log the balances before/staking staking and before/after unstaking
    function testBalancesAfterActions() public {
        vm.startPrank(user);
        console.log("***** Before Staking *****");
        uint256 contractIndex1BalanceBeforeStaking = indexToken1.balanceOf(address(nexStaging));
        uint256 contractRewardBalanceBeforeStaking = nexLabsToken.balanceOf(address(nexStaging));
        console.log("Contract Index1 Balance Before Staking", contractIndex1BalanceBeforeStaking);
        console.log("COntract Reward Balance Before Staking", contractRewardBalanceBeforeStaking);

        uint256 userIndex1BalanceBeforeStaking = indexToken1.balanceOf(user);
        uint256 userRewardBalanceBeforeStaking = nexLabsToken.balanceOf(user);
        console.log("User Index1 Balance Before Staking", userIndex1BalanceBeforeStaking);
        console.log("User Reward Balance Before Staking", userRewardBalanceBeforeStaking);

        (uint256 feeAmountForStaking, uint256 amountAfterFee) = calculateAmountAfterFeeAndFee(stakeAmount);
        console.log("Fee Amount For Staking", feeAmountForStaking);
        console.log("Amount After Fee", amountAfterFee);
        nexStaging.stake(address(indexToken1), address(nexLabsToken), stakeAmount, false);

        console.log("");
        console.log("***** After Staking *****");

        vm.warp(block.timestamp + 365 days);
        uint256 expectedReward = compoundInterest(amountAfterFee, indexToken1APY, 365, false);

        console.log("Expected reward", expectedReward /* / DECIMAL*/ );

        uint256 contractIndex1BalanceAfterStaking = indexToken1.balanceOf(address(nexStaging));
        uint256 contractRewardBalanceAfterStaking = nexLabsToken.balanceOf(address(nexStaging));
        console.log("Contract Index1 Balance After Staking", contractIndex1BalanceAfterStaking);
        console.log("Contract Reward Balance After Staking", contractRewardBalanceAfterStaking);

        uint256 userIndex1BalanceAfterStaking = indexToken1.balanceOf(user);
        uint256 userRewardBalanceAfterStaking = nexLabsToken.balanceOf(user);

        console.log("User Index1 Balance After Staking", userIndex1BalanceAfterStaking);
        console.log("User Reward Balance After Staking", userRewardBalanceAfterStaking);
        console.log("-----------------------------------------------------------------------------------------");
        console.log("***** After UnStaking *****");
        nexStaging.unStake(1);

        (uint256 rewardFeeAmountForUnstaking, uint256 rewardAmountUnstakingAfterFee) =
            calculateAmountAfterFeeAndFee(expectedReward);
        console.log("Reward Fee Amount For Unstaking", rewardFeeAmountForUnstaking);
        console.log("Reward Amount After Fee Unstaking", rewardAmountUnstakingAfterFee);

        uint256 contractIndex1BalanceAfterUnstake = indexToken1.balanceOf(address(nexStaging));
        uint256 contractRewardBalanceAfterUnstake = nexLabsToken.balanceOf(address(nexStaging));
        console.log("Contract Index1 Balance After UnStaking", contractIndex1BalanceAfterUnstake);
        console.log("Contract Reward Balance After UnStaking", contractRewardBalanceAfterUnstake);

        uint256 userIndex1BalanceAfterUnStaking = indexToken1.balanceOf(user);
        uint256 userRewardBalanceAfterUnStaking = nexLabsToken.balanceOf(user);

        console.log("User Index1 Balance After UnStaking", userIndex1BalanceAfterUnStaking);
        console.log("User Reward Balance After UnStaking", userRewardBalanceAfterUnStaking);

        console.log("-----------------------------------------------------------------------------------------");

        (,,, uint256 stakedAmount, uint256 rewardEarned,,,) = nexStaging.positions(1);

        console.log("Reward Earned", rewardEarned);
        console.log("Staked Amount", stakedAmount);

        assertEq(rewardEarned, 0);
        assertEq(stakedAmount, 0);

        vm.stopPrank();
    }

    ///////////////////////////////////////////////////////
    ///////////// Calculation Functions ///////////////////
    ///////////////////////////////////////////////////////

    /// @notice Calculates the compound interest
    /// @param principal Principal amount
    /// @param rate Interest rate
    /// @param durationInDays Duration in days
    /// @param autoCompound Boolean indicating if auto-compound is enabled
    /// @return Final amount after compound interest calculation
    function compoundInterest(uint256 principal, uint256 rate, uint256 durationInDays, bool autoCompound)
        internal
        pure
        returns (uint256)
    {
        uint256 originalPrincipal = principal;
        uint256 dailyRate = rate * 1e18 / 10;
        uint256 intervalRate = dailyRate * 10; // Adjust the rate for the 10-day interval

        if (autoCompound) {
            uint256 numberOfIntervals = durationInDays / 10;

            for (uint256 i = 0; i < numberOfIntervals; i++) {
                uint256 interest = (principal * intervalRate) / 1e20;
                principal += interest;
            }

            // Calculate remaining days that don't fit into the full 10-day interval
            uint256 remainingDays = durationInDays % 10;
            uint256 remainingInterest = (principal * dailyRate * remainingDays) / 1e20;
            principal += remainingInterest;
        } else {
            principal += (principal * dailyRate * durationInDays) / 1e20;
        }

        return principal - originalPrincipal;
    }

    /// @notice Calculates the amount after fee and the fee itself
    /// @param amount Initial amount
    /// @return fee Calculated fee
    /// @return amountAfterFee Amount after fee deduction
    function calculateAmountAfterFeeAndFee(uint256 amount) internal view returns (uint256, uint256) {
        uint256 fee = (amount * feePercent) / 10000;
        uint256 amountAfterFee = amount - fee;
        return (fee, amountAfterFee);
    }
}
