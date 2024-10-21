// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

interface IVRGDACap {
    function xToY(
        int256 timeSinceStart,
        int256 sold,
        int256 amount,
        int256 avgTargetPrice
    ) external view returns (int256);
}
