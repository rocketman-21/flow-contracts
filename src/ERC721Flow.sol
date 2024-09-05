// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {Flow} from "./Flow.sol";
import {FlowStorageV1} from "./storage/FlowStorageV1.sol";
import {IFlow} from "./interfaces/IFlow.sol";
import {IERC721Checkpointable} from "./interfaces/IERC721Checkpointable.sol";

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import {ISuperfluidPool} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/gdav1/ISuperfluidPool.sol";
import {SuperTokenV1Library} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";

contract ERC721Flow is
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    ReentrancyGuardUpgradeable,
    EIP712Upgradeable,
    FlowStorageV1,
    Flow
{
    constructor() payable initializer Flow() {}

    function initialize(
        address _nounsToken,
        address _superToken,
        address _flowImpl,
        address _manager,
        address _parent,
        FlowParams memory _flowParams,
        RecipientMetadata memory _metadata
    ) public override initializer {
        __Flow_init(_nounsToken, _superToken, _flowImpl, _manager, _parent, _flowParams, _metadata);
    }

    /**
     * @notice Cast a vote for a set of grant addresses.
     * @param tokenIds The tokenIds that the voter is using to vote.
     * @param recipientIds The recpientIds of the grant recipients.
     * @param percentAllocations The basis points of the vote to be split with the recipients.
     */
    function castVotes(uint256[] memory tokenIds, uint256[] memory recipientIds, uint32[] memory percentAllocations)
        external
        override
        nonReentrant
        validVotes(recipientIds, percentAllocations)
    {
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
    function canVoteWithToken(uint256 tokenId, address voter) public view override returns (bool) {
        address tokenOwner = erc721Votes.ownerOf(tokenId);
        // check if the token owner has delegated their voting power to the voter
        // erc721checkpointable falls back to the owner 
        // if the owner hasn't delegated so this will work for the owner as well
        address delegate = erc721Votes.delegates(tokenOwner);
        return voter == delegate;
    }
}
