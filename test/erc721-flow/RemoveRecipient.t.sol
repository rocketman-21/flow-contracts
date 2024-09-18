// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import { ERC721FlowTest } from "./ERC721Flow.t.sol";
import { IFlowEvents, IFlow } from "../../src/interfaces/IFlow.sol";
import { FlowStorageV1 } from "../../src/storage/FlowStorageV1.sol";

contract RemoveRecipientsTest is ERC721FlowTest {
    function setUp() public override {
        super.setUp();
    }

    function testRemoveRecipient() public {
        address recipient = address(0x123);

        // Add a recipient first
        vm.prank(flow.owner());
        (bytes32 recipientId, address recipientAddress) = flow.addRecipient(recipient, recipientMetadata);

        // Test successful removal of a recipient
        vm.startPrank(flow.owner());
        vm.expectEmit(true, true, true, true);
        emit IFlowEvents.RecipientRemoved(recipientAddress, recipientId);
        flow.removeRecipient(recipientId);

        // Verify recipient was removed correctly
        (address storedRecipient, bool removed, , ) = flow.recipients(recipientId);
        assertEq(storedRecipient, recipient);
        assertEq(removed, true);
        assertEq(flow.recipientExists(recipient), false);

        // Verify recipient count remains the same
        assertEq(flow.activeRecipientCount(), 0);
    }

    function testRemoveRecipientInvalidId() public {
        address recipient = address(0x123);

        // Add a recipient first
        vm.prank(flow.owner());
        (bytes32 recipientId, address recipientAddress) = flow.addRecipient(recipient, recipientMetadata);

        // Test removing a recipient with an invalid ID (should revert)
        vm.prank(flow.owner());
        vm.expectRevert(IFlow.INVALID_RECIPIENT_ID.selector);
        flow.removeRecipient(bytes32(uint256(1))); // Using ID 1, which is invalid as we only added one recipient (ID 0)

        // Verify that the valid recipient (ID 0) still exists and is not removed
        (address storedRecipient, bool removed, , ) = flow.recipients(recipientId);
        assertEq(storedRecipient, recipient);
        assertEq(removed, false);
    }

    function testRemoveRecipientAlreadyRemoved() public {
        address recipient = address(0x123);

        // Add a recipient
        vm.prank(flow.owner());
        (bytes32 recipientId, ) = flow.addRecipient(recipient, recipientMetadata);

        // Remove the recipient
        vm.prank(flow.owner());
        flow.removeRecipient(recipientId);

        // Try to remove the same recipient again (should revert)
        vm.prank(flow.owner());
        vm.expectRevert(IFlow.RECIPIENT_ALREADY_REMOVED.selector);
        flow.removeRecipient(recipientId);
    }

    function testRemoveRecipientNonManager() public {
        address recipient = address(0x123);

        // Add a recipient
        vm.prank(flow.owner());
        (bytes32 recipientId, ) = flow.addRecipient(recipient, recipientMetadata);

        // Test removing a recipient from a non-manager address (should revert)
        vm.prank(address(0xABC));
        vm.expectRevert(IFlow.SENDER_NOT_MANAGER.selector);
        flow.removeRecipient(recipientId);
    }
    function testRemoveMultipleRecipients() public {
        address recipient1 = address(0x123);
        address recipient2 = address(0x456);
        FlowStorageV1.RecipientMetadata memory metadata1 = FlowStorageV1.RecipientMetadata(
            "Recipient 1",
            "Description 1",
            "ipfs://image1",
            "Tagline 1",
            "https://recipient1.com"
        );
        FlowStorageV1.RecipientMetadata memory metadata2 = FlowStorageV1.RecipientMetadata(
            "Recipient 2",
            "Description 2",
            "ipfs://image2",
            "Tagline 2",
            "https://recipient2.com"
        );

        // Add recipients
        vm.startPrank(flow.owner());
        (bytes32 recipientId1, ) = flow.addRecipient(recipient1, metadata1);
        (bytes32 recipientId2, ) = flow.addRecipient(recipient2, metadata2);

        // Remove first recipient
        flow.removeRecipient(recipientId1);

        // Verify first recipient was removed
        (address storedRecipient1, bool removed1, , ) = flow.recipients(recipientId1);
        assertEq(storedRecipient1, recipient1);
        assertEq(removed1, true);

        // Remove second recipient
        flow.removeRecipient(recipientId2);

        // Verify second recipient was removed
        (address storedRecipient2, bool removed2, , ) = flow.recipients(recipientId2);
        assertEq(storedRecipient2, recipient2);
        assertEq(removed2, true);

        // Verify recipient count remains the same
        assertEq(flow.activeRecipientCount(), 0);
    }

    function testRemoveRecipientUpdateMemberUnits() public {
        address recipient = address(0x123);

        // Add a recipient
        vm.prank(flow.owner());
        (bytes32 recipientId, ) = flow.addRecipient(recipient, recipientMetadata);

        // Cast a vote to give the recipient some member units
        uint256 tokenId = 0;
        bytes32[] memory recipientIds = new bytes32[](1);
        recipientIds[0] = recipientId;
        uint32[] memory percentAllocations = new uint32[](1);
        percentAllocations[0] = 1e6; // 100%
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        vm.prank(address(this));
        nounsToken.mint(address(this), tokenId);

        vm.prank(address(this));
        flow.castVotes(tokenIds, recipientIds, percentAllocations);

        // Check initial member units
        uint128 initialUnits = flow.bonusPool().getUnits(recipient);
        assertGt(initialUnits, 0);

        // Remove the recipient
        vm.prank(flow.owner());
        flow.removeRecipient(recipientId);

        // Check that member units have been updated (should be 0)
        uint128 finalUnits = flow.bonusPool().getUnits(recipient);
        assertEq(finalUnits, 0);
    }

    function testRemoveRecipientAndVoteAgain() public {
        address recipient = address(0x123);

        // Add a recipient
        vm.prank(flow.owner());
        (bytes32 recipientId, ) = flow.addRecipient(recipient, recipientMetadata);

        // Remove the recipient
        vm.prank(flow.owner());
        flow.removeRecipient(recipientId);

        // Attempt to vote for the removed recipient
        uint256 tokenId = 0;
        bytes32[] memory recipientIds = new bytes32[](1);
        recipientIds[0] = recipientId;
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
        uint128 finalUnits = flow.bonusPool().getUnits(recipient);
        assertEq(finalUnits, 0);
    }

    function testVoteAfterRemovingRecipient() public {
        address recipient1 = address(0x123);
        address recipient2 = address(0x456);

        // Add two recipients
        vm.startPrank(flow.owner());
        (bytes32 recipientId1, ) = flow.addRecipient(recipient1, recipientMetadata);
        (bytes32 recipientId2, ) = flow.addRecipient(recipient2, recipientMetadata);
        vm.stopPrank();

        // Mint a token for voting
        uint256 tokenId = 0;
        vm.prank(address(this));
        nounsToken.mint(address(this), tokenId);

        // Vote for the first recipient
        bytes32[] memory recipientIds = new bytes32[](1);
        recipientIds[0] = recipientId1;
        uint32[] memory percentAllocations = new uint32[](1);
        percentAllocations[0] = 1e6; // 100%
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = tokenId;

        flow.castVotes(tokenIds, recipientIds, percentAllocations);

        // Verify the vote was cast
        FlowStorageV1.VoteAllocation[] memory votes = flow.getVotesForTokenId(tokenId);
        assertEq(votes.length, 1);
        assertEq(votes[0].recipientId, recipientId1);
        assertEq(votes[0].bps, 1e6);

        // Remove the first recipient
        vm.prank(flow.owner());
        flow.removeRecipient(recipientId1);

        // Vote for the second recipient
        recipientIds[0] = recipientId2;
        flow.castVotes(tokenIds, recipientIds, percentAllocations);

        // Verify the new vote was cast
        votes = flow.getVotesForTokenId(tokenId);
        assertEq(votes.length, 1);
        assertEq(votes[0].recipientId, recipientId2);
        assertEq(votes[0].bps, 1e6);

        // Verify member units
        uint128 units1 = flow.bonusPool().getUnits(recipient1);
        uint128 units2 = flow.bonusPool().getUnits(recipient2);
        assertEq(units1, 0);
        assertGt(units2, 0);
    }

    function testRemoveRecipientBaselineMemberUnits() public {
        address recipient1 = address(0x123);
        address recipient2 = address(0x456);
        FlowStorageV1.RecipientMetadata memory metadata1 = FlowStorageV1.RecipientMetadata(
            "Recipient 1",
            "Description 1",
            "ipfs://image1",
            "Tagline 1",
            "https://recipient1.com"
        );
        FlowStorageV1.RecipientMetadata memory metadata2 = FlowStorageV1.RecipientMetadata(
            "Recipient 2",
            "Description 2",
            "ipfs://image2",
            "Tagline 2",
            "https://recipient2.com"
        );

        // Add recipients
        vm.prank(flow.owner());
        (bytes32 recipientId1, ) = flow.addRecipient(recipient1, metadata1);
        vm.prank(flow.owner());
        (bytes32 recipientId2, ) = flow.addRecipient(recipient2, metadata2);

        // Check initial state
        uint128 initialTotalUnits = flow.baselinePool().getTotalUnits();
        assertEq(initialTotalUnits, flow.BASELINE_MEMBER_UNITS() * 2 + 1, "Initial total units incorrect");

        // Remove first recipient
        vm.prank(flow.owner());
        flow.removeRecipient(recipientId1);

        // Check units after removing first recipient
        uint128 unitsAfterRemove1 = flow.baselinePool().getTotalUnits();
        assertEq(
            unitsAfterRemove1,
            flow.BASELINE_MEMBER_UNITS() + 1,
            "Total units incorrect after removing first recipient"
        );
        assertEq(flow.baselinePool().getUnits(recipient1), 0, "Removed recipient should have 0 units");
        assertEq(
            flow.baselinePool().getUnits(recipient2),
            flow.BASELINE_MEMBER_UNITS(),
            "Remaining recipient should keep units"
        );

        // Try to remove the same recipient again (should not change anything)
        vm.prank(flow.owner());
        vm.expectRevert(IFlow.RECIPIENT_ALREADY_REMOVED.selector);
        flow.removeRecipient(recipientId1);
        assertEq(
            flow.baselinePool().getTotalUnits(),
            unitsAfterRemove1,
            "Total units should not change when removing already removed recipient"
        );

        // Remove second recipient
        vm.prank(flow.owner());
        flow.removeRecipient(recipientId2);

        // Check final state
        uint128 finalTotalUnits = flow.baselinePool().getTotalUnits();
        assertEq(finalTotalUnits, 1, "Final total units should be 1 (for address(this))");
        assertEq(flow.baselinePool().getUnits(recipient2), 0, "Second removed recipient should have 0 units");

        // Try to remove non-existent recipient (should revert)
        vm.prank(flow.owner());
        vm.expectRevert();
        flow.removeRecipient(bytes32(uint256(2)));

        // Add a new recipient and verify units are assigned correctly
        address recipient3 = address(0x789);
        FlowStorageV1.RecipientMetadata memory metadata3 = FlowStorageV1.RecipientMetadata(
            "Recipient 3",
            "Description 3",
            "ipfs://image3",
            "Tagline 3",
            "https://recipient3.com"
        );
        vm.prank(flow.owner());
        (bytes32 recipientId3, ) = flow.addRecipient(recipient3, metadata3);

        assertEq(
            flow.baselinePool().getTotalUnits(),
            flow.BASELINE_MEMBER_UNITS() + 1,
            "Total units incorrect after adding new recipient"
        );
        assertEq(
            flow.baselinePool().getUnits(recipient3),
            flow.BASELINE_MEMBER_UNITS(),
            "New recipient should have baseline member units"
        );
    }

    function testRemoveFlowRecipient() public {
        address flowManager1 = address(0x123);
        address flowManager2 = address(0x456);
        FlowStorageV1.RecipientMetadata memory metadata1 = FlowStorageV1.RecipientMetadata(
            "Flow Recipient 1",
            "Description 1",
            "ipfs://image1",
            "Tagline 1",
            "https://flowrecipient1.com"
        );
        FlowStorageV1.RecipientMetadata memory metadata2 = FlowStorageV1.RecipientMetadata(
            "Flow Recipient 2",
            "Description 2",
            "ipfs://image2",
            "Tagline 2",
            "https://flowrecipient2.com"
        );

        // Add flow recipients
        vm.startPrank(flow.owner());
        (bytes32 recipientId1, address flowRecipient1) = flow.addFlowRecipient(metadata1, flowManager1);
        (bytes32 recipientId2, address flowRecipient2) = flow.addFlowRecipient(metadata2, flowManager2);
        vm.stopPrank();

        // Check initial state
        uint128 initialTotalUnits = flow.baselinePool().getTotalUnits();
        assertEq(initialTotalUnits, flow.BASELINE_MEMBER_UNITS() * 2 + 1, "Initial total units incorrect");

        // Remove first flow recipient
        vm.prank(flow.owner());
        flow.removeRecipient(recipientId1);

        // Check units after removing first recipient
        uint128 unitsAfterRemove1 = flow.baselinePool().getTotalUnits();
        assertEq(
            unitsAfterRemove1,
            flow.BASELINE_MEMBER_UNITS() + 1,
            "Total units incorrect after removing first recipient"
        );
        assertEq(flow.baselinePool().getUnits(flowRecipient1), 0, "Removed recipient should have 0 units");
        assertEq(
            flow.baselinePool().getUnits(flowRecipient2),
            flow.BASELINE_MEMBER_UNITS(),
            "Remaining recipient should keep units"
        );

        // Try to remove the same recipient again (should not change anything)
        vm.prank(flow.owner());
        vm.expectRevert(IFlow.RECIPIENT_ALREADY_REMOVED.selector);
        flow.removeRecipient(recipientId1);
        assertEq(
            flow.baselinePool().getTotalUnits(),
            unitsAfterRemove1,
            "Total units should not change when removing already removed recipient"
        );

        // Remove second flow recipient
        vm.prank(flow.owner());
        flow.removeRecipient(recipientId2);

        // Check final state
        uint128 finalTotalUnits = flow.baselinePool().getTotalUnits();
        assertEq(finalTotalUnits, 1, "Final total units should be 1 (for address(this))");
        assertEq(flow.baselinePool().getUnits(flowRecipient2), 0, "Second removed recipient should have 0 units");

        // Try to remove non-existent recipient (should revert)
        vm.prank(flow.owner());
        vm.expectRevert();
        flow.removeRecipient(bytes32(uint256(2)));

        // Add a new flow recipient and verify units are assigned correctly
        address flowManager3 = address(0x789);
        FlowStorageV1.RecipientMetadata memory metadata3 = FlowStorageV1.RecipientMetadata(
            "Flow Recipient 3",
            "Description 3",
            "ipfs://image3",
            "Tagline 3",
            "https://flowrecipient3.com"
        );
        vm.prank(flow.owner());
        (bytes32 recipientId3, address flowRecipient3) = flow.addFlowRecipient(metadata3, flowManager3);

        assertEq(
            flow.baselinePool().getTotalUnits(),
            flow.BASELINE_MEMBER_UNITS() + 1,
            "Total units incorrect after adding new recipient"
        );
        assertEq(
            flow.baselinePool().getUnits(flowRecipient3),
            flow.BASELINE_MEMBER_UNITS(),
            "New recipient should have baseline member units"
        );
    }
}
