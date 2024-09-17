// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20VotesArbitratorTest } from "./ERC20VotesArbitrator.t.sol";
import { ArbitratorStorageV1 } from "../../src/tcr/storage/ArbitratorStorageV1.sol";
import { IArbitrable } from "../../src/tcr/interfaces/IArbitrable.sol";

contract ERC20ArbitratorDisputeTest is ERC20VotesArbitratorTest {
    function testVotingOnDispute() public {
        // Create a new dispute
        (, uint256 disputeID) = submitItemAndChallenge(ITEM_DATA, requester, challenger);

        // Commit votes
        bytes32 salt1 = keccak256(abi.encodePacked("salt1"));
        bytes32 salt2 = keccak256(abi.encodePacked("salt2"));
        bytes32 salt3 = keccak256(abi.encodePacked("salt3"));

        advanceTime(VOTING_DELAY + 2);

        commitVote(disputeID, voter1, 1, "Reason 1", salt1);
        commitVote(disputeID, voter2, 2, "Reason 2", salt2);
        commitVote(disputeID, voter3, 1, "Reason 3", salt3);

        // Check if votes are properly committed
        (, , , uint256 currentRound, , ) = arbitrator.disputes(disputeID);

        ArbitratorStorageV1.Receipt memory receipt1 = arbitrator.getReceipt(disputeID, voter1);
        ArbitratorStorageV1.Receipt memory receipt2 = arbitrator.getReceipt(disputeID, voter2);
        ArbitratorStorageV1.Receipt memory receipt3 = arbitrator.getReceipt(disputeID, voter3);

        assertTrue(receipt1.hasCommitted, "Voter 1 vote not committed");
        assertTrue(receipt2.hasCommitted, "Voter 2 vote not committed");
        assertTrue(receipt3.hasCommitted, "Voter 3 vote not committed");

        // Advance time to reveal period
        advanceTime(VOTING_PERIOD);

        // Reveal votes
        revealVote(disputeID, voter1, 1, "Reason 1", salt1);
        revealVote(disputeID, voter2, 2, "Reason 2", salt2);
        revealVote(disputeID, voter3, 1, "Reason 3", salt3);

        receipt1 = arbitrator.getReceipt(disputeID, voter1);
        receipt2 = arbitrator.getReceipt(disputeID, voter2);
        receipt3 = arbitrator.getReceipt(disputeID, voter3);

        // Check if votes are properly revealed
        assertTrue(receipt1.hasRevealed, "Voter 1 vote not revealed");
        assertTrue(receipt2.hasRevealed, "Voter 2 vote not revealed");
        assertTrue(receipt3.hasRevealed, "Voter 3 vote not revealed");

        // Get vote counts for each choice
        uint256 choiceVotes1 = arbitrator.getVotesByRound(disputeID, currentRound, 1);
        uint256 choiceVotes2 = arbitrator.getVotesByRound(disputeID, currentRound, 2);

        // Check vote counts
        assertEq(
            choiceVotes1,
            erc20Token.balanceOf(voter1) + erc20Token.balanceOf(voter3),
            "Incorrect vote count for choice 1"
        );
        assertEq(choiceVotes2, erc20Token.balanceOf(voter2), "Incorrect vote count for choice 2");

        // Check total votes
        assertEq(
            choiceVotes1 + choiceVotes2,
            erc20Token.balanceOf(voter1) + erc20Token.balanceOf(voter2) + erc20Token.balanceOf(voter3),
            "Incorrect total vote count"
        );

        // check total votes returned by getVotesByRound
        uint256 totalVotes = arbitrator.getTotalVotesByRound(disputeID, currentRound);
        assertEq(totalVotes, choiceVotes1 + choiceVotes2, "Incorrect total votes for choice 1");

        // Advance time to end of reveal period
        advanceTime(REVEAL_PERIOD + APPEAL_PERIOD);

        // Execute ruling
        arbitrator.executeRuling(disputeID);

        // Check final ruling
        assertEq(
            uint256(arbitrator.currentRuling(disputeID)),
            uint256(IArbitrable.Party.Requester),
            "Incorrect final ruling"
        );
    }
}
