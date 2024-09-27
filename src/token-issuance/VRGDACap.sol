// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import { wadExp, wadLn, wadMul, wadDiv, unsafeWadDiv, wadPow } from "../libs/SignedWadMath.sol";
import { IVRGDACap } from "../interfaces/IVRGDACap.sol";

/// @title Continuous Variable Rate Gradual Dutch Auction Cap Functionality
/// @author transmissions11 <t11s@paradigm.xyz>
/// @author FrankieIsLost <frankie@paradigm.xyz>
/// @author Dan Robinson <dan@paradigm.xyz>
/// @notice Sell tokens roughly according to an issuance schedule.
/// @notice Modifications by rocketman21.eth
/// Changes:
/// - Removed targetPrice and replaced it with function parameters for avgTargetPrice
abstract contract VRGDACap is IVRGDACap {
    /*//////////////////////////////////////////////////////////////
                            VRGDACap PARAMETERS
    //////////////////////////////////////////////////////////////*/

    int256 public perTimeUnit;

    int256 public decayConstant;

    int256 public priceDecayPercent;

    ///                                                          ///
    ///                         INITIALIZER                      ///
    ///                                                          ///

    /// @notice Sets price decay percent and per time unit for the VRGDACap.
    /// @param _priceDecayPercent The percent price decays per unit of time with no sales, scaled by 1e18.
    /// @param _perTimeUnit The number of tokens to target selling in 1 full unit of time, scaled by 1e18.
    function __VRGDACap_init(int256 _priceDecayPercent, int256 _perTimeUnit) public {
        perTimeUnit = _perTimeUnit;

        priceDecayPercent = _priceDecayPercent;

        decayConstant = wadLn(1e18 - _priceDecayPercent);

        // The decay constant must be negative for VRGDAs to work.
        require(decayConstant < 0, "NON_NEGATIVE_DECAY_CONSTANT");
    }

    /*//////////////////////////////////////////////////////////////
                              PRICING LOGIC
    //////////////////////////////////////////////////////////////*/

    // given # of tokens sold and # to buy, returns amount to pay
    // adds 1 avg target price to the function
    // mvp of dynamic target pricing for the token emitter
    function xToY(
        int256 timeSinceStart,
        int256 sold,
        int256 amount,
        int256 avgTargetPrice
    ) public view virtual returns (int256) {
        return
            pIntegral(timeSinceStart, sold + amount, avgTargetPrice) - pIntegral(timeSinceStart, sold, avgTargetPrice);
    }

    // given # of tokens sold, returns integral of price p(x) = p0 * (1 - k)^(t - x/r)
    function pIntegral(int256 timeSinceStart, int256 sold, int256 targetPrice) internal view returns (int256) {
        return
            wadDiv(
                -wadMul(
                    wadMul(targetPrice, perTimeUnit),
                    wadPow(1e18 - priceDecayPercent, timeSinceStart - unsafeWadDiv(sold, perTimeUnit)) -
                        wadPow(1e18 - priceDecayPercent, timeSinceStart)
                ),
                decayConstant
            );
    }
}
