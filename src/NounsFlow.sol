// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {Flow} from "./Flow.sol";
import {FlowStorageV1} from "./storage/FlowStorageV1.sol";
import {IFlow, INounsFlow} from "./interfaces/IFlow.sol";
import {IL2NounsVerifier} from "./interfaces/IL2NounsVerifier.sol";
import {StateVerifier} from "./state-proof/StateVerifier.sol";

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract NounsFlow is INounsFlow, Flow {
    IL2NounsVerifier public verifier;

    // Base state proof parameters, which are the same for all storage proofs in a block
    // for a given account / contract
    struct BaseStateProofParameters {
        bytes32 beaconRoot;
        uint256 beaconOracleTimestamp;
        bytes32 executionStateRoot;
        bytes32[] stateRootProof;
        bytes[] accountProof;
    }

    constructor() payable initializer Flow() {}

    function initialize(
        address _verifier,
        address _superToken,
        address _flowImpl,
        address _manager,
        address _parent,
        FlowParams memory _flowParams,
        RecipientMetadata memory _metadata
    ) public initializer {
        __Flow_init(_superToken, _flowImpl, _manager, _parent, _flowParams, _metadata);

        verifier = IL2NounsVerifier(_verifier);
    }

    /**
     * @notice Cast votes for multiple token owners across multiple tokens.
     * @param owners An array of token owner addresses.
     * @param tokenIds A 2D array of token IDs, where each inner array corresponds to an owner.
     * @param recipientIds An array of recipient IDs for the grant recipients.
     * @param percentAllocations An array of basis points allocations for each recipient.
     * @param baseProofParams The base state proof parameters.
     * @param ownershipStorageProofs A 2D array of storage proofs for token ownership, corresponding to each token ID.
     * @param delegateStorageProofs A 2D array of storage proofs for delegation, corresponding to each token ID.
     */
    function castVotes(
        address[] memory owners,
        uint256[][] memory tokenIds,
        uint256[] memory recipientIds,
        uint32[] memory percentAllocations,
        BaseStateProofParameters calldata baseProofParams,
        bytes[][][] memory ownershipStorageProofs,
        bytes[][] memory delegateStorageProofs
    )
        external
        nonReentrant
        validVotes(recipientIds, percentAllocations)
    {
        for (uint256 i = 0; i < owners.length; i++) {
            StateVerifier.StateProofParameters[] memory ownershipProofs = new StateVerifier.StateProofParameters[](tokenIds[i].length);

            for (uint256 j = 0; j < tokenIds[i].length; j++) {
                ownershipProofs[j] = StateVerifier.StateProofParameters({
                    beaconRoot: baseProofParams.beaconRoot,
                    beaconOracleTimestamp: baseProofParams.beaconOracleTimestamp,
                    executionStateRoot: baseProofParams.executionStateRoot,
                    stateRootProof: baseProofParams.stateRootProof,
                    accountProof: baseProofParams.accountProof,
                    // there is one storage proof for each tokenId
                    storageProof: ownershipStorageProofs[i][j]
                });
            }

            _castVotesForOwner(
                owners[i],
                tokenIds[i],
                recipientIds,
                percentAllocations,
                ownershipProofs,
                // there is one delegate proof for each owner
                StateVerifier.StateProofParameters({
                    beaconRoot: baseProofParams.beaconRoot,
                    beaconOracleTimestamp: baseProofParams.beaconOracleTimestamp,
                    executionStateRoot: baseProofParams.executionStateRoot,
                    stateRootProof: baseProofParams.stateRootProof,
                    accountProof: baseProofParams.accountProof,
                    storageProof: delegateStorageProofs[i]
                })
            );
        }
    }

    /**
     * @notice Cast votes for a set of grant addresses on behalf of a token owner
     * @param owner The address of the token owner
     * @param tokenIds The token IDs that the owner is using to vote
     * @param recipientIds The recipient IDs of the grant recipients
     * @param percentAllocations The basis points of the vote to be split among the recipients
     * @param ownershipProofs The state proofs for token ownership
     * @param delegateProof The state proof for delegation
     */
    function _castVotesForOwner(
        address owner,
        uint256[] memory tokenIds,
        uint256[] memory recipientIds,
        uint32[] memory percentAllocations,
        StateVerifier.StateProofParameters[] memory ownershipProofs,
        StateVerifier.StateProofParameters memory delegateProof
    ) internal {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (!verifier.canVoteWithToken(tokenIds[i], owner, msg.sender, ownershipProofs[i], delegateProof)) revert NOT_ABLE_TO_VOTE_WITH_TOKEN();
            _setVotesAllocationForTokenId(tokenIds[i], recipientIds, percentAllocations);
        }
    }

    /**
     * @notice Deploys a new Flow contract as a recipient
     * @dev This function overrides the base _deployFlowRecipient to use NounsFlow-specific initialization
     * @param metadata The IPFS hash of the recipient's metadata
     * @param flowManager The address of the flow manager for the new contract
     * @return address The address of the newly created Flow contract
     */
    function _deployFlowRecipient(RecipientMetadata memory metadata, address flowManager) internal override returns (address) {
        address recipient = address(new ERC1967Proxy(flowImpl, ""));
        if (recipient == address(0)) revert ADDRESS_ZERO();

        INounsFlow(recipient).initialize({
            verifier: address(verifier),
            superToken: address(superToken),
            flowImpl: flowImpl,
            manager: flowManager,
            parent: address(this),
            flowParams: FlowParams({
                tokenVoteWeight: tokenVoteWeight,
                baselinePoolFlowRatePercent: baselinePoolFlowRatePercent
            }),
            metadata: metadata
        });

        Ownable2StepUpgradeable(recipient).transferOwnership(owner());

        return recipient;
    }
}
