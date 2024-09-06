// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {ERC721FlowTest} from "./ERC721Flow.t.sol";
import {IFlowEvents,IFlow} from "../src/interfaces/IFlow.sol";
import {Flow} from "../src/Flow.sol";
import {ERC721Flow} from "../src/ERC721Flow.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TestToken} from "@superfluid-finance/ethereum-contracts/contracts/utils/TestToken.sol";
import {console} from "forge-std/console.sol";

contract OwnerFlowTest is ERC721FlowTest {

    function setUp() override public {
        super.setUp();
    }

    function testRemoveNonexistentRecipient() public {
        uint256 nonexistentRecipientId = 999; // Assuming this ID doesn't exist

        vm.prank(manager); // Owner address
        vm.expectRevert(IFlow.INVALID_RECIPIENT_ID.selector);
        flow.removeRecipient(nonexistentRecipientId);
    }

    function testSetFlowImpl() public {
        address newFlowImpl = address(0x123);
        vm.prank(address(0)); // Non-owner address
        vm.expectRevert("Ownable: caller is not the owner");
        Flow(flow).setFlowImpl(newFlowImpl);

        vm.prank(manager); // Owner address
        Flow(flow).setFlowImpl(newFlowImpl);
        assertEq(Flow(flow).flowImpl(), newFlowImpl);
    }

    function testSetFlowRate() public {
        int96 newFlowRate = 10;
        vm.prank(address(1)); // Non-owner address
        vm.expectRevert(IFlow.NOT_OWNER_OR_PARENT.selector);
        Flow(flow).setFlowRate(newFlowRate);

        vm.prank(manager); // Owner address
        Flow(flow).setFlowRate(newFlowRate);
        assertEq(Flow(flow).getTotalFlowRate(), newFlowRate);
    }

    function testUpgrade() public {
        address newImplementation = address(new ERC721Flow());
        vm.prank(address(0)); // Non-owner address
        vm.expectRevert("Ownable: caller is not the owner");
        Flow(flow).upgradeTo(newImplementation);

        vm.prank(manager); // Owner address
        Flow(flow).upgradeTo(newImplementation);
        // Additional checks to verify upgrade might be needed
    }

    function testTransferOwnership() public {
        address newOwner = address(0x456);
        vm.prank(address(0)); // Non-owner address
        vm.expectRevert("Ownable: caller is not the owner");
        Flow(flow).transferOwnership(newOwner);

        vm.prank(manager); // Owner address
        Flow(flow).transferOwnership(newOwner);
        assertEq(Flow(flow).owner(), manager); // Ownership not transferred yet due to two-step process

        vm.prank(newOwner);
        Flow(flow).acceptOwnership();
        assertEq(Flow(flow).owner(), newOwner);
    }

    function testRenounceOwnership() public {
        vm.prank(address(0)); // Non-owner address
        vm.expectRevert("Ownable: caller is not the owner");
        Flow(flow).renounceOwnership();

        vm.prank(manager); // Owner address
        Flow(flow).renounceOwnership();
        assertEq(Flow(flow).owner(), address(0));
    }

}