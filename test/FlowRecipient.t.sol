// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {FlowTest} from "./Flow.t.sol";
import {IFlowEvents,IFlow} from "../src/interfaces/IFlow.sol";
import {Flow} from "../src/Flow.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {FlowStorageV1} from "../src/storage/FlowStorageV1.sol";

contract FlowRecipientTest is FlowTest {

    function setUp() override public {
        super.setUp();
    }

    function testAddFlowRecipient() public {
        FlowStorageV1.RecipientMetadata memory metadata = FlowStorageV1.RecipientMetadata("Flow Recipient", "A new Flow contract", "ipfs://image");
        address flowManager = address(0x123); // New flow manager address

        vm.startPrank(flow.owner());

        // Test successful addition of a Flow recipient
        vm.expectEmit(false, false, true, true);
        emit IFlowEvents.RecipientCreated(address(0), manager); // address(0) as we don't know the new address yet

        address newFlowAddress = flow.addFlowRecipient(metadata, flowManager);

        assertNotEq(newFlowAddress, address(0));

        // Verify recipient was added correctly
        assertNotEq(newFlowAddress, address(0));
        (address storedRecipient, bool removed, FlowStorageV1.RecipientType recipientType, FlowStorageV1.RecipientMetadata memory storedMetadata) = flow.recipients(0);
        assertEq(storedRecipient, newFlowAddress);
        assertEq(removed, false);
        assertEq(uint8(recipientType), uint8(FlowStorageV1.RecipientType.FlowContract));
        assertEq(storedMetadata.title, metadata.title);
        assertEq(storedMetadata.description, metadata.description);
        assertEq(storedMetadata.image, metadata.image);

        // Verify recipient count increased
        assertEq(flow.recipientCount(), 1);

        // Check the newly created Flow contract fields
        Flow newFlow = Flow(newFlowAddress);
        assertEq(address(newFlow.erc721Votes()), address(nounsToken));
        assertEq(address(newFlow.superToken()), address(superToken));
        assertEq(newFlow.flowImpl(), flow.flowImpl());
        assertEq(newFlow.manager(), flowManager); // Check that the manager is set to the new flowManager
        assertEq(newFlow.tokenVoteWeight(), flow.tokenVoteWeight());
        (string memory title, string memory description, string memory image) = newFlow.metadata();
        assertEq(title, metadata.title);
        assertEq(description, metadata.description);
        assertEq(image, metadata.image);
        vm.stopPrank();

        // Test accepting ownership of the new Flow contract
        vm.prank(flow.owner());
        newFlow.acceptOwnership();

        // Verify that ownership has been accepted
        assertEq(newFlow.owner(), flow.owner());

        vm.stopPrank();
    }

    function testAddFlowRecipientEmptyMetadata() public {
        FlowStorageV1.RecipientMetadata memory emptyMetadata = FlowStorageV1.RecipientMetadata("", "", "");
        address flowManager = address(0x123);

        vm.prank(flow.owner());
        vm.expectRevert(IFlow.INVALID_METADATA.selector);
        flow.addFlowRecipient(emptyMetadata, flowManager);
    }

    function testAddFlowRecipientNonManager() public {
        FlowStorageV1.RecipientMetadata memory metadata = FlowStorageV1.RecipientMetadata("Flow Recipient", "A new Flow contract", "ipfs://image");
        address flowManager = address(0x123);

        vm.prank(address(0xABC));
        vm.expectRevert(IFlow.SENDER_NOT_MANAGER.selector);
        flow.addFlowRecipient(metadata, flowManager);
    }

    function testAddMultipleFlowRecipients() public {
        FlowStorageV1.RecipientMetadata memory metadata1 = FlowStorageV1.RecipientMetadata("Flow Recipient 1", "First Flow contract", "ipfs://image1");
        FlowStorageV1.RecipientMetadata memory metadata2 = FlowStorageV1.RecipientMetadata("Flow Recipient 2", "Second Flow contract", "ipfs://image2");
        address flowManager1 = address(0x123);
        address flowManager2 = address(0x456);

        vm.startPrank(flow.owner());

        address newFlowAddress1 = flow.addFlowRecipient(metadata1, flowManager1);
        address newFlowAddress2 = flow.addFlowRecipient(metadata2, flowManager2);

        assertNotEq(newFlowAddress1, newFlowAddress2);
        assertEq(flow.recipientCount(), 2);

        vm.stopPrank();
    }
}
