// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import { RewardSplits } from "./RewardSplits.sol";

abstract contract FlowProtocolRewards is RewardSplits {
    constructor(
        address _protocolRewards,
        address _revolutionRewardRecipient
    ) payable RewardSplits(_protocolRewards, _revolutionRewardRecipient) {}

    function _handleRewardsAndGetValueToSend(
        uint256 msgValue,
        address builderReferral,
        address purchaseReferral
    ) internal returns (uint256) {
        return msgValue - _depositPurchaseRewards(msgValue, builderReferral, purchaseReferral);
    }
}
