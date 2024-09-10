// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;


library FlowLibraryV1 {
    /**
     *  @notice Multiplies an amount by a scaled percentage
     *  @param amount Amount to get `scaledPercentage` of
     *  @param scaledPercent Percent scaled by PERCENTAGE_SCALE
     *  @return scaledAmount Percent of `amount`.
     */
    function scaleAmountByPercentage(uint256 amount, uint256 scaledPercent, uint256 percentageScale)
        public
        pure
        returns (uint256 scaledAmount)
    {
        // use assembly to bypass checking for overflow & division by 0
        // scaledPercent has been validated to be < PERCENTAGE_SCALE)
        // & PERCENTAGE_SCALE will never be 0
        assembly {
            /* eg (100 * 2*1e4) / (1e6) */
            scaledAmount := div(mul(amount, scaledPercent), percentageScale)
        }
    }

    /**
     * @notice Sums array of uint32s
     *  @param numbers Array of uint32s to sum
     *  @return sum Sum of `numbers`.
     */
    function getSum(uint32[] memory numbers) public pure returns (uint32 sum) {
        // overflow should be impossible in for-loop index
        uint256 numbersLength = numbers.length;
        for (uint256 i = 0; i < numbersLength;) {
            sum += numbers[i];
            unchecked {
                // overflow should be impossible in for-loop index
                ++i;
            }
        }
    }
}