// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {NexStaging} from "../NexStaging.sol";

library CalculationHelper {
    function calculateReward(NexStaging.StakePosition storage position, uint256 apy) internal view returns (uint256) {
        uint256 duration = block.timestamp - position.startTime;
        uint256 dailyRate = apy * 1e18 / 365;

        uint256 interval = 7 days;
        uint256 intervalRate = dailyRate * 7;

        if (position.autoCompound) {
            uint256 compoundedStakeAmount = position.stakeAmount;
            uint256 numberOfIntervals = duration / interval;

            for (uint256 i = 0; i < numberOfIntervals; i++) {
                uint256 interest = (compoundedStakeAmount * intervalRate) / 1e20;
                compoundedStakeAmount += interest;
            }

            uint256 remainingDays = (duration % interval) / 1 days;
            uint256 remainingInterest = (compoundedStakeAmount * dailyRate * remainingDays) / 1e20;
            compoundedStakeAmount += remainingInterest;

            return compoundedStakeAmount - position.stakeAmount;
        } else {
            return (position.stakeAmount * dailyRate * duration / 1 days) / 1e20;
        }
    }

    function calculateAmountAfterFeeAndFee(uint256 amount, uint256 feePercent)
        internal
        pure
        returns (uint256, uint256)
    {
        uint256 fee = (amount * feePercent) / 10000;
        uint256 amountAfterFee = amount - fee;
        return (fee, amountAfterFee);
    }
}
