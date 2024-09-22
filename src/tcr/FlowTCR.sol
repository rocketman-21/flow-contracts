// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import { GeneralizedTCR } from "./GeneralizedTCR.sol";
import { IArbitrator } from "./interfaces/IArbitrator.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IManagedFlow } from "../interfaces/IManagedFlow.sol";
import { FlowTypes } from "../storage/FlowStorageV1.sol";
import { ITCRFactory } from "./interfaces/ITCRFactory.sol";
import { FlowRecipients } from "../library/FlowRecipients.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";

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

    // The address of the TCR factory
    ITCRFactory public tcrFactory;

    constructor() payable initializer {}

    /**
     * @dev Initializes the FlowTCR contract with necessary parameters and links it to a Flow contract.
     * @param _contractParams Struct containing address parameters and interfaces
     * @param _tcrParams Struct containing TCR parameters, including deposits, durations, and evidence
     */
    function initialize(ContractParams memory _contractParams, TCRParams memory _tcrParams) public initializer {
        flowContract = _contractParams.flowContract;
        tcrFactory = _contractParams.tcrFactory;
        __GeneralizedTCR_init(
            _contractParams.initialOwner,
            _contractParams.arbitrator,
            _tcrParams.arbitratorExtraData,
            _tcrParams.registrationMetaEvidence,
            _tcrParams.clearingMetaEvidence,
            _contractParams.governor,
            _contractParams.erc20,
            _tcrParams.submissionBaseDeposit,
            _tcrParams.removalBaseDeposit,
            _tcrParams.submissionChallengeBaseDeposit,
            _tcrParams.removalChallengeBaseDeposit,
            _tcrParams.challengePeriodDuration,
            _tcrParams.stakeMultipliers
        );
    }

    /**
     * @notice Removes an item from the Flow contract when it's removed from the TCR
     * @param _itemID The ID of the item being removed
     * @dev This function is called internally when an item is removed from the TCR
     * @dev IMPORTANT: Assumes that the itemID is consistent with the recipientId in the Flow contract
     */
    function _onItemRemoved(bytes32 _itemID) internal override {
        flowContract.removeRecipient(_itemID);
    }

    /**
     * @dev Verifies the data of an item before it's added to the registry.
     * @param _item The data describing the item to be added.
     * @return valid True if the item data is valid, false otherwise.
     */
    function _verifyItemData(bytes calldata _item) internal pure override returns (bool valid) {
        (address recipient, FlowTypes.RecipientMetadata memory metadata, FlowTypes.RecipientType recipientType) = abi
            .decode(_item, (address, FlowTypes.RecipientMetadata, FlowTypes.RecipientType));

        // Check if recipient is a valid address
        if (recipient == address(0)) {
            return false;
        }

        // Check if metadata is valid
        FlowRecipients.validateMetadata(metadata);

        // Check if recipientType is valid
        if (
            recipientType != FlowTypes.RecipientType.ExternalAccount &&
            recipientType != FlowTypes.RecipientType.FlowContract
        ) {
            return false;
        }

        return true;
    }

    /**
     * @notice Handles the registration of an item in the TCR
     * @param _item The data describing the item
     * @dev This function is called internally when an item is registered in the TCR
     */
    function _onItemRegistered(bytes32, bytes memory _item) internal override {
        // Note: The unused variable has been removed
        // Decode the item data
        (address recipient, FlowTypes.RecipientMetadata memory metadata, FlowTypes.RecipientType recipientType) = abi
            .decode(_item, (address, FlowTypes.RecipientMetadata, FlowTypes.RecipientType));

        // Add the recipient to the Flow contract
        if (recipientType == FlowTypes.RecipientType.ExternalAccount) {
            flowContract.addRecipient(recipient, metadata);
        } else if (recipientType == FlowTypes.RecipientType.FlowContract) {
            // temporarily set manager to owner
            (, address flowRecipient) = flowContract.addFlowRecipient(metadata, owner(), owner());

            ITCRFactory.DeployedContracts memory deployedContracts = tcrFactory.deployFlowTCR(
                ITCRFactory.FlowTCRParams({
                    flowContract: IManagedFlow(flowRecipient),
                    arbitratorExtraData: arbitratorExtraData,
                    registrationMetaEvidence: registrationMetaEvidence,
                    clearingMetaEvidence: clearingMetaEvidence,
                    governor: governor,
                    submissionBaseDeposit: submissionBaseDeposit,
                    removalBaseDeposit: removalBaseDeposit,
                    submissionChallengeBaseDeposit: submissionChallengeBaseDeposit,
                    removalChallengeBaseDeposit: removalChallengeBaseDeposit,
                    challengePeriodDuration: challengePeriodDuration,
                    stakeMultipliers: [sharedStakeMultiplier, winnerStakeMultiplier, loserStakeMultiplier]
                }),
                arbitrator.getArbitratorParamsForFactory(),
                ITCRFactory.ERC20Params({ initialOwner: owner(), minter: owner(), name: "TCR Test", symbol: "TCRT" }), // TODO update all
                ITCRFactory.RewardPoolParams({ superToken: ISuperToken(flowContract.getSuperToken()) })
            );

            // set manager to new TCR and manager reward pool
            flowContract.setManager(deployedContracts.tcrAddress);
            flowContract.setManagerRewardPool(deployedContracts.rewardPoolAddress);
        }
    }
}
