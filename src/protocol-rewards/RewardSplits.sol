// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import { IProtocolRewards } from "./interfaces/IProtocolRewards.sol";
import { IRewardSplits } from "./interfaces/IRewardSplits.sol";

/**
 * @title RewardSplits
 * @notice Common logic for TokenEmitter contracts for protocol reward splits & deposits
 */
abstract contract RewardSplits is IRewardSplits {
    // 2.25% total
    uint256 internal constant REVOLUTION_REWARD_BPS = 75;
    uint256 internal constant BUILDER_REWARD_BPS = 100;
    uint256 internal constant PURCHASE_REFERRAL_BPS = 50;

    address internal immutable revolutionRewardRecipient;
    IProtocolRewards internal immutable protocolRewards;

    /**
     * @notice Initializes the RewardSplits contract
     * @param _protocolRewards The address of the protocol rewards contract
     * @param _revolutionRewardRecipient The address of the revolution reward recipient
     */
    constructor(address _protocolRewards, address _revolutionRewardRecipient) payable {
        if (_protocolRewards == address(0) || _revolutionRewardRecipient == address(0)) revert("Invalid Address Zero");

        protocolRewards = IProtocolRewards(_protocolRewards);
        revolutionRewardRecipient = _revolutionRewardRecipient;
    }

    /**
     * @notice Computes the total reward amount based on the payment amount
     * @param paymentAmountWei The amount of ETH being paid for the purchase
     * @return The total reward amount
     */
    function computeTotalReward(uint256 paymentAmountWei) public pure override returns (uint256) {
        return
            ((paymentAmountWei * BUILDER_REWARD_BPS) / 10_000) +
            ((paymentAmountWei * PURCHASE_REFERRAL_BPS) / 10_000) +
            ((paymentAmountWei * REVOLUTION_REWARD_BPS) / 10_000);
    }

    /**
     * @notice Computes the purchase rewards and total reward amount
     * @param paymentAmountWei The amount of ETH being paid for the purchase
     * @return settings The computed reward settings
     * @return totalReward The total reward amount
     */
    function computePurchaseRewards(
        uint256 paymentAmountWei
    ) public pure override returns (RewardsSettings memory, uint256) {
        return (
            RewardsSettings({
                builderReferralReward: (paymentAmountWei * BUILDER_REWARD_BPS) / 10_000,
                purchaseReferralReward: (paymentAmountWei * PURCHASE_REFERRAL_BPS) / 10_000,
                revolutionReward: (paymentAmountWei * REVOLUTION_REWARD_BPS) / 10_000
            }),
            computeTotalReward(paymentAmountWei)
        );
    }

    /**
     * @notice Deposits purchase rewards to the protocol rewards contract
     * @param paymentAmountWei The amount of ETH being paid for the purchase
     * @param builderReferral The address of the builder referral
     * @param purchaseReferral The address of the purchase referral
     * @return The total reward amount deposited
     */
    function _depositPurchaseRewards(
        uint256 paymentAmountWei,
        address builderReferral,
        address purchaseReferral
    ) internal returns (uint256) {
        (RewardsSettings memory settings, uint256 totalReward) = computePurchaseRewards(paymentAmountWei);

        if (builderReferral == address(0)) builderReferral = revolutionRewardRecipient;

        if (purchaseReferral == address(0)) purchaseReferral = revolutionRewardRecipient;

        protocolRewards.depositRewards{ value: totalReward }(
            builderReferral,
            settings.builderReferralReward,
            purchaseReferral,
            settings.purchaseReferralReward,
            revolutionRewardRecipient,
            settings.revolutionReward
        );

        return totalReward;
    }
}
