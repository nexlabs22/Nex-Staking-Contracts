// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {NexStaging} from "../NexStaging.sol";

library CalculationHelper {
    function calculateAmountAfterFeeAndFee(uint256 amount, uint256 feePercent)
        internal
        pure
        returns (uint256, uint256)
    {
        uint256 fee = (amount * feePercent) / 10000;
        uint256 amountAfterFee = amount - fee;
        return (fee, amountAfterFee);
    }

    // function calculateWeightOfPools() internal view returns (uint256[] memory) {
    //     uint256 totalStakedAcrossAllPools = 0;
    //     uint256[] memory weights = new uint256[](NexStaging.poolTokens().length);

    //     for (uint256 i = 0; i < NexStaging.poolTokens.length; i++) {
    //         totalStakedAcrossAllPools += NexStaging.pools[NexStaging.poolTokens[i]].totalStaked;
    //     }

    //     for (uint256 i = 0; i < NexStaging.poolTokens.length; i++) {
    //         weights[i] = (NexStaging.pools[NexStaging.poolTokens[i]].totalStaked * 1e18) / totalStakedAcrossAllPools;
    //     }

    //     return weights;
    // }
}
