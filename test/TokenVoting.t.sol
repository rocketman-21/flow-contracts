// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {FlowTest} from "./Flow.t.sol";
import {IFlowEvents,IFlow} from "../src/interfaces/IFlow.sol";
import {Flow} from "../src/Flow.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {TestToken} from "@superfluid-finance/ethereum-contracts/contracts/utils/TestToken.sol";
import {console} from "forge-std/console.sol";

contract TokenVotingFlowTest is FlowTest {

    function setUp() override public {
        super.setUp();
    }

    // Ensure that voting with 721, transfering 721, then attempting to vote again fails.
    // 1. Should remove the old votes for that tokenId.
    // 2. Doesn't change memberUnits
    function test__DoubleVoting_AfterTransfer() public {
        address voter1 = address(1);
        address voter2 = address(2);
        uint256 tokenId = 0;

        nounsToken.mint(voter1, tokenId);

        address recipient = address(3);
        vm.prank(manager);
        flow.addRecipient(recipient, recipientMetadata);

        uint256[] memory recipientIds =  new uint256[](1);
        uint32[] memory percentAllocations = new uint32[](1);
        uint256[] memory tokenIds = new uint256[](1);

        percentAllocations[0] = 1e6;
        recipientIds[0] = 0; // Assuming the first recipient has ID 0
        tokenIds[0] = tokenId;

        vm.prank(voter1);
        flow.castVotes(tokenIds, recipientIds, percentAllocations);

        // get current member units of the pool
        uint128 currentUnits = flow.bonusPool().getUnits(recipient);

        assertGt(currentUnits, 0);

        vm.prank(voter1);
        nounsToken.transferFrom(voter1, voter2, tokenId);

        vm.prank(voter2);
        flow.castVotes(tokenIds, recipientIds, percentAllocations);

        uint128 newUnits = flow.bonusPool().getUnits(recipient);

        assertEq(newUnits, currentUnits);
    }

    function test__DoubleVoting_SameTokenId() public {
        address voter1 = address(1);
        uint256 tokenId = 0;

        nounsToken.mint(voter1, tokenId);

        address recipient = address(3);
        vm.prank(manager);
        flow.addRecipient(recipient, recipientMetadata);

        uint256[] memory recipientIds =  new uint256[](1);
        uint32[] memory percentAllocations = new uint32[](1);
        uint256[] memory tokenIds = new uint256[](1);

        percentAllocations[0] = 1e6;
        recipientIds[0] = 0; // Assuming the first recipient has ID 0
        tokenIds[0] = tokenId;

        vm.prank(voter1);
        flow.castVotes(tokenIds, recipientIds, percentAllocations);

        // get current member units of the pool
        uint128 currentUnits = flow.bonusPool().getUnits(recipient);

        assertGt(currentUnits, 0);

        uint256[] memory twoTokenIds = new uint256[](2);
        twoTokenIds[0] = tokenId;
        twoTokenIds[1] = tokenId;

        vm.prank(voter1);
        flow.castVotes(twoTokenIds, recipientIds, percentAllocations);

        uint128 newUnits = flow.bonusPool().getUnits(recipient);

        assertEq(newUnits, currentUnits);
    }

    function test__NotTokenOwner_OneToken() public {
        address voter1 = address(1);
        address voter2 = address(2);
        uint256 tokenId = 0;

        nounsToken.mint(voter1, tokenId);

        address recipient = address(3);
        vm.prank(manager);
        flow.addRecipient(recipient, recipientMetadata);

        uint256[] memory recipientIds =  new uint256[](1);
        uint32[] memory percentAllocations = new uint32[](1);
        uint256[] memory tokenIds = new uint256[](1);

        percentAllocations[0] = 1e6;
        recipientIds[0] = 0; // Assuming the first recipient has ID 0
        tokenIds[0] = tokenId;

        vm.prank(voter1);
        flow.castVotes(tokenIds, recipientIds, percentAllocations);

        vm.prank(voter1);
        nounsToken.transferFrom(voter1, voter2, tokenId);

        vm.prank(voter1);
        vm.expectRevert(IFlow.NOT_ABLE_TO_VOTE_WITH_TOKEN.selector);
        flow.castVotes(tokenIds, recipientIds, percentAllocations);
    }

    function test__NotTokenOwner_MultiTokens() public {
        address voter1 = address(1);
        address voter2 = address(2);
        uint256 tokenId = 0;

        nounsToken.mint(voter1, tokenId);
        nounsToken.mint(voter2, 1);

        address recipient = address(3);
        vm.prank(manager);
        flow.addRecipient(recipient, recipientMetadata);

        uint256[] memory recipientIds =  new uint256[](1);
        uint32[] memory percentAllocations = new uint32[](1);
        uint256[] memory tokenIds = new uint256[](2);

        percentAllocations[0] = 1e6;
        recipientIds[0] = 0; // Assuming the first recipient has ID 0
        tokenIds[0] = tokenId;
        tokenIds[1] = 1;

        vm.prank(voter1);
        vm.expectRevert(IFlow.NOT_ABLE_TO_VOTE_WITH_TOKEN.selector);
        flow.castVotes(tokenIds, recipientIds, percentAllocations);

        vm.prank(voter1);
        nounsToken.transferFrom(voter1, voter2, tokenId);

        vm.prank(voter1);
        vm.expectRevert(IFlow.NOT_ABLE_TO_VOTE_WITH_TOKEN.selector);
        flow.castVotes(tokenIds, recipientIds, percentAllocations);
    }

}