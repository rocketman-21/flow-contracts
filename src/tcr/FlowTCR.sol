// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import { GeneralizedTCR } from "./GeneralizedTCR.sol";
import { IArbitrator } from "./interfaces/IArbitrator.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IManagedFlow } from "../interfaces/IManagedFlow.sol";
import { FlowStorageV1 } from "../storage/FlowStorageV1.sol";
/**
 * @title FlowTCR
 * @dev This contract extends GeneralizedTCR to provide a Token Curated Registry (TCR)
 * specifically designed to interface with the Flow.sol contract as a manager.
 * It allows for the curation of recipients in the Flow ecosystem through a
 * decentralized voting and challenge process.
 */
contract FlowTCR is GeneralizedTCR {
    // The Flow contract this TCR is managing
    IManagedFlow public flowContract;

    constructor() payable initializer {}

    /**
     * @dev Initializes the FlowTCR contract with necessary parameters and links it to a Flow contract.
     * @param _flowContract The address of the Flow contract this TCR will manage
     * @param _arbitrator The arbitrator to resolve disputes
     * @param _arbitratorExtraData Extra data for the arbitrator
     * @param _registrationMetaEvidence MetaEvidence for registration requests
     * @param _clearingMetaEvidence MetaEvidence for removal requests
     * @param _governor The governor of this contract
     * @param _erc20 The ERC20 token used for deposits and challenges
     * @param _submissionBaseDeposit Base deposit for submitting an item
     * @param _removalBaseDeposit Base deposit for removing an item
     * @param _submissionChallengeBaseDeposit Base deposit for challenging a submission
     * @param _removalChallengeBaseDeposit Base deposit for challenging a removal
     * @param _challengePeriodDuration Duration of the challenge period
     * @param _stakeMultipliers Multipliers for appeals
     */
    function initialize(
        IManagedFlow _flowContract,
        IArbitrator _arbitrator,
        bytes memory _arbitratorExtraData,
        string memory _registrationMetaEvidence,
        string memory _clearingMetaEvidence,
        address _governor,
        IERC20 _erc20,
        uint _submissionBaseDeposit,
        uint _removalBaseDeposit,
        uint _submissionChallengeBaseDeposit,
        uint _removalChallengeBaseDeposit,
        uint _challengePeriodDuration,
        uint[3] memory _stakeMultipliers
    ) public initializer {
        flowContract = _flowContract;
        __GeneralizedTCR_init(
            _arbitrator,
            _arbitratorExtraData,
            _registrationMetaEvidence,
            _clearingMetaEvidence,
            _governor,
            _erc20,
            _submissionBaseDeposit,
            _removalBaseDeposit,
            _submissionChallengeBaseDeposit,
            _removalChallengeBaseDeposit,
            _challengePeriodDuration,
            _stakeMultipliers
        );
    }

    /**
     * @notice Removes an item from the Flow contract when it's removed from the TCR
     * @param _itemID The ID of the item being removed
     * @dev This function is called internally when an item is removed from the TCR
     */
    function _onItemRemoved(bytes32 _itemID) internal override {
        flowContract.removeRecipient(_itemID);
    }

    /**
     * @notice Handles the registration of an item in the TCR
     * @param _itemID The ID of the item being registered
     * @param _item The data describing the item
     * @dev This function is called internally when an item is registered in the TCR
     */
    function _onItemRegistered(bytes32 _itemID, bytes memory _item) internal override {
        // Note: The unused variable has been removed
        // Decode the item data
        (
            address recipient,
            FlowStorageV1.RecipientMetadata memory metadata,
            FlowStorageV1.RecipientType recipientType
        ) = abi.decode(_item, (address, FlowStorageV1.RecipientMetadata, FlowStorageV1.RecipientType));

        // Add the recipient to the Flow contract
        if (recipientType == FlowStorageV1.RecipientType.ExternalAccount) {
            flowContract.addRecipient(recipient, metadata);
        } else if (recipientType == FlowStorageV1.RecipientType.FlowContract) {
            address flowManager = address(0x1); // TODO: Get this by creating new TCR
            flowContract.addFlowRecipient(metadata, flowManager);
        }
    }
}
