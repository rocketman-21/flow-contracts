// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import "./Flow.t.sol";

contract BasicFlowTest is FlowTest {

    function setUp() override public {
        super.setUp();
    }

    function test_initialize() public {
        // Ensure the Flow contract is initialized correctly
        assertEq(address(Flow(flow).erc721Votes()), address(0x1));
        assertEq(Flow(flow).minVotingPowerToVote(), 1e18);
        assertEq(Flow(flow).minVotingPowerToCreate(), 100 * 1e18);
        assertEq(Flow(flow).quorumVotesBPS(), 5000);
        assertEq(Flow(flow).tokenVoteWeight(), 1e18);
    }
}
