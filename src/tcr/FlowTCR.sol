// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import { GeneralizedTCR } from "./GeneralizedTCR.sol";
import { IArbitrator } from "./interfaces/IArbitrator.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IManagedFlow } from "../interfaces/IManagedFlow.sol";
import { FlowStorageV1 } from "../storage/FlowStorageV1.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IOwnable2Step } from "../interfaces/IOwnable2Step.sol";
import { ERC20VotesArbitrator } from "./ERC20VotesArbitrator.sol";
import { IERC20VotesArbitrator } from "./interfaces/IERC20VotesArbitrator.sol";
import { IFlowTCR } from "./interfaces/IGeneralizedTCR.sol";
import { ERC20VotesMintable } from "../ERC20VotesMintable.sol";
import { IERC20Mintable } from "../interfaces/IERC20Mintable.sol";

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

    // The address of the FlowTCR implementation contract
    address public flowTCRImpl;

    constructor() payable initializer {}

    /**
     * @dev Initializes the FlowTCR contract with necessary parameters and links it to a Flow contract.
     * @param _flowContract The address of the Flow contract this TCR will manage
     * @param _flowTCRImpl The address of the FlowTCR implementation contract
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
        address _flowTCRImpl,
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
        flowTCRImpl = _flowTCRImpl;
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
     * @dev IMPORTANT: Assumes that the itemID is consistent with the recipientId in the Flow contract
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
            address newTCR = _deployFlowTCR();
            flowContract.addFlowRecipient(metadata, newTCR);
        }
    }

    /**
     * @notice Deploys a new Flow TCR contract as a recipient
     * @dev This function deploys a new FlowTCR and its associated Arbitrator
     * @return address The address of the newly created FlowTCR contract
     */
    function _deployFlowTCR() internal returns (address) {
        // Deploy FlowTCR implementation and proxy
        address flowTCRProxy = address(new ERC1967Proxy(flowTCRImpl, ""));

        // Deploy ERC20VotesArbitrator implementation and proxy
        address arbitratorProxy = address(new ERC1967Proxy(address(new ERC20VotesArbitrator()), ""));

        // Deploy ERC20VotesMintable implementation and proxy
        address erc20Proxy = address(new ERC1967Proxy(address(new ERC20VotesMintable()), ""));

        // Initialize the ERC20VotesMintable token
        IERC20Mintable(erc20Proxy).initialize({
            initialOwner: owner(), // Initial owner
            minter: owner(), // todo update to token emitter
            name: "Flow TCR Token", // Token name
            symbol: "FTT" // Token symbol
        });

        // Initialize the arbitrator
        IERC20VotesArbitrator(arbitratorProxy).initialize({
            votingToken: address(erc20Proxy),
            arbitrable: flowTCRProxy,
            votingPeriod: ERC20VotesArbitrator(arbitratorProxy)._votingPeriod(),
            votingDelay: ERC20VotesArbitrator(arbitratorProxy)._votingDelay(),
            revealPeriod: ERC20VotesArbitrator(arbitratorProxy)._revealPeriod(),
            appealPeriod: ERC20VotesArbitrator(arbitratorProxy)._appealPeriod(),
            appealCost: ERC20VotesArbitrator(arbitratorProxy)._appealCost(),
            arbitrationCost: ERC20VotesArbitrator(arbitratorProxy)._arbitrationCost()
        });

        // Initialize the FlowTCR
        IFlowTCR(flowTCRProxy).initialize({
            flowContract: IManagedFlow(address(flowContract)),
            arbitrator: IArbitrator(arbitratorProxy),
            flowTCRImpl: flowTCRImpl,
            arbitratorExtraData: arbitratorExtraData,
            registrationMetaEvidence: registrationMetaEvidence,
            clearingMetaEvidence: clearingMetaEvidence,
            governor: owner(),
            erc20: IERC20(address(erc20Proxy)),
            submissionBaseDeposit: submissionBaseDeposit,
            removalBaseDeposit: removalBaseDeposit,
            submissionChallengeBaseDeposit: submissionChallengeBaseDeposit,
            removalChallengeBaseDeposit: removalChallengeBaseDeposit,
            challengePeriodDuration: challengePeriodDuration,
            stakeMultipliers: [sharedStakeMultiplier, winnerStakeMultiplier, loserStakeMultiplier]
        });

        // Transfer ownership of the FlowTCR to the owner of this contract
        IOwnable2Step(flowTCRProxy).transferOwnership(owner());
        IOwnable2Step(arbitratorProxy).transferOwnership(owner());
        IOwnable2Step(erc20Proxy).transferOwnership(owner());

        return flowTCRProxy;
    }
}
