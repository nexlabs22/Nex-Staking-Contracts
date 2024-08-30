// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

library CalculationHelpers {
    function calculateAmountAfterFeeAndFee(uint256 amount, uint256 feePercent)
        internal
        pure
        returns (uint256 fee, uint256 amountAfterFee)
    {
        fee = (amount * feePercent) / 10000;
        amountAfterFee = amount - fee;
    }
}
