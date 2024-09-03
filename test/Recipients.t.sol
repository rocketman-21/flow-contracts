// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {FlowTest} from "./Flow.t.sol";
import {IFlowEvents,IFlow} from "../src/interfaces/IFlow.sol";
import {Flow} from "../src/Flow.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FlowStorageV1} from "../src/storage/FlowStorageV1.sol";

contract RecipientsTest is FlowTest {

    function setUp() override public {
        super.setUp();
    }

    function testAddRecipient() public {
        address recipient = address(0x123);
        string memory metadata = "ipfs://metadata";

        // Test successful addition of a recipient
        vm.startPrank(flow.owner());
        vm.expectEmit(true, true, true, true);
        emit IFlowEvents.RecipientCreated(recipient, flow.owner());
        flow.addRecipient(recipient, metadata);

        // Verify recipient was added correctly
        (address storedRecipient, bool removed, FlowStorageV1.RecipientType recipientType, string memory storedMetadata) = flow.recipients(0);
        assertEq(storedRecipient, recipient);
        assertEq(removed, false);
        assertEq(uint8(recipientType), uint8(FlowStorageV1.RecipientType.ExternalAccount));
        assertEq(storedMetadata, metadata);

        // Verify recipient count increased
        assertEq(flow.recipientCount(), 1);
    }

    function testAddRecipientZeroAddress() public {
        string memory metadata = "ipfs://metadata";

        // Test adding a zero address recipient (should revert)
        vm.prank(flow.owner());
        vm.expectRevert(IFlow.ADDRESS_ZERO.selector);
        flow.addRecipient(address(0), metadata);
    }

    function testAddRecipientEmptyMetadata() public {
        address recipient = address(0x123);

        // Test adding a recipient with empty metadata (should revert)
        vm.prank(flow.owner());
        vm.expectRevert(IFlow.INVALID_METADATA.selector);
        flow.addRecipient(recipient, "");
    }
    
    function testAddRecipientNonManager() public {
        address recipient = address(0x123);
        string memory metadata = "ipfs://metadata";

        // Test adding a recipient from a non-manager address (should revert)
        vm.prank(address(0xABC));
        vm.expectRevert(IFlow.SENDER_NOT_MANAGER.selector);
        flow.addRecipient(recipient, metadata);
    }

    function testAddMultipleRecipients() public {
        address recipient1 = address(0x123);
        address recipient2 = address(0x456);
        string memory metadata1 = "ipfs://metadata1";
        string memory metadata2 = "ipfs://metadata2";

        // Add first recipient
        vm.prank(flow.owner());
        flow.addRecipient(recipient1, metadata1);

        // Add second recipient
        vm.prank(flow.owner());
        flow.addRecipient(recipient2, metadata2);

        // Verify both recipients were added correctly
        assertEq(flow.recipientCount(), 2);

        (address storedRecipient1, , , ) = flow.recipients(0);
        (address storedRecipient2, , , ) = flow.recipients(1);

        assertEq(storedRecipient1, recipient1);
        assertEq(storedRecipient2, recipient2);
    }
}
