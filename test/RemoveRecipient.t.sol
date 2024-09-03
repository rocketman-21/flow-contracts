// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {FlowTest} from "./Flow.t.sol";
import {IFlowEvents,IFlow} from "../src/interfaces/IFlow.sol";
import {Flow} from "../src/Flow.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FlowStorageV1} from "../src/storage/FlowStorageV1.sol";

contract RemoveRecipientsTest is FlowTest {

    function setUp() override public {
        super.setUp();
    }

    function testRemoveRecipient() public {
        address recipient = address(0x123);
        

        // Add a recipient first
        vm.prank(flow.owner());
        flow.addRecipient(recipient, recipientMetadata);

        // Test successful removal of a recipient
        vm.startPrank(flow.owner());
        vm.expectEmit(true, true, true, true);
        emit IFlowEvents.RecipientRemoved(recipient, 0);
        flow.removeRecipient(0);

        // Verify recipient was removed correctly
        (address storedRecipient, bool removed, , ) = flow.recipients(0);
        assertEq(storedRecipient, recipient);
        assertEq(removed, true);

        // Verify recipient count remains the same
        assertEq(flow.recipientCount(), 1);
    }

    function testRemoveRecipientInvalidId() public {
        address recipient = address(0x123);
        

        // Add a recipient first
        vm.prank(flow.owner());
        flow.addRecipient(recipient, recipientMetadata);

        // Test removing a recipient with an invalid ID (should revert)
        vm.prank(flow.owner());
        vm.expectRevert(IFlow.INVALID_RECIPIENT_ID.selector);
        flow.removeRecipient(1); // Using ID 1, which is invalid as we only added one recipient (ID 0)

        // Verify that the valid recipient (ID 0) still exists and is not removed
        (address storedRecipient, bool removed, , ) = flow.recipients(0);
        assertEq(storedRecipient, recipient);
        assertEq(removed, false);
    }

    function testRemoveRecipientAlreadyRemoved() public {
        address recipient = address(0x123);
        

        // Add a recipient
        vm.prank(flow.owner());
        flow.addRecipient(recipient, recipientMetadata);

        // Remove the recipient
        vm.prank(flow.owner());
        flow.removeRecipient(0);

        // Try to remove the same recipient again (should revert)
        vm.prank(flow.owner());
        vm.expectRevert(IFlow.RECIPIENT_ALREADY_REMOVED.selector);
        flow.removeRecipient(0);
    }

    function testRemoveRecipientNonManager() public {
        address recipient = address(0x123);
        

        // Add a recipient
        vm.prank(flow.owner());
        flow.addRecipient(recipient, recipientMetadata);

        // Test removing a recipient from a non-manager address (should revert)
        vm.prank(address(0xABC));
        vm.expectRevert(IFlow.SENDER_NOT_MANAGER.selector);
        flow.removeRecipient(0);
    }
    function testRemoveMultipleRecipients() public {
        address recipient1 = address(0x123);
        address recipient2 = address(0x456);
        FlowStorageV1.RecipientMetadata memory metadata1 = FlowStorageV1.RecipientMetadata("Recipient 1", "Description 1", "ipfs://image1");
        FlowStorageV1.RecipientMetadata memory metadata2 = FlowStorageV1.RecipientMetadata("Recipient 2", "Description 2", "ipfs://image2");

        // Add recipients
        vm.startPrank(flow.owner());
        flow.addRecipient(recipient1, metadata1);
        flow.addRecipient(recipient2, metadata2);

        // Remove first recipient
        flow.removeRecipient(0);

        // Verify first recipient was removed
        (address storedRecipient1, bool removed1, , ) = flow.recipients(0);
        assertEq(storedRecipient1, recipient1);
        assertEq(removed1, true);

        // Remove second recipient
        flow.removeRecipient(1);

        // Verify second recipient was removed
        (address storedRecipient2, bool removed2, , ) = flow.recipients(1);
        assertEq(storedRecipient2, recipient2);
        assertEq(removed2, true);

        // Verify recipient count remains the same
        assertEq(flow.recipientCount(), 2);
    }

    function testRemoveRecipientUpdateMemberUnits() public {
        address recipient = address(0x123);
        

        // Add a recipient
        vm.prank(flow.owner());
        flow.addRecipient(recipient, recipientMetadata);

        // Cast a vote to give the recipient some member units
        uint256 tokenId = 0;
        uint256[] memory recipientIds = new uint256[](1);
        recipientIds[0] = 0;
        uint32[] memory percentAllocations = new uint32[](1);
        percentAllocations[0] = 1e6; // 100%
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        vm.prank(address(this));
        nounsToken.mint(address(this), tokenId);

        vm.prank(address(this));
        flow.castVotes(tokenIds, recipientIds, percentAllocations);

        // Check initial member units
        uint128 initialUnits = flow.getPoolMemberUnits(recipient);
        assertGt(initialUnits, 0);

        // Remove the recipient
        vm.prank(flow.owner());
        flow.removeRecipient(0);

        // Check that member units have been updated (should be 0)
        uint128 finalUnits = flow.getPoolMemberUnits(recipient);
        assertEq(finalUnits, 0);
    }

    function testRemoveRecipientAndVoteAgain() public {
        address recipient = address(0x123);
        

        // Add a recipient
        vm.prank(flow.owner());
        flow.addRecipient(recipient, recipientMetadata);

        // Remove the recipient
        vm.prank(flow.owner());
        flow.removeRecipient(0);

        // Attempt to vote for the removed recipient
        uint256 tokenId = 0;
        uint256[] memory recipientIds = new uint256[](1);
        recipientIds[0] = 0;
        uint32[] memory percentAllocations = new uint32[](1);
        percentAllocations[0] = 1e6; // 100%
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        vm.prank(address(this));
        nounsToken.mint(address(this), tokenId);

        vm.expectRevert(IFlow.NOT_APPROVED_RECIPIENT.selector);
        flow.castVotes(tokenIds, recipientIds, percentAllocations);

        // Verify that no votes were cast
        FlowStorageV1.VoteAllocation[] memory votes = flow.getVotesForTokenId(tokenId);
        assertEq(votes.length, 0);

        // Verify that member units remain at 0
        uint128 finalUnits = flow.getPoolMemberUnits(recipient);
        assertEq(finalUnits, 0);
    }

    function testVoteAfterRemovingRecipient() public {
        address recipient1 = address(0x123);
        address recipient2 = address(0x456);
        

        // Add two recipients
        vm.startPrank(flow.owner());
        flow.addRecipient(recipient1, recipientMetadata);
        flow.addRecipient(recipient2, recipientMetadata);
        vm.stopPrank();

        // Mint a token for voting
        uint256 tokenId = 0;
        vm.prank(address(this));
        nounsToken.mint(address(this), tokenId);

        // Vote for the first recipient
        uint256[] memory recipientIds = new uint256[](1);
        recipientIds[0] = 0;
        uint32[] memory percentAllocations = new uint32[](1);
        percentAllocations[0] = 1e6; // 100%
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        flow.castVotes(tokenIds, recipientIds, percentAllocations);

        // Verify the vote was cast
        FlowStorageV1.VoteAllocation[] memory votes = flow.getVotesForTokenId(tokenId);
        assertEq(votes.length, 1);
        assertEq(votes[0].recipientId, 0);
        assertEq(votes[0].bps, 1e6);

        // Remove the first recipient
        vm.prank(flow.owner());
        flow.removeRecipient(0);

        // Vote for the second recipient
        recipientIds[0] = 1;
        flow.castVotes(tokenIds, recipientIds, percentAllocations);

        // Verify the new vote was cast
        votes = flow.getVotesForTokenId(tokenId);
        assertEq(votes.length, 1);
        assertEq(votes[0].recipientId, 1);
        assertEq(votes[0].bps, 1e6);

        // Verify member units
        uint128 units1 = flow.getPoolMemberUnits(recipient1);
        uint128 units2 = flow.getPoolMemberUnits(recipient2);
        assertEq(units1, 0);
        assertGt(units2, 0);
    }

}
