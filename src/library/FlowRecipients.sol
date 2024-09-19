// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import { FlowTypes } from "../storage/FlowStorageV1.sol";
import { IFlowEvents, IFlow } from "../interfaces/IFlow.sol";

library FlowRecipients {
    /**
     * @notice Removes a recipient for receiving funds
     * @param fs The storage of the Flow contract
     * @param recipientId The ID of the recipient to be approved
     * @dev Only callable by the manager of the contract
     * @dev Emits a RecipientRemoved event if the recipient is successfully removed
     */
    function removeRecipient(FlowTypes.Storage storage fs, bytes32 recipientId) external {
        if (fs.recipients[recipientId].recipient == address(0)) revert IFlow.INVALID_RECIPIENT_ID();
        if (fs.recipients[recipientId].removed) revert IFlow.RECIPIENT_ALREADY_REMOVED();

        address recipientAddress = fs.recipients[recipientId].recipient;
        fs.recipientExists[recipientAddress] = false;

        emit IFlowEvents.RecipientRemoved(recipientAddress, recipientId);

        fs.recipients[recipientId].removed = true;
        fs.activeRecipientCount--;
    }

    /**
     * @notice Adds an address to the list of approved recipients
     * @param fs The storage of the Flow contract
     * @param recipient The address to be added as an approved recipient
     * @param metadata The metadata of the recipient
     * @return bytes32 The recipientId of the newly created recipient
     * @return address The address of the newly created recipient
     */
    function addRecipient(
        FlowTypes.Storage storage fs,
        address recipient,
        FlowTypes.RecipientMetadata memory metadata
    ) external returns (bytes32, address) {
        if (recipient == address(0)) revert IFlow.ADDRESS_ZERO();
        if (fs.recipientExists[recipient]) revert IFlow.RECIPIENT_ALREADY_EXISTS();

        bytes32 recipientId = keccak256(abi.encode(recipient, metadata, FlowTypes.RecipientType.ExternalAccount));
        if (fs.recipients[recipientId].recipient != address(0)) revert IFlow.RECIPIENT_ALREADY_EXISTS();

        fs.recipientExists[recipient] = true;

        fs.recipients[recipientId] = FlowTypes.FlowRecipient({
            recipientType: FlowTypes.RecipientType.ExternalAccount,
            removed: false,
            recipient: recipient,
            metadata: metadata
        });

        fs.activeRecipientCount++;

        emit IFlowEvents.RecipientCreated(recipientId, fs.recipients[recipientId], msg.sender);

        return (recipientId, recipient);
    }
}
