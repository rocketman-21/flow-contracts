// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import { FlowStorageV1 } from "../storage/FlowStorageV1.sol";

interface IManagedFlow {
    /**
     * @notice Adds an address to the list of approved recipients
     * @param recipient The address to be added as an approved recipient
     * @param metadata The metadata of the recipient
     */
    function addRecipient(address recipient, FlowStorageV1.RecipientMetadata memory metadata) external;

    /**
     * @notice Adds a new Flow contract as a recipient
     * @param metadata The metadata of the recipient
     * @param flowManager The address of the flow manager for the new contract
     * @return address The address of the newly created Flow contract
     */
    function addFlowRecipient(
        FlowStorageV1.RecipientMetadata memory metadata,
        address flowManager
    ) external returns (address);

    /**
     * @notice Removes a recipient for receiving funds
     * @param recipientId The ID of the recipient to be removed
     */
    function removeRecipient(uint256 recipientId) external;
}
