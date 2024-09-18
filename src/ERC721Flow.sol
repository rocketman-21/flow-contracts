// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import { Flow } from "./Flow.sol";
import { FlowStorageV1 } from "./storage/FlowStorageV1.sol";
import { IFlow, IERC721Flow } from "./interfaces/IFlow.sol";
import { IERC721Checkpointable } from "./interfaces/IERC721Checkpointable.sol";

import { IOwnable2Step } from "./interfaces/IOwnable2Step.sol";

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract ERC721Flow is IERC721Flow, Flow {
    // The ERC721 voting token contract used to get the voting power of an account
    IERC721Checkpointable public erc721Votes;

    constructor() payable initializer {}

    function initialize(
        address _nounsToken,
        address _superToken,
        address _flowImpl,
        address _manager,
        address _parent,
        FlowParams calldata _flowParams,
        RecipientMetadata calldata _metadata
    ) public initializer {
        if (_nounsToken == address(0)) revert ADDRESS_ZERO();

        erc721Votes = IERC721Checkpointable(_nounsToken);

        __Flow_init(_superToken, _flowImpl, _manager, _parent, _flowParams, _metadata);
    }

    /**
     * @notice Cast a vote for a set of grant addresses.
     * @param tokenIds The tokenIds that the voter is using to vote.
     * @param recipientIds The recpientIds of the grant recipients.
     * @param percentAllocations The basis points of the vote to be split with the recipients.
     */
    function castVotes(
        uint256[] calldata tokenIds,
        bytes32[] calldata recipientIds,
        uint32[] calldata percentAllocations
    ) external nonReentrant validVotes(recipientIds, percentAllocations) {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (!canVoteWithToken(tokenIds[i], msg.sender)) revert NOT_ABLE_TO_VOTE_WITH_TOKEN();
            _setVotesAllocationForTokenId(tokenIds[i], recipientIds, percentAllocations);
        }
    }

    /**
     * @notice Checks if a given address can vote with a specific token
     * @param tokenId The ID of the token to check voting rights for
     * @param voter The address of the potential voter
     * @return bool True if the voter can vote with the token, false otherwise
     */
    function canVoteWithToken(uint256 tokenId, address voter) public view returns (bool) {
        address tokenOwner = erc721Votes.ownerOf(tokenId);
        // check if the token owner has delegated their voting power to the voter
        // erc721checkpointable falls back to the owner
        // if the owner hasn't delegated so this will work for the owner as well
        address delegate = erc721Votes.delegates(tokenOwner);
        return voter == delegate;
    }

    /**
     * @notice Deploys a new Flow contract as a recipient
     * @dev This function is virtual to allow for different deployment strategies in derived contracts
     * @param metadata The recipient's metadata like title, description, etc.
     * @param flowManager The address of the flow manager for the new contract
     * @return address The address of the newly created Flow contract
     */
    function _deployFlowRecipient(
        RecipientMetadata calldata metadata,
        address flowManager
    ) internal override returns (address) {
        address recipient = address(new ERC1967Proxy(flowImpl, ""));
        if (recipient == address(0)) revert ADDRESS_ZERO();

        IERC721Flow(recipient).initialize({
            nounsToken: address(erc721Votes),
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

        IOwnable2Step(recipient).transferOwnership(owner());

        return recipient;
    }
}
