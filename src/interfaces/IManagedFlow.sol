// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import { FlowTypes } from "../storage/FlowStorageV1.sol";

interface IManagedFlow {
    /**
     * @notice Adds an address to the list of approved recipients
     * @param recipient The address to be added as an approved recipient
     * @param metadata The metadata of the recipient
     * @return recipientId The ID of the recipient
     * @return recipientAddress The address of the newly created Flow contract
     */
    function addRecipient(
        address recipient,
        FlowTypes.RecipientMetadata memory metadata
    ) external returns (bytes32 recipientId, address recipientAddress);

    /**
     * @notice Adds a new Flow contract as a recipient
     * @param metadata The metadata of the recipient
     * @param flowManager The address of the flow manager for the new contract
     * @param managerRewardPool The address of the manager reward pool for the new contract
     * @return recipientId The ID of the recipient
     * @return recipientAddress The address of the newly created Flow contract
     */
    function addFlowRecipient(
        FlowTypes.RecipientMetadata memory metadata,
        address flowManager,
        address managerRewardPool
    ) external returns (bytes32 recipientId, address recipientAddress);

    /**
     * @notice Removes a recipient for receiving funds
     * @param recipientId The ID of the recipient to be removed
     */
    function removeRecipient(bytes32 recipientId) external;

    /**
     * @notice Sets a new manager for the Flow contract
     * @param _newManager The address of the new manager
     */
    function setManager(address _newManager) external;

    /**
     * @notice Sets a new manager reward pool for the Flow contract
     * @param _newManagerRewardPool The address of the new manager reward pool
     */
    function setManagerRewardPool(address _newManagerRewardPool) external;

    /**
     * @notice Returns the SuperToken address
     * @return The address of the SuperToken
     */
    function getSuperToken() external view returns (address);
}
