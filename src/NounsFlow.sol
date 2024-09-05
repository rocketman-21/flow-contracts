// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {Flow} from "./Flow.sol";
import {FlowStorageV1} from "./storage/FlowStorageV1.sol";
import {IFlow, INounsFlow} from "./interfaces/IFlow.sol";
import {IL2NounsVerifier} from "./interfaces/IL2NounsVerifier.sol";
import {StateVerifier} from "./state-proof/StateVerifier.sol";

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import {ISuperfluidPool} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/gdav1/ISuperfluidPool.sol";
import {SuperTokenV1Library} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";

contract NounsFlow is INounsFlow, Flow {
    IL2NounsVerifier public verifier;

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
     * @notice Cast a vote for a set of grant addresses.
     * @param tokenIds The tokenIds that the voter is using to vote.
     * @param recipientIds The recpientIds of the grant recipients.
     * @param percentAllocations The basis points of the vote to be split with the recipients.
     */
    function castVotes(uint256[] memory tokenIds, uint256[] memory recipientIds, uint32[] memory percentAllocations, address[] calldata owners, StateVerifier.StateProofParameters[] calldata ownershipProofs, StateVerifier.StateProofParameters[] calldata delegateProofs)
        external
        nonReentrant
        validVotes(recipientIds, percentAllocations)
    {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (!verifier.canVoteWithToken(tokenIds[i], owners[i], msg.sender, ownershipProofs[i], delegateProofs[i])) revert NOT_ABLE_TO_VOTE_WITH_TOKEN();
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
