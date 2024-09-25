// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.27;

interface IRewardSplits {
    struct RewardsSettings {
        uint256 builderReferralReward;
        uint256 purchaseReferralReward;
        uint256 revolutionReward;
    }

    function computeTotalReward(uint256 paymentAmountWei) external pure returns (uint256);

    function computePurchaseRewards(uint256 paymentAmountWei) external pure returns (RewardsSettings memory, uint256);
}
