// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import { GeneralizedTCR } from "./GeneralizedTCR.sol";
import { IArbitrator } from "./interfaces/IArbitrator.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IManagedFlow } from "../interfaces/IManagedFlow.sol";
import { FlowTypes } from "../storage/FlowStorageV1.sol";
import { ITCRFactory } from "./interfaces/ITCRFactory.sol";
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
     * @param _initialOwner The initial owner of the contract
     * @param _flowContract The address of the Flow contract this TCR will manage
     * @param _arbitrator The arbitrator to resolve disputes
     * @param _tcrFactory The address of the TCR factory
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
        address _initialOwner,
        IManagedFlow _flowContract,
        IArbitrator _arbitrator,
        ITCRFactory _tcrFactory,
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
        tcrFactory = _tcrFactory;
        __GeneralizedTCR_init(
            _initialOwner,
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
     * @dev IMPORTANT: Assumes that the itemID is consistent with the recipientId in the Flow contract
     */
    function _onItemRemoved(bytes32 _itemID) internal override {
        flowContract.removeRecipient(_itemID);
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

            (address newTCR, , , address rewardPool) = tcrFactory.deployFlowTCR(
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
            flowContract.setManager(address(newTCR));
            flowContract.setManagerRewardPool(rewardPool);
        }
    }
}
