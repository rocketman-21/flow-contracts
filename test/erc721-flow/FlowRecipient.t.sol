// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import { IFlowEvents, IFlow } from "../../src/interfaces/IFlow.sol";
import { ERC721Flow } from "../../src/ERC721Flow.sol";
import { FlowStorageV1 } from "../../src/storage/FlowStorageV1.sol";
import { ERC721FlowTest } from "./ERC721Flow.t.sol";

contract FlowRecipientTest is ERC721FlowTest {
    function setUp() public override {
        super.setUp();
    }
    function testAddFlowRecipientParent() public {
        FlowStorageV1.RecipientMetadata memory metadata = FlowStorageV1.RecipientMetadata(
            "Flow Recipient",
            "A new Flow contract",
            "ipfs://image",
            "Flow Recipient Tagline",
            "https://flowrecipient.com"
        );
        address flowManager = address(0x123);

        vm.prank(manager);
        address newFlowAddress = flow.addFlowRecipient(metadata, flowManager);

        ERC721Flow newFlow = ERC721Flow(newFlowAddress);

        // Transfer test tokens to the new Flow contract
        _transferTestTokenToFlow(newFlowAddress, 1e6 * 10 ** 18);

        // Check that the parent of the new Flow contract is set correctly
        assertEq(newFlow.parent(), address(flow), "Parent of new Flow contract should be the original Flow contract");

        // Test that parent can call setFlowRate
        int96 newFlowRate = 1000;
        vm.prank(address(flow));
        newFlow.setFlowRate(newFlowRate);

        // Verify the flow rate was updated
        assertEq(newFlow.getTotalFlowRate(), newFlowRate, "Flow rate should be updated by parent");
    }

    function testAddFlowRecipient() public {
        FlowStorageV1.RecipientMetadata memory metadata = FlowStorageV1.RecipientMetadata(
            "Flow Recipient",
            "A new Flow contract",
            "ipfs://image",
            "Flow Recipient Tagline",
            "https://flowrecipient.com"
        );
        address flowManager = address(0x123); // New flow manager address

        vm.startPrank(flow.owner());

        // Test successful addition of a Flow recipient
        vm.expectEmit(false, true, false, false);
        emit IFlowEvents.RecipientCreated(
            0,
            FlowStorageV1.FlowRecipient({
                recipientType: FlowStorageV1.RecipientType.FlowContract,
                removed: false,
                recipient: address(0),
                metadata: metadata
            }),
            flow.owner()
        );
        address newFlowAddress = flow.addFlowRecipient(metadata, flowManager);

        assertNotEq(newFlowAddress, address(0));

        // Verify recipient was added correctly
        assertNotEq(newFlowAddress, address(0));
        (
            address storedRecipient,
            bool removed,
            FlowStorageV1.RecipientType recipientType,
            FlowStorageV1.RecipientMetadata memory storedMetadata
        ) = flow.recipients(0);
        assertEq(storedRecipient, newFlowAddress);
        assertEq(removed, false);
        assertEq(uint8(recipientType), uint8(FlowStorageV1.RecipientType.FlowContract));
        assertEq(storedMetadata.title, metadata.title);
        assertEq(storedMetadata.description, metadata.description);
        assertEq(storedMetadata.image, metadata.image);
        assertEq(storedMetadata.tagline, metadata.tagline);
        assertEq(storedMetadata.url, metadata.url);

        // Verify recipient count increased
        assertEq(flow.recipientCount(), 1);

        // Check the newly created Flow contract fields
        ERC721Flow newFlow = ERC721Flow(newFlowAddress);
        assertEq(address(newFlow.erc721Votes()), address(nounsToken));
        assertEq(address(newFlow.superToken()), address(superToken));
        assertEq(newFlow.flowImpl(), flow.flowImpl());
        assertEq(newFlow.manager(), flowManager); // Check that the manager is set to the new flowManager
        assertEq(newFlow.tokenVoteWeight(), flow.tokenVoteWeight());
        (
            string memory title,
            string memory description,
            string memory image,
            string memory tagline,
            string memory url
        ) = newFlow.metadata();
        assertEq(title, metadata.title);
        assertEq(description, metadata.description);
        assertEq(image, metadata.image);
        assertEq(tagline, metadata.tagline);
        assertEq(url, metadata.url);
        vm.stopPrank();

        // Test accepting ownership of the new Flow contract
        vm.prank(flow.owner());
        newFlow.acceptOwnership();

        // Verify that ownership has been accepted
        assertEq(newFlow.owner(), flow.owner());

        vm.stopPrank();
    }

    function testAddFlowRecipientEmptyManager() public {
        FlowStorageV1.RecipientMetadata memory metadata = FlowStorageV1.RecipientMetadata(
            "Flow Recipient",
            "A new Flow contract",
            "ipfs://image",
            "Flow Recipient Tagline",
            "https://flowrecipient.com"
        );
        address emptyManager = address(0);

        vm.startPrank(flow.owner());

        vm.expectRevert(IFlow.ADDRESS_ZERO.selector);
        flow.addFlowRecipient(metadata, emptyManager);

        vm.stopPrank();
    }

    function testAddFlowRecipientEmptyMetadata() public {
        FlowStorageV1.RecipientMetadata memory emptyMetadata = FlowStorageV1.RecipientMetadata("", "", "", "", "");
        address flowManager = address(0x123);

        vm.prank(flow.owner());
        vm.expectRevert(IFlow.INVALID_METADATA.selector);
        flow.addFlowRecipient(emptyMetadata, flowManager);
    }

    function testAddFlowRecipientNonManager() public {
        FlowStorageV1.RecipientMetadata memory metadata = FlowStorageV1.RecipientMetadata(
            "Flow Recipient",
            "A new Flow contract",
            "ipfs://image",
            "Flow Recipient Tagline",
            "https://flowrecipient.com"
        );
        address flowManager = address(0x123);

        vm.prank(address(0xABC));
        vm.expectRevert(IFlow.SENDER_NOT_MANAGER.selector);
        flow.addFlowRecipient(metadata, flowManager);
    }

    function testAddMultipleFlowRecipients() public {
        FlowStorageV1.RecipientMetadata memory metadata1 = FlowStorageV1.RecipientMetadata(
            "Flow Recipient 1",
            "First Flow contract",
            "ipfs://image1",
            "Tagline 1",
            "https://flow1.com"
        );
        FlowStorageV1.RecipientMetadata memory metadata2 = FlowStorageV1.RecipientMetadata(
            "Flow Recipient 2",
            "Second Flow contract",
            "ipfs://image2",
            "Tagline 2",
            "https://flow2.com"
        );
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
