// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import { FlowTypes } from "../storage/FlowStorageV1.sol";
import { IFlow } from "../interfaces/IFlow.sol";

library FlowVotes {
    function createVote(
        FlowTypes.Storage storage fs,
        bytes32 recipientId,
        uint32 bps,
        uint256 tokenId,
        uint256 totalWeight,
        uint256 percentageScale,
        address voter
    ) public returns (uint128 memberUnits, address recipientAddress, FlowTypes.RecipientType recipientType) {
        recipientAddress = fs.recipients[recipientId].recipient;
        recipientType = fs.recipients[recipientId].recipientType;
        uint128 currentUnits = fs.bonusPool.getUnits(recipientAddress);

        // double check for overflow before casting
        // and scale back by 1e15
        // per https://docs.superfluid.finance/docs/protocol/distributions/guides/pools#about-member-units
        // gives someone with 1 vote at least 1e3 units to work with
        uint256 scaledUnits = _scaleAmountByPercentage(totalWeight, bps, percentageScale) / 1e15;
        if (scaledUnits > type(uint128).max) revert IFlow.OVERFLOW();
        uint128 newUnits = uint128(scaledUnits);

        memberUnits = currentUnits + newUnits;

        // update votes, track recipient, bps, and total member units assigned
        fs.votes[tokenId].push(FlowTypes.VoteAllocation({ recipientId: recipientId, bps: bps, memberUnits: newUnits }));
        fs.voters[tokenId] = voter;
    }

    /**
     * @notice Checks that the recipients and percentAllocations are valid
     * @param recipientIds The recipientIds of the grant recipients.
     * @param percentAllocations The basis points of the vote to be split with the recipients.
     */
    function validateVotes(
        FlowTypes.Storage storage fs,
        bytes32[] memory recipientIds,
        uint32[] memory percentAllocations
    ) public view {
        // must have recipientIds
        if (recipientIds.length < 1) {
            revert IFlow.TOO_FEW_RECIPIENTS();
        }

        // recipientIds & percentAllocations must be equal length
        if (recipientIds.length != percentAllocations.length) {
            revert IFlow.RECIPIENTS_ALLOCATIONS_MISMATCH(recipientIds.length, percentAllocations.length);
        }

        // ensure recipients are not 0 address and allocations are > 0
        for (uint256 i = 0; i < recipientIds.length; i++) {
            bytes32 recipientId = recipientIds[i];
            if (fs.recipients[recipientId].recipient == address(0)) revert IFlow.INVALID_RECIPIENT_ID();
            if (fs.recipients[recipientId].removed == true) revert IFlow.NOT_APPROVED_RECIPIENT();
            if (percentAllocations[i] == 0) revert IFlow.ALLOCATION_MUST_BE_POSITIVE();
        }
    }

    /**
     * @notice Multiplies an amount by a scaled percentage
     *  @param amount Amount to get `scaledPercentage` of
     *  @param scaledPercent Percent scaled by PERCENTAGE_SCALE
     *  @return scaledAmount Percent of `amount`.
     */
    function _scaleAmountByPercentage(
        uint256 amount,
        uint256 scaledPercent,
        uint256 percentageScale
    ) public pure returns (uint256 scaledAmount) {
        // use assembly to bypass checking for overflow & division by 0
        // scaledPercent has been validated to be < PERCENTAGE_SCALE)
        // & PERCENTAGE_SCALE will never be 0
        assembly {
            /* eg (100 * 2*1e4) / (1e6) */
            scaledAmount := div(mul(amount, scaledPercent), percentageScale)
        }
    }

    /**
     * @notice Retrieves all vote allocations for multiple ERC721 tokenIds
     * @param fs The storage of the Flow contract
     * @param tokenIds An array of tokenIds to retrieve votes for
     * @return allocations An array of arrays, where each inner array contains VoteAllocation structs for a tokenId
     */
    function getVotesForTokenIds(
        FlowTypes.Storage storage fs,
        uint256[] calldata tokenIds
    ) public view returns (FlowTypes.VoteAllocation[][] memory allocations) {
        allocations = new FlowTypes.VoteAllocation[][](tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            allocations[i] = fs.votes[tokenIds[i]];
        }
        return allocations;
    }

    /**
     * @notice Checks if a tokenId has voted before.
     * @param fs The storage of the Flow contract
     * @param tokenId The tokenId owned by the voter.
     * @param percentageScale The percentage scale to be used for the vote.
     * @param percentAllocations The basis points of the vote to be split with the recipients.
     * @return hasTokenVotedBefore - true if the tokenId has voted before, false otherwise
     */
    function checkVotesAllocationForTokenId(
        FlowTypes.Storage storage fs,
        uint256 tokenId,
        uint256 percentageScale,
        uint32[] memory percentAllocations,
        address voter
    ) public view returns (bool hasTokenVotedBefore) {
        uint256 sum = 0;
        // overflow should be impossible in for-loop index
        for (uint256 i = 0; i < percentAllocations.length; i++) {
            sum += percentAllocations[i];
        }
        if (sum != percentageScale) revert IFlow.INVALID_BPS_SUM();
        if (voter == address(0)) revert IFlow.ADDRESS_ZERO();

        // if there was a voter set for this tokenId, set hasTokenVotedBefore to true
        if (fs.voters[tokenId] != address(0)) {
            hasTokenVotedBefore = true;
        }
    }
}
