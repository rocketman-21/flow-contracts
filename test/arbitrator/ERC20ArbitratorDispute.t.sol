// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { ERC20VotesArbitratorTest } from "./ERC20VotesArbitrator.t.sol";
import { ArbitratorStorageV1 } from "../../src/tcr/storage/ArbitratorStorageV1.sol";
import { IArbitrable } from "../../src/tcr/interfaces/IArbitrable.sol";
import { IERC20VotesArbitrator } from "../../src/tcr/interfaces/IERC20VotesArbitrator.sol";

contract ERC20ArbitratorDisputeTest is ERC20VotesArbitratorTest {
    function testVotingOnDispute() public {
        setupAndExecuteRulingForDispute();

        uint256 disputeID = arbitrator.disputeCount();
        (, , , uint256 currentRound, , ) = arbitrator.disputes(disputeID);

        // Check if votes are properly committed and revealed
        ArbitratorStorageV1.Receipt memory receipt1 = arbitrator.getReceipt(disputeID, voter1);
        ArbitratorStorageV1.Receipt memory receipt2 = arbitrator.getReceipt(disputeID, voter2);
        ArbitratorStorageV1.Receipt memory receipt3 = arbitrator.getReceipt(disputeID, voter3);

        assertTrue(receipt1.hasCommitted && receipt1.hasRevealed, "Voter 1 vote not properly processed");
        assertTrue(receipt2.hasCommitted && receipt2.hasRevealed, "Voter 2 vote not properly processed");
        assertTrue(receipt3.hasCommitted && receipt3.hasRevealed, "Voter 3 vote not properly processed");

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
        uint256 totalVotes = arbitrator.getTotalVotesByRound(disputeID, currentRound);
        assertEq(
            totalVotes,
            erc20Token.balanceOf(voter1) + erc20Token.balanceOf(voter2) + erc20Token.balanceOf(voter3),
            "Incorrect total vote count"
        );

        // Check final ruling
        assertEq(
            uint256(arbitrator.currentRuling(disputeID)),
            uint256(IArbitrable.Party.Requester),
            "Incorrect final ruling"
        );
    }

    function setupAndExecuteRulingForDispute() public {
        // Create a new dispute
        (, uint256 disputeID) = submitItemAndChallenge(EXTERNAL_ACCOUNT_ITEM_DATA, requester, challenger);

        // Commit votes
        bytes32 salt1 = keccak256("salt1");
        bytes32 salt2 = keccak256("salt2");
        bytes32 salt3 = keccak256("salt3");

        advanceTime(VOTING_DELAY + 2);

        commitVote(disputeID, voter1, 1, "Reason 1", salt1);
        commitVote(disputeID, voter2, 2, "Reason 2", salt2);
        commitVote(disputeID, voter3, 1, "Reason 3", salt3);

        // Advance time to end of voting period
        advanceTime(VOTING_PERIOD);

        // Reveal votes
        revealVote(disputeID, voter1, 1, "Reason 1", salt1);
        revealVote(disputeID, voter2, 2, "Reason 2", salt2);
        revealVote(disputeID, voter3, 1, "Reason 3", salt3);

        // Advance time to end of reveal period
        advanceTime(REVEAL_PERIOD);

        // Execute ruling
        arbitrator.executeRuling(disputeID);
    }

    function testWithdrawVoterRewards() public {
        // Set up and execute the ruling for the dispute
        setupAndExecuteRulingForDispute();

        uint256 arbitratorCost = arbitrator.arbitrationCost(bytes(""));

        // Get the latest dispute ID
        uint256 disputeID = arbitrator.disputeCount();

        // The current round is 0
        uint256 currentRound = 0;

        // Voter1 attempts to withdraw their rewards
        uint256 balanceBeforeVoter1 = erc20Token.balanceOf(voter1);

        vm.prank(voter1);
        arbitrator.withdrawVoterRewards(disputeID, currentRound, voter1);

        uint256 balanceAfterVoter1 = erc20Token.balanceOf(voter1);

        // Verify that Voter1's balance has increased
        assertEq(balanceAfterVoter1, balanceBeforeVoter1 + arbitratorCost / 2, "Voter1 did not receive reward");

        // Voter2, who voted for the losing choice, attempts to withdraw rewards
        vm.prank(voter2);
        vm.expectRevert(abi.encodeWithSelector(IERC20VotesArbitrator.VOTER_ON_LOSING_SIDE.selector));
        arbitrator.withdrawVoterRewards(disputeID, currentRound, voter2);

        // Voter3 withdraws their rewards
        uint256 balanceBeforeVoter3 = erc20Token.balanceOf(voter3);

        vm.prank(voter3);
        arbitrator.withdrawVoterRewards(disputeID, currentRound, voter3);

        uint256 balanceAfterVoter3 = erc20Token.balanceOf(voter3);

        // Verify that Voter3's balance has increased
        assertEq(balanceAfterVoter3, balanceBeforeVoter3 + arbitratorCost / 2, "Voter3 did not receive reward");

        // Voter1 attempts to withdraw rewards again, should revert
        vm.prank(voter1);
        vm.expectRevert(abi.encodeWithSelector(IERC20VotesArbitrator.REWARD_ALREADY_CLAIMED.selector));
        arbitrator.withdrawVoterRewards(disputeID, currentRound, voter1);
    }
}
