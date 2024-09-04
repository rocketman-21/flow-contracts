// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

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
        vm.startPrank(manager);
        flow.addRecipient(recipient, recipientMetadata);
        flow.addRecipient(recipient2, recipientMetadata);
        vm.stopPrank();

        uint256[] memory recipientIds =  new uint256[](1);
        uint32[] memory percentAllocations = new uint32[](1);
        uint256[] memory tokenIds = new uint256[](1);

        percentAllocations[0] = 1e6;
        tokenIds[0] = tokenId;
        recipientIds[0] = 0;

        vm.prank(voter1);
        flow.castVotes(tokenIds, recipientIds, percentAllocations);

        // get current member units of the pool
        uint128 currentUnits = flow.bonusPool().getUnits(recipient);

        assertGt(currentUnits, 0);

        recipientIds[0] = 1;

        vm.prank(voter1);
        flow.castVotes(tokenIds, recipientIds, percentAllocations);

        uint128 recipient2Units = flow.bonusPool().getUnits(recipient2);

        assertGt(recipient2Units, 0);

        assertEq(flow.bonusPool().getUnits(recipient), 0);
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
        vm.startPrank(manager);
        flow.addRecipient(recipient, recipientMetadata);
        flow.addRecipient(recipient2, recipientMetadata);
        vm.stopPrank();

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
        uint128 originalUnits = flow.bonusPool().getUnits(recipient);

        assertGt(originalUnits, 0);

        vm.prank(voter1);
        flow.castVotes(tokenIds, recipientIds, percentAllocations);

        uint128 secondVoteUnits = flow.bonusPool().getUnits(recipient);

        assertGt(secondVoteUnits, originalUnits);

        uint256[] memory newRecipientIds =  new uint256[](1);
        newRecipientIds[0] = 1;

        vm.prank(voter1);
        flow.castVotes(tokenIds, newRecipientIds, percentAllocations);

        uint128 recipient2Units = flow.bonusPool().getUnits(recipient2);
        assertGt(recipient2Units, 0);

        assertEq(flow.bonusPool().getUnits(recipient), originalUnits);
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
        vm.startPrank(manager);
        flow.addRecipient(recipient1, recipientMetadata);
        flow.addRecipient(recipient2, recipientMetadata);
        vm.stopPrank();

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
        vm.startPrank(manager);
        flow.addRecipient(recipient1, recipientMetadata);
        flow.addRecipient(recipient2, recipientMetadata);
        vm.stopPrank();

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

        uint128 recipient1OriginalUnits = flow.bonusPool().getUnits(recipient1);
        uint128 recipient2OriginalUnits = flow.bonusPool().getUnits(recipient2);

        assertGt(recipient1OriginalUnits, 0);
        assertGt(recipient2OriginalUnits, 0);

        // Change vote to only recipient1
        recipientIds = new uint256[](1);
        percentAllocations = new uint32[](1);
        recipientIds[0] = 0;
        percentAllocations[0] = 1e6; // 100%

        vm.prank(voter);
        flow.castVotes(tokenIds, recipientIds, percentAllocations);

        uint128 recipient1NewUnits = flow.bonusPool().getUnits(recipient1);
        uint128 recipient2NewUnits = flow.bonusPool().getUnits(recipient2);

        assertGt(recipient1NewUnits, recipient1OriginalUnits);
        assertEq(recipient2NewUnits, 0);

        // Verify that the votes for the tokenId have been updated
        Flow.VoteAllocation[] memory voteAllocations = flow.getVotesForTokenId(tokenId);
        assertEq(voteAllocations.length, 1);
        assertEq(voteAllocations[0].recipientId, 0);
        assertEq(voteAllocations[0].bps, 1e6);
    }

    function test__FlowRecipientFlowRateChanges() public {
        address voter = address(1);
        uint256 tokenId = 0;

        nounsToken.mint(voter, tokenId);

        address recipient1 = address(3);
        address flowRecipient = address(0);
        vm.startPrank(manager);
        flow.addRecipient(recipient1, recipientMetadata);
        flowRecipient = flow.addFlowRecipient(recipientMetadata, manager);
        vm.stopPrank();

        uint256[] memory recipientIds = new uint256[](1);
        uint32[] memory percentAllocations = new uint32[](1);
        uint256[] memory tokenIds = new uint256[](1);

        recipientIds[0] = 1; // Flow recipient
        percentAllocations[0] = 1e6; // 100%
        tokenIds[0] = tokenId;

        // // ensure small balance - need to be able to set flow rate
        _transferTestTokenToFlow(flowRecipient, 56 * 10**18);

        vm.prank(voter);
        flow.castVotes(tokenIds, recipientIds, percentAllocations);

        // Check that the flow rate for the flow recipient has changed
        int96 flowRecipientFlowRate = Flow(flowRecipient).getNetFlowRate();
        assertEq(flowRecipientFlowRate, 0);

        int96 flowRecipientTotalFlowRate = Flow(flowRecipient).getTotalFlowRate();
        assertGt(flowRecipientTotalFlowRate, 0);

        // Change vote to recipient1
        recipientIds[0] = 0;
        percentAllocations[0] = 1e6; // 100%

        vm.prank(voter);
        flow.castVotes(tokenIds, recipientIds, percentAllocations);

        // Check that total bonus salary flow rate to the flow recipient is 0
        int96 newFlowRecipientTotalFlowRate = flow.bonusPool().getMemberFlowRate(flowRecipient);
        assertEq(newFlowRecipientTotalFlowRate, 0);

        // Check that the member units on the bonus pool for the flow recipient are 0
        uint128 flowRecipientBonusUnits = flow.bonusPool().getUnits(flowRecipient);
        assertEq(flowRecipientBonusUnits, 0);

        // Check that the baseline pool units for the flow recipient are unchanged
        uint128 flowRecipientBaselineUnits = flow.baselinePool().getUnits(flowRecipient);
        assertEq(flowRecipientBaselineUnits, flow.BASELINE_MEMBER_UNITS());

        // Check that the baseline pool units for recipient1 are unchanged
        uint128 recipient1BaselineUnits = flow.baselinePool().getUnits(recipient1);
        assertEq(recipient1BaselineUnits, flow.BASELINE_MEMBER_UNITS());

        // Check that recipient1 now has units
        uint128 recipient1Units = flow.bonusPool().getUnits(recipient1);
        assertGt(recipient1Units, 0);
    }

    function test__FlowRecipientFlowRateBufferAmount() public {
        address voter = address(1);
        uint256 tokenId = 0;

        nounsToken.mint(voter, tokenId);

        address recipient1 = address(3);
        address flowRecipient = address(0);
        vm.startPrank(manager);
        flow.addRecipient(recipient1, recipientMetadata);
        flowRecipient = flow.addFlowRecipient(recipientMetadata, manager);
        vm.stopPrank();

        uint256[] memory recipientIds = new uint256[](1);
        uint32[] memory percentAllocations = new uint32[](1);
        uint256[] memory tokenIds = new uint256[](1);

        recipientIds[0] = 1; // Flow recipient
        percentAllocations[0] = 1e6; // 100%
        tokenIds[0] = tokenId;

        vm.prank(voter);
        flow.castVotes(tokenIds, recipientIds, percentAllocations);

        // Check that the flow rate for the flow recipient has changed
        int96 flowRecipientFlowRate = Flow(flowRecipient).getNetFlowRate();
        assertGt(flowRecipientFlowRate, 0);

        // the total flow rate should be 0 because the recipient does not have the buffer amount yet
        int96 flowRecipientTotalFlowRate = Flow(flowRecipient).getTotalFlowRate();
        assertEq(flowRecipientTotalFlowRate, 0);

        // transfer tokens to flow recipient
        _transferTestTokenToFlow(flowRecipient, 100 * 10**18);

        // vote again check total flow rate is now gt 0
        vm.prank(voter);
        flow.castVotes(tokenIds, recipientIds, percentAllocations);

        int96 newFlowRecipientTotalFlowRate = Flow(flowRecipient).getTotalFlowRate();
        assertGt(newFlowRecipientTotalFlowRate, 0);
    }

}