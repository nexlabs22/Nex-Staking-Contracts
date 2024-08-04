// SPDX-License-Identifier: SEE LICENSE IN LICENSE
pragma solidity ^0.8.26;

import {NexStaging} from "../NexStaging.sol";

library CalculationHelper {
    function calculateReward(NexStaging.StakePositions storage position) internal view returns (uint256) {
        uint256 duration = block.timestamp - position.startTime;
        uint256 dailyRate = position.apy * 1e18 / 365;

        if (position.autoCompound) {
            uint256 compoundedStakeAmount = position.stakeAmount;
            for (uint256 i = 0; i < duration / 1 days; i++) {
                uint256 interest = (compoundedStakeAmount * dailyRate) / 1e20;
                compoundedStakeAmount += interest;
            }
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
