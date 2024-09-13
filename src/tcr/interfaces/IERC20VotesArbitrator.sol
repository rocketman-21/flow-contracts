// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IArbitrator.sol";

interface IERC20VotesArbitrator is IArbitrator {
    /// @notice Error thrown when the voting token address is invalid (zero address)
    error INVALID_VOTING_TOKEN_ADDRESS();

    /// @notice Error thrown when the voting period is outside the allowed range
    error INVALID_VOTING_PERIOD();

    /// @notice Error thrown when the voting delay is outside the allowed range
    error INVALID_VOTING_DELAY();

    /// @notice Error thrown when the quorum votes basis points are outside the allowed range
    error INVALID_QUORUM_VOTES_BPS();

    /// @notice Error thrown when the function is called by an address other than the arbitrable address
    error ONLY_ARBITRABLE();

    /// @notice Error thrown when the reveal period is outside the allowed range
    error INVALID_REVEAL_PERIOD();

    /// @notice Error thrown when the dispute ID is invalid
    error INVALID_DISPUTE_ID();

    /// @notice Error thrown when trying to execute a dispute that is not in the Solved state
    error DISPUTE_NOT_SOLVED();

    /// @notice Error thrown when trying to execute a dispute that is not in the Appealable state
    error DISPUTE_NOT_APPEALABLE();

    /// @notice Error thrown when trying to execute a dispute that has already been executed
    error DISPUTE_ALREADY_EXECUTED();

    /// @notice Error thrown when the appeal period is outside the allowed range
    error INVALID_APPEAL_PERIOD();

    /// @notice Error thrown when the appeal cost is outside the allowed range
    error INVALID_APPEAL_COST();

    /// @notice Error thrown when the arbitration cost is outside the allowed range
    error INVALID_ARBITRATION_COST();

    /// @notice Error thrown when the appeal period is ended
    error APPEAL_PERIOD_ENDED();

    /// @notice Error thrown when the voting is closed for a dispute
    error VOTING_CLOSED();

    /// @notice Error thrown when an invalid vote choice is selected
    error INVALID_VOTE_CHOICE();

    /// @notice Error thrown when a voter attempts to vote more than once on a dispute
    error VOTER_ALREADY_VOTED();

    /// @notice Error thrown when the number of choices for a dispute is invalid
    error INVALID_DISPUTE_CHOICES();

    /**
     * @notice Emitted when the voting period is set
     * @param oldVotingPeriod The previous voting period
     * @param newVotingPeriod The new voting period
     */
    event VotingPeriodSet(uint256 oldVotingPeriod, uint256 newVotingPeriod);

    /**
     * @notice Emitted when a dispute is reset
     * @param disputeId The ID of the dispute that was reset
     * @param votingStartTime The timestamp when voting starts
     * @param votingEndTime The timestamp when voting ends
     * @param revealPeriodEndTime The timestamp when the reveal period ends
     * @param appealPeriodEndTime The timestamp when the appeal period ends
     * @param quorumVotes The number of votes required for quorum
     * @param totalSupply The total supply of voting tokens at dispute creation
     * @param cost The cost paid by the arbitrable contract for this voting round. Either arbitrationCost or appealCost
     * @param extraData Additional data related to the dispute
     */
    event DisputeReset(
        uint256 disputeId,
        uint256 votingStartTime,
        uint256 votingEndTime,
        uint256 revealPeriodEndTime,
        uint256 appealPeriodEndTime,
        uint256 quorumVotes,
        uint256 totalSupply,
        uint256 cost,
        bytes extraData
    );

    /**
     * @notice Emitted when an appeal is raised
     * @param disputeId The ID of the dispute
     * @param roundNumber The round number of the appeal
     * @param appealer The address of the appealer
     * @param appealCost The cost of the appeal
     */
    event AppealRaised(uint256 disputeId, uint256 roundNumber, address appealer, uint256 appealCost);

    /**
     * @notice Emitted when the voting delay is set
     * @param oldVotingDelay The previous voting delay
     * @param newVotingDelay The new voting delay
     */
    event VotingDelaySet(uint256 oldVotingDelay, uint256 newVotingDelay);

    /**
     * @notice Emitted when the appeal cost is set
     * @param oldAppealCost The previous appeal cost
     * @param newAppealCost The new appeal cost
     */
    event AppealCostSet(uint256 oldAppealCost, uint256 newAppealCost);

    /**
     * @notice Emitted when the arbitration cost is set
     * @param oldArbitrationCost The previous arbitration cost
     * @param newArbitrationCost The new arbitration cost
     */
    event ArbitrationCostSet(uint256 oldArbitrationCost, uint256 newArbitrationCost);

    /**
     * @notice Emitted when the quorum votes basis points are set
     * @param oldQuorumVotesBPS The previous quorum votes basis points
     * @param newQuorumVotesBPS The new quorum votes basis points
     */
    event QuorumVotesBPSSet(uint256 oldQuorumVotesBPS, uint256 newQuorumVotesBPS);

    /**
     * @notice Emitted when the appeal period is set
     * @param oldAppealPeriod The previous appeal period
     * @param newAppealPeriod The new appeal period
     */
    event AppealPeriodSet(uint256 oldAppealPeriod, uint256 newAppealPeriod);

    /**
     * @notice Emitted when a vote has been cast on a dispute
     * @param voter The address of the voter
     * @param disputeId The ID of the dispute
     * @param choice The choice that was voted for
     * @param votes The number of votes cast
     * @param reason The reason given for the vote by the voter
     */
    event VoteCast(address indexed voter, uint256 disputeId, uint256 choice, uint256 votes, string reason);

    /**
     * @dev Emitted when a dispute is executed and a ruling is set
     * @param disputeId The ID of the executed dispute
     * @param ruling The final ruling for the dispute
     */
    event DisputeExecuted(uint256 indexed disputeId, IArbitrable.Party ruling);

    /**
     * @notice Emitted when a new dispute is created
     * @param id The ID of the newly created dispute
     * @param arbitrable The address of the arbitrable contract
     * @param votingStartTime The timestamp when voting starts
     * @param votingEndTime The timestamp when voting ends
     * @param revealPeriodEndTime The timestamp when the reveal period ends
     * @param appealPeriodEndTime The timestamp when the appeal period ends
     * @param quorumVotes The number of votes required for quorum
     * @param totalSupply The total supply of voting tokens at dispute creation
     * @param extraData Additional data related to the dispute
     * @param choices The number of choices available for voting
     */
    event DisputeCreated(
        uint256 id,
        address indexed arbitrable,
        uint256 votingStartTime,
        uint256 votingEndTime,
        uint256 revealPeriodEndTime,
        uint256 appealPeriodEndTime,
        uint256 quorumVotes,
        uint256 totalSupply,
        bytes extraData,
        uint256 choices
    );
}
