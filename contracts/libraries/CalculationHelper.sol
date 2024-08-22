// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

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
}
