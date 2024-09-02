// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {FlowTest} from "./Flow.t.sol";
import {IFlowEvents,IFlow} from "../src/interfaces/IFlow.sol";
import {Flow} from "../src/Flow.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TestToken} from "@superfluid-finance/ethereum-contracts/contracts/utils/TestToken.sol";
import {console} from "forge-std/console.sol";

contract VotingValidationTest is FlowTest {

    function setUp() override public {
        super.setUp();
    }

    function test__InvalidPercentAllocations() public {
        address voter1 = address(1);
        uint256 tokenId = 0;

        nounsToken.mint(voter1, tokenId);

        address recipient = address(3);
        flow.addRecipient(recipient);

        address[] memory recipients =  new address[](1);
        uint32[] memory percentAllocations = new uint32[](0);
        uint256[] memory tokenIds = new uint256[](1);

        recipients[0] = recipient;
        tokenIds[0] = tokenId;

        vm.prank(voter1);
        bytes4 selector = bytes4(keccak256("RECIPIENTS_ALLOCATIONS_MISMATCH(uint256,uint256)"));

        vm.expectRevert(abi.encodeWithSelector(selector, 1, 0));
        flow.castVotes(tokenIds, recipients, percentAllocations);

        uint32[] memory percentAllocationsTwo = new uint32[](2);
        vm.prank(voter1);
        vm.expectRevert(abi.encodeWithSelector(selector, 1, 2));
        flow.castVotes(tokenIds, recipients, percentAllocationsTwo);

        address[] memory recipientsTwo =  new address[](2);
        recipientsTwo[0] = recipient;
        recipientsTwo[1] = recipient;

        vm.expectRevert(IFlow.ALLOCATION_MUST_BE_POSITIVE.selector);
        vm.prank(voter1);
        flow.castVotes(tokenIds, recipientsTwo, percentAllocationsTwo);

        percentAllocationsTwo[0] = 1e6;
        percentAllocationsTwo[1] = 1e6;
        vm.prank(voter1);
        vm.expectRevert(IFlow.INVALID_BPS_SUM.selector);
        flow.castVotes(tokenIds, recipientsTwo, percentAllocationsTwo);
    }

    function test__InvalidRecipients() public {
        address voter1 = address(1);
        uint256 tokenId = 0;

        nounsToken.mint(voter1, tokenId);

        address recipient = address(3);
        flow.addRecipient(recipient);

        address[] memory recipients =  new address[](0);
        uint32[] memory percentAllocations = new uint32[](1);
        uint256[] memory tokenIds = new uint256[](1);

        percentAllocations[0] = 1e6;
        tokenIds[0] = tokenId;

        vm.prank(voter1);
        vm.expectRevert(IFlow.TOO_FEW_RECIPIENTS.selector);
        flow.castVotes(tokenIds, recipients, percentAllocations);

        address recipient2 = address(4);

        address[] memory recipients2 =  new address[](1);
        recipients2[0] = recipient2;

        vm.prank(voter1);
        vm.expectRevert(IFlow.NOT_APPROVED_RECIPIENT.selector);
        flow.castVotes(tokenIds, recipients2, percentAllocations);
    }

    function test__RecipientZeroAddr() public {
        address voter1 = address(1);
        uint256 tokenId = 0;

        nounsToken.mint(voter1, tokenId);

        address recipient = address(3);
        flow.addRecipient(recipient);

        address[] memory recipients =  new address[](1);
        uint32[] memory percentAllocations = new uint32[](1);
        uint256[] memory tokenIds = new uint256[](1);

        percentAllocations[0] = 1e6;
        tokenIds[0] = tokenId;
        recipients[0] = address(0);

        vm.prank(voter1);
        vm.expectRevert(IFlow.ADDRESS_ZERO.selector);
        flow.castVotes(tokenIds, recipients, percentAllocations);
    }

}