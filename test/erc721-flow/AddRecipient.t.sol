// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {IFlowEvents,IFlow} from "../../src/interfaces/IFlow.sol";
import {Flow} from "../../src/Flow.sol";
import {FlowStorageV1} from "../../src/storage/FlowStorageV1.sol";
import {ERC721FlowTest} from "./ERC721Flow.t.sol";

contract AddRecipientsTest is ERC721FlowTest {

    function setUp() override public {
        super.setUp();
    }

    function testAddRecipient() public {
        address recipient = address(0x123);
        // Test successful addition of a recipient
        vm.startPrank(flow.owner());
        vm.expectEmit(true, true, true, true);
        emit IFlowEvents.RecipientCreated(0, FlowStorageV1.FlowRecipient({
            recipientType: FlowStorageV1.RecipientType.ExternalAccount,
            removed: false,
            recipient: recipient,
            metadata: recipientMetadata
        }), flow.owner());
        flow.addRecipient(recipient, recipientMetadata);

        // Verify recipient was added correctly
        (address storedRecipient, bool removed, FlowStorageV1.RecipientType recipientType, FlowStorageV1.RecipientMetadata memory storedMetadata) = flow.recipients(0);
        assertEq(storedRecipient, recipient);
        assertEq(removed, false);
        assertEq(uint8(recipientType), uint8(FlowStorageV1.RecipientType.ExternalAccount));
        assertEq(storedMetadata.title, recipientMetadata.title);
        assertEq(storedMetadata.description, recipientMetadata.description);
        assertEq(storedMetadata.image, recipientMetadata.image);
        assertEq(flow.recipientExists(recipient), true);

        // Verify recipient count increased
        assertEq(flow.recipientCount(), 1);
    }

    function testAddRecipientZeroAddress() public {
        // Test adding a zero address recipient (should revert)
        vm.prank(flow.owner());
        vm.expectRevert(IFlow.ADDRESS_ZERO.selector);
        flow.addRecipient(address(0), recipientMetadata);
    }

    function testAddRecipientEmptyMetadata() public {
        address recipient = address(0x123);

        // Test adding a recipient with empty metadata (should revert)
        vm.prank(flow.owner());
        vm.expectRevert(IFlow.INVALID_METADATA.selector);
        flow.addRecipient(recipient, FlowStorageV1.RecipientMetadata("", "", "", "", ""));
    }
    
    function testAddRecipientNonManager() public {
        address recipient = address(0x123);

        // Test adding a recipient from a non-manager address (should revert)
        vm.prank(address(0xABC));
        vm.expectRevert(IFlow.SENDER_NOT_MANAGER.selector);
        flow.addRecipient(recipient, recipientMetadata);
    }

    function testAddMultipleRecipients() public {
        address recipient1 = address(0x123);
        address recipient2 = address(0x456);
        FlowStorageV1.RecipientMetadata memory metadata1 = FlowStorageV1.RecipientMetadata("Recipient 1", "Description 1", "ipfs://image1", "Tagline 1", "https://recipient1.com");
        FlowStorageV1.RecipientMetadata memory metadata2 = FlowStorageV1.RecipientMetadata("Recipient 2", "Description 2", "ipfs://image2", "Tagline 2", "https://recipient2.com");

        // Add first recipient
        vm.prank(flow.owner());
        flow.addRecipient(recipient1, metadata1);

        // Add second recipient
        vm.prank(flow.owner());
        flow.addRecipient(recipient2, metadata2);

        // Verify both recipients were added correctly
        assertEq(flow.recipientCount(), 2);

        (address storedRecipient1, , , FlowStorageV1.RecipientMetadata memory storedMetadata1) = flow.recipients(0);
        (address storedRecipient2, , , FlowStorageV1.RecipientMetadata memory storedMetadata2) = flow.recipients(1);

        assertEq(storedRecipient1, recipient1);
        assertEq(storedRecipient2, recipient2);
        assertEq(storedMetadata1.title, metadata1.title);
        assertEq(storedMetadata2.title, metadata2.title);
    }

    function testBaselineMemberUnitsAfterAddingRecipients() public {
        address externalRecipient = address(0x123);
        FlowStorageV1.RecipientMetadata memory externalMetadata = FlowStorageV1.RecipientMetadata("External Recipient", "Description", "ipfs://image1", "External Tagline", "https://external.com");

        // Add external recipient
        vm.prank(flow.owner());
        flow.addRecipient(externalRecipient, externalMetadata);

        // Add flow recipient
        vm.prank(flow.owner());
        address flowRecipient = flow.addFlowRecipient(
            FlowStorageV1.RecipientMetadata("Flow Recipient", "Description", "ipfs://image2", "Flow Tagline", "https://flow.com"),
            address(0x456) // flowManager address
        );

        // Check baseline member units for external recipient
        uint128 externalRecipientUnits = flow.baselinePool().getUnits(externalRecipient);
        assertEq(externalRecipientUnits, flow.BASELINE_MEMBER_UNITS(), "External recipient should have baseline member units");

        // Check baseline member units for flow recipient
        uint128 flowRecipientUnits = flow.baselinePool().getUnits(flowRecipient);
        assertEq(flowRecipientUnits, flow.BASELINE_MEMBER_UNITS(), "Flow recipient should have baseline member units");

        // Verify total units in baseline pool
        uint128 totalUnits = flow.baselinePool().getTotalUnits();
        assertEq(totalUnits, flow.BASELINE_MEMBER_UNITS() * 2 + 1, "Total units should be 2 * BASELINE_MEMBER_UNITS + 1 (for address(this))");
    }

    function testAddDuplicateRecipient() public {
        address recipient = address(0x123);
        FlowStorageV1.RecipientMetadata memory metadata = FlowStorageV1.RecipientMetadata({
            title: "Recipient",
            description: "Description",
            image: "ipfs://image",
            tagline: "Test Tagline",
            url: "https://example.com"
        });

        // Add recipient for the first time
        vm.prank(flow.owner());
        flow.addRecipient(recipient, metadata);

        // Attempt to add the same recipient again
        vm.prank(flow.owner());
        vm.expectRevert(IFlow.RECIPIENT_ALREADY_EXISTS.selector);
        flow.addRecipient(recipient, metadata);

        // Verify recipient count hasn't changed
        assertEq(flow.recipientCount(), 1, "Recipient count should still be 1");
    }
}
