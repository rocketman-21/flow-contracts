// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import { wadLn, wadExp, wadMul, wadDiv } from "../libs/SignedWadMath.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

/// @title Bonding S-Curve
/// @author rocketman
/// @author Math help from o1
contract BondingSCurve is UUPSUpgradeable, OwnableUpgradeable {
    /*//////////////////////////////////////////////////////////////
                            CURVE PARAMETERS
    //////////////////////////////////////////////////////////////*/

    // Curve equation:
    // https://www.desmos.com/calculator/zhnlvsr28w
    // p(x) = c / (1 + e^(-m(x + b))) + d
    // Where:
    // p(x) is the price of the next token
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

    /// @notice Reverts for negative amount
    error INVALID_AMOUNT();

    /// @notice Reverts for invalid amount of tokens sold
    error INVALID_SOLD_AMOUNT();

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
    function costToBuy(int256 sold, int256 amount) public view virtual returns (int256) {
        if (sold < 0) revert INVALID_SOLD_AMOUNT();
        if (amount < 0) revert INVALID_AMOUNT();

        return pIntegral(sold + amount) - pIntegral(sold);
    }

    // given # of tokens sold and # to sell, returns the payment for selling
    function paymentToSell(int256 sold, int256 amount) public view virtual returns (int256) {
        if (amount < 0) revert INVALID_AMOUNT();
        int256 newSold = sold - amount;
        if (newSold < 0) revert INVALID_SOLD_AMOUNT();

        // Calculate the payment by finding the difference in the integral of the price function
        // given the current total sold amount and the new total sold amount
        return pIntegral(sold) - pIntegral(newSold);
    }

    // given # of tokens sold, returns the integral of price p(x), or the total amount paid for the tokens sold
    function pIntegral(int256 sold) internal view returns (int256) {
        // y(x) = (c * (ln(e^(mx + bm) + 1))) / m + d * x

        // Calculate m * (sold + b)
        int256 m_times_x_plus_b = wadMul(curveSteepness, sold + supplyOffset);

        // Calculate e ^ (m * (sold + b))
        int256 exp_term = wadExp(m_times_x_plus_b);

        // Calculate ln(exp(m * (sold + b)) + 1)
        int256 ln_term = wadLn(exp_term + 1e18);

        // Compute c * ln(...) / m
        // Multiply before dividing to maintain precision
        int256 numerator = wadMul(maxPriceIncrease, ln_term);
        int256 term1 = wadDiv(numerator, curveSteepness);

        // Compute d * x
        int256 term2 = wadMul(basePrice, sold);

        // Add the two terms together
        return term1 + term2;
    }

    ///                                                          ///
    ///                        VRGDA UPGRADE                     ///
    ///                                                          ///

    /// @notice Ensures the caller is authorized to upgrade the contract
    /// @dev This function is called in `upgradeTo` & `upgradeToAndCall`
    /// @param _newImpl The new implementation address
    function _authorizeUpgrade(address _newImpl) internal view override onlyOwner {}
}
