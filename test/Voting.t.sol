// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {FlowTest} from "./Flow.t.sol";
import {IFlowEvents,IFlow} from "../src/interfaces/IFlow.sol";
import {Flow} from "../src/Flow.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TestToken} from "@superfluid-finance/ethereum-contracts/contracts/utils/TestToken.sol";
import {console} from "forge-std/console.sol";

contract VotingFlowTest is FlowTest {

    function setUp() override public {
        super.setUp();
    }

    function test__RecipientVotesCleared() public {
        address voter1 = address(1);
        uint256 tokenId = 0;

        nounsToken.mint(voter1, tokenId);

        address recipient = address(3);
        address recipient2 = address(4);
        flow.addRecipient(recipient);
        flow.addRecipient(recipient2);

        uint256[] memory recipientIds =  new uint256[](1);
        uint32[] memory percentAllocations = new uint32[](1);
        uint256[] memory tokenIds = new uint256[](1);

        percentAllocations[0] = 1e6;
        tokenIds[0] = tokenId;
        recipientIds[0] = 0;

        vm.prank(voter1);
        flow.castVotes(tokenIds, recipientIds, percentAllocations);

        // get current member units of the pool
        uint128 currentUnits = flow.pool().getUnits(recipient);

        assertGt(currentUnits, 0);

        recipientIds[0] = 1;

        vm.prank(voter1);
        flow.castVotes(tokenIds, recipientIds, percentAllocations);

        uint128 recipient2Units = flow.pool().getUnits(recipient2);

        assertGt(recipient2Units, 0);

        assertEq(flow.pool().getUnits(recipient), 0);
    }

    function test__RecipientVotesCleared_MultiToken() public {
        address voter1 = address(1);
        address voter2 = address(2);
        uint256 tokenId = 0;
        uint256 tokenId2 = 1;

        nounsToken.mint(voter1, tokenId);
        nounsToken.mint(voter2, tokenId2);

        address recipient = address(3);
        address recipient2 = address(4);
        flow.addRecipient(recipient);
        flow.addRecipient(recipient2);

        uint256[] memory recipientIds =  new uint256[](1);
        uint32[] memory percentAllocations = new uint32[](1);
        uint256[] memory tokenIds = new uint256[](1);
        uint256[] memory tokenIds2 = new uint256[](1);

        percentAllocations[0] = 1e6;
        tokenIds[0] = tokenId;
        tokenIds2[0] = tokenId2;
        recipientIds[0] = 0;

        vm.prank(voter2);
        flow.castVotes(tokenIds2, recipientIds, percentAllocations);

        // get current member units of the pool
        uint128 originalUnits = flow.pool().getUnits(recipient);

        assertGt(originalUnits, 0);

        vm.prank(voter1);
        flow.castVotes(tokenIds, recipientIds, percentAllocations);

        uint128 secondVoteUnits = flow.pool().getUnits(recipient);

        assertGt(secondVoteUnits, originalUnits);

        uint256[] memory newRecipientIds =  new uint256[](1);
        newRecipientIds[0] = 1;

        vm.prank(voter1);
        flow.castVotes(tokenIds, newRecipientIds, percentAllocations);

        uint128 recipient2Units = flow.pool().getUnits(recipient2);
        assertGt(recipient2Units, 0);

        assertEq(flow.pool().getUnits(recipient), originalUnits);
    }

    function test__VoteAllocationStructForMultipleRecipients(uint32 splitPercentage) public {
        // Step 1: Ensure splitPercentage is within valid range
        splitPercentage = uint32(bound(uint256(splitPercentage), 1, 1e6 - 1));

        // Step 2: Set up test environment
        address voter = address(1);
        uint256 tokenId = 0;
        nounsToken.mint(voter, tokenId);

        address recipient1 = address(3);
        address recipient2 = address(4);
        flow.addRecipient(recipient1);
        flow.addRecipient(recipient2);

        // Step 3: Prepare vote data
        uint256[] memory recipientIds = new uint256[](2);
        uint32[] memory percentAllocations = new uint32[](2);
        uint256[] memory tokenIds = new uint256[](1);

        recipientIds[0] = 0;
        recipientIds[1] = 1;
        percentAllocations[0] = splitPercentage;
        percentAllocations[1] = 1e6 - splitPercentage;
        tokenIds[0] = tokenId;

        // Step 4: Cast votes
        vm.prank(voter);
        flow.castVotes(tokenIds, recipientIds, percentAllocations);

        // Step 5: Verify vote allocations
        Flow.VoteAllocation[] memory voteAllocations = flow.getVotesForTokenId(tokenId);

        // Check number of allocations
        assertEq(voteAllocations.length, 2);
        
        // Check first allocation
        assertEq(voteAllocations[0].recipientId, 0);
        assertEq(voteAllocations[0].bps, splitPercentage);
        assertGt(voteAllocations[0].memberUnits, 0);

        // Check second allocation
        assertEq(voteAllocations[1].recipientId, 1);
        assertEq(voteAllocations[1].bps, 1e6 - splitPercentage);
        assertGt(voteAllocations[1].memberUnits, 0);

        // Step 6: Compare member units based on split percentage
        if (splitPercentage > 5e5) {
            assertGt(voteAllocations[0].memberUnits, voteAllocations[1].memberUnits);
        } else if (splitPercentage < 5e5) {
            assertLt(voteAllocations[0].memberUnits, voteAllocations[1].memberUnits);
        } else {
            assertEq(voteAllocations[0].memberUnits, voteAllocations[1].memberUnits);
        }

        // Step 7: Ensure total member units are greater than zero
        uint256 totalMemberUnits = uint256(voteAllocations[0].memberUnits) + uint256(voteAllocations[1].memberUnits);
        assertGt(totalMemberUnits, 0);
    }

    function test__ClearVotesAllocations() public {
        address voter = address(1);
        uint256 tokenId = 0;

        nounsToken.mint(voter, tokenId);

        address recipient1 = address(3);
        address recipient2 = address(4);
        flow.addRecipient(recipient1);
        flow.addRecipient(recipient2);

        uint256[] memory recipientIds = new uint256[](2);
        uint32[] memory percentAllocations = new uint32[](2);
        uint256[] memory tokenIds = new uint256[](1);

        recipientIds[0] = 0;
        recipientIds[1] = 1;
        percentAllocations[0] = 5e5; // 50%
        percentAllocations[1] = 5e5; // 50%
        tokenIds[0] = tokenId;

        vm.prank(voter);
        flow.castVotes(tokenIds, recipientIds, percentAllocations);

        uint128 recipient1OriginalUnits = flow.pool().getUnits(recipient1);
        uint128 recipient2OriginalUnits = flow.pool().getUnits(recipient2);

        assertGt(recipient1OriginalUnits, 0);
        assertGt(recipient2OriginalUnits, 0);

        // Change vote to only recipient1
        recipientIds = new uint256[](1);
        percentAllocations = new uint32[](1);
        recipientIds[0] = 0;
        percentAllocations[0] = 1e6; // 100%

        vm.prank(voter);
        flow.castVotes(tokenIds, recipientIds, percentAllocations);

        uint128 recipient1NewUnits = flow.pool().getUnits(recipient1);
        uint128 recipient2NewUnits = flow.pool().getUnits(recipient2);

        assertGt(recipient1NewUnits, recipient1OriginalUnits);
        assertEq(recipient2NewUnits, 0);

        // Verify that the votes for the tokenId have been updated
        Flow.VoteAllocation[] memory voteAllocations = flow.getVotesForTokenId(tokenId);
        assertEq(voteAllocations.length, 1);
        assertEq(voteAllocations[0].recipientId, 0);
        assertEq(voteAllocations[0].bps, 1e6);
    }


}