// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import { wadLn } from "../libs/SignedWadMath.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title Continuous Variable Rate Gradual Dutch Auction
/// @author transmissions11 <t11s@paradigm.xyz>
/// @author FrankieIsLost <frankie@paradigm.xyz>
/// @author Dan Robinson <dan@paradigm.xyz>
/// @notice Sell tokens roughly according to an issuance schedule.
contract BondingSCurve is UUPSUpgradeable, OwnableUpgradeable {
    /*//////////////////////////////////////////////////////////////
                            CURVE PARAMETERS
    //////////////////////////////////////////////////////////////*/

    // Curve equation:
    // f(x) = c / (1 + e^(-m(x + b))) + d
    // Where:
    // f(x) is the price
    // x is the number of tokens sold
    // c is the curve's maximum value
    // m is the curve's steepness
    // b is the x-axis shift (supply offset)
    // d is the y-axis shift (base price)

    // equivalent to `m`
    int256 public curveSteepness;

    // equivalent to `d`
    int256 public basePrice;

    // equivalent to `c`
    int256 public maxPriceIncrease;

    // equivalent to `b`
    int256 public supplyOffset;

    ///                                                          ///
    ///                         CONSTRUCTOR                      ///
    ///                                                          ///

    constructor() payable initializer {}

    ///                                                          ///
    ///                           ERRORS                         ///
    ///                                                          ///

    /// @notice Reverts for address zero
    error INVALID_ADDRESS_ZERO();

    ///                                                          ///
    ///                         INITIALIZER                      ///
    ///                                                          ///

    /// @notice Sets target price and per time unit price decay for the VRGDA.
    /// @param _initialOwner The initial owner of the contract
    /// @param _curveSteepness The steepness of the curve, scaled by 1e18.
    /// @param _basePrice The base price for a token if sold on pace, scaled by 1e18.
    /// @param _maxPriceIncrease The maximum price increase for a token if sold on pace, scaled by 1e18.
    /// @param _supplyOffset The supply offset for a token if sold on pace, scaled by 1e18.
    function initialize(
        address _initialOwner,
        int256 _curveSteepness,
        int256 _basePrice,
        int256 _maxPriceIncrease,
        int256 _supplyOffset
    ) public initializer {
        if (_initialOwner == address(0)) revert INVALID_ADDRESS_ZERO();

        __Ownable_init();

        _transferOwnership(_initialOwner);

        curveSteepness = _curveSteepness;
        basePrice = _basePrice;
        maxPriceIncrease = _maxPriceIncrease;
        supplyOffset = _supplyOffset;
    }

    /*//////////////////////////////////////////////////////////////
                              PRICING LOGIC
    //////////////////////////////////////////////////////////////*/

    // y to pay
    // given # of tokens sold and # to buy, returns amount to pay
    function xToY(int256 sold, int256 amount) public view virtual returns (int256) {
        return pIntegral(sold + amount) - pIntegral(sold);
    }

    // given amount to pay for tokens, returns # of tokens to sell - raw form
    function yToX(int256 sold, int256 amount) public view virtual returns (int256) {}

    // given # of tokens sold, returns the integral of price p(x), or the total amount paid for the tokens sold
    function pIntegral(int256 sold) internal view returns (int256) {}

    // given total tokens sold, returns the price of the next token to be sold
    function p(int256 sold) internal view returns (int256) {}

    ///                                                          ///
    ///                        VRGDA UPGRADE                     ///
    ///                                                          ///

    /// @notice Ensures the caller is authorized to upgrade the contract
    /// @dev This function is called in `upgradeTo` & `upgradeToAndCall`
    /// @param _newImpl The new implementation address
    function _authorizeUpgrade(address _newImpl) internal view override onlyOwner {}
}
