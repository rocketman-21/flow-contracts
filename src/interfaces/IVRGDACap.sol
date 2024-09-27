// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

interface IVRGDACap {
    /**
     * @notice Initializes the VRGDAC contract
     * @param priceDecayPercent The percent price decays per unit of time with no sales, scaled by 1e18.
     * @param perTimeUnit The number of tokens to target selling in 1 full unit of time, scaled by 1e18.
     */
    function __VRGDACap_init(int256 priceDecayPercent, int256 perTimeUnit) external;

    function xToY(
        int256 timeSinceStart,
        int256 sold,
        int256 amount,
        int256 avgTargetPrice
    ) external view returns (int256);
}
