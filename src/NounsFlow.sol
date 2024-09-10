// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import { Flow } from "./Flow.sol";
import { INounsFlow } from "./interfaces/IFlow.sol";
import { ITokenVerifier } from "./interfaces/ITokenVerifier.sol";
import { IStateProof } from "./interfaces/IStateProof.sol";

import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract NounsFlow is INounsFlow, Flow {
    ITokenVerifier public verifier;

    constructor() payable initializer {}

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

        verifier = ITokenVerifier(_verifier);
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
        IStateProof.BaseParameters memory baseProofParams,
        bytes[][][] memory ownershipStorageProofs,
        bytes[][] memory delegateStorageProofs
    ) external nonReentrant validVotes(recipientIds, percentAllocations) {
        // if the timestamp is more than 5 minutes old, it is invalid
        // TODO check through security considerations if this is a valid assumption
        if (baseProofParams.beaconOracleTimestamp < block.timestamp - 5 minutes) revert PAST_PROOF();

        for (uint256 i = 0; i < owners.length; i++) {
            IStateProof.Parameters[] memory ownershipProofs = _generateOwnershipProofs(
                baseProofParams,
                ownershipStorageProofs[i]
            );
            IStateProof.Parameters memory delegateProof = _generateStateProofParams(
                baseProofParams,
                delegateStorageProofs[i]
            );

            _castVotesForOwner(
                owners[i],
                tokenIds[i],
                recipientIds,
                percentAllocations,
                ownershipProofs,
                delegateProof
            );
        }
    }

    /**
     * @notice Generates an array of ownership proofs for multiple token IDs
     * @dev This function creates state proof parameters for each token ID using the base parameters and storage proofs
     * @param baseProofParams The base state proof parameters common to all proofs
     * @param ownershipStorageProofs A 2D array of storage proofs, where each inner array corresponds to a token ID
     * @return An array of IStateProof.Parameters, one for each token ID
     */
    function _generateOwnershipProofs(
        IStateProof.BaseParameters memory baseProofParams,
        bytes[][] memory ownershipStorageProofs
    ) internal pure returns (IStateProof.Parameters[] memory) {
        uint256 tokenIdCount = ownershipStorageProofs.length;
        IStateProof.Parameters[] memory ownershipProofs = new IStateProof.Parameters[](tokenIdCount);

        for (uint256 j = 0; j < tokenIdCount; j++) {
            // there is one storage proof for each tokenId
            ownershipProofs[j] = _generateStateProofParams(baseProofParams, ownershipStorageProofs[j]);
        }

        return ownershipProofs;
    }

    /**
     * @notice Generates StateProofParameters from base parameters and storage proof
     * @param baseProofParams The base state proof parameters
     * @param storageProof The storage proof for the specific state
     * @return IStateProof.Parameters The generated state proof parameters
     */
    function _generateStateProofParams(
        IStateProof.BaseParameters memory baseProofParams,
        bytes[] memory storageProof
    ) internal pure returns (IStateProof.Parameters memory) {
        return
            IStateProof.Parameters({
                beaconRoot: baseProofParams.beaconRoot,
                beaconOracleTimestamp: baseProofParams.beaconOracleTimestamp,
                executionStateRoot: baseProofParams.executionStateRoot,
                stateRootProof: baseProofParams.stateRootProof,
                accountProof: baseProofParams.accountProof,
                storageProof: storageProof
            });
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
        IStateProof.Parameters[] memory ownershipProofs,
        IStateProof.Parameters memory delegateProof
    ) internal {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (!verifier.canVoteWithToken(tokenIds[i], owner, msg.sender, ownershipProofs[i], delegateProof))
                revert NOT_ABLE_TO_VOTE_WITH_TOKEN();
            _setVotesAllocationForTokenId(tokenIds[i], recipientIds, percentAllocations);
        }
    }

    /**
     * @notice Deploys a new Flow contract as a recipient
     * @dev This function overrides the base _deployFlowRecipient to use NounsFlow-specific initialization
     * @param metadata The recipient's metadata like title, description, etc.
     * @param flowManager The address of the flow manager for the new contract
     * @return address The address of the newly created Flow contract
     */
    function _deployFlowRecipient(
        RecipientMetadata memory metadata,
        address flowManager
    ) internal override returns (address) {
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
