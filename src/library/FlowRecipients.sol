// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import { FlowTypes } from "../storage/FlowStorageV1.sol";
import { IFlowEvents, IFlow } from "../interfaces/IFlow.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import { ISuperfluidPool } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/gdav1/ISuperfluidPool.sol";

library FlowRecipients {
    /**
     * @notice Removes a recipient for receiving funds
     * @param recipientId The ID of the recipient to be approved
     * @dev Only callable by the manager of the contract
     * @dev Emits a RecipientRemoved event if the recipient is successfully removed
     */
    function removeRecipient(FlowTypes.Storage storage fs, bytes32 recipientId) external returns (address) {
        if (fs.recipients[recipientId].recipient == address(0)) revert IFlow.INVALID_RECIPIENT_ID();
        if (fs.recipients[recipientId].removed) revert IFlow.RECIPIENT_ALREADY_REMOVED();

        address recipientAddress = fs.recipients[recipientId].recipient;
        fs.recipientExists[recipientAddress] = false;

        emit IFlowEvents.RecipientRemoved(recipientAddress, recipientId);

        fs.recipients[recipientId].removed = true;
        fs.activeRecipientCount--;

        return recipientAddress;
    }
}
