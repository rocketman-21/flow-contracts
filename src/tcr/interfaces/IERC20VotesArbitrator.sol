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

    /// @notice Error thrown when the function is called by an address other than the arbitrable address
    error ONLY_ARBITRABLE();

    /// @notice Error thrown when the reveal period is outside the allowed range
    error INVALID_REVEAL_PERIOD();

    /// @notice Error thrown when the dispute ID is invalid
    error INVALID_DISPUTE_ID();

    /// @notice Error thrown when trying to execute a dispute that is not in the Solved state
    error DISPUTE_NOT_SOLVED();

    /// @notice Error thrown when trying to execute a dispute that has already been executed
    error DISPUTE_ALREADY_EXECUTED();

    /// @notice Error thrown when the round is invalid
    error INVALID_ROUND();

    /// @notice Error thrown when there are no votes
    error NO_VOTES();

    /// @notice Error thrown when owner tries to withdraw rewards for a round that has votes
    error VOTES_WERE_CAST();

    /// @notice Error thrown when there are no winning votes
    error NO_WINNING_VOTES();

    /// @notice Error thrown when the arbitration cost is outside the allowed range
    error INVALID_ARBITRATION_COST();

    /// @notice Error thrown when the arbitrable address is invalid (zero address)
    error INVALID_ARBITRABLE_ADDRESS();

    /// @notice Error thrown when the voting is closed for a dispute
    error VOTING_CLOSED();

    /// @notice Error thrown when a voter has no votes
    error VOTER_HAS_NO_VOTES();

    /// @notice Error thrown when an invalid vote choice is selected
    error INVALID_VOTE_CHOICE();

    /// @notice Error thrown when a voter attempts to vote more than once on a dispute
    error VOTER_ALREADY_VOTED();

    /// @notice Error thrown when the number of choices for a dispute is invalid
    error INVALID_DISPUTE_CHOICES();

    /// @notice Error thrown when a voter has not voted
    error VOTER_HAS_NOT_VOTED();

    /// @notice Error thrown when the initial owner is invalid (zero address)
    error INVALID_INITIAL_OWNER();

    /// @notice Error thrown when a reward has already been claimed
    error REWARD_ALREADY_CLAIMED();

    /// @notice Error thrown when a voter is on the losing side
    error VOTER_ON_LOSING_SIDE();

    /// @notice Error thrown when a dispute is not executed
    error DISPUTE_NOT_EXECUTED();

    /// @notice Error thrown when a voter has not committed a vote
    error NO_COMMITTED_VOTE();

    /// @notice Error thrown when a voter has already revealed a vote
    error ALREADY_REVEALED_VOTE();

    /// @notice Error thrown when the hashes do not match
    error HASHES_DO_NOT_MATCH();

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
     * @param totalSupply The total supply of voting tokens at dispute creation
     * @param cost The cost paid by the arbitrable contract for this voting round.
     * @param extraData Additional data related to the dispute
     */
    event DisputeReset(
        uint256 disputeId,
        uint256 votingStartTime,
        uint256 votingEndTime,
        uint256 revealPeriodEndTime,
        uint256 totalSupply,
        uint256 cost,
        bytes extraData
    );

    /**
     * @notice Emitted when the voting delay is set
     * @param oldVotingDelay The previous voting delay
     * @param newVotingDelay The new voting delay
     */
    event VotingDelaySet(uint256 oldVotingDelay, uint256 newVotingDelay);

    /**
     * @notice Emitted when the reveal period is set
     * @param oldRevealPeriod The previous reveal period
     * @param newRevealPeriod The new reveal period
     */
    event RevealPeriodSet(uint256 oldRevealPeriod, uint256 newRevealPeriod);

    /**
     * @notice Emitted when a voter withdraws their proportional share of the cost for a voting round
     * @param disputeId The ID of the dispute
     * @param round The round number
     * @param voter The address of the voter
     * @param amount The amount withdrawn
     */
    event RewardWithdrawn(uint256 indexed disputeId, uint256 indexed round, address indexed voter, uint256 amount);

    /**
     * @notice Emitted when the arbitration cost is set
     * @param oldArbitrationCost The previous arbitration cost
     * @param newArbitrationCost The new arbitration cost
     */
    event ArbitrationCostSet(uint256 oldArbitrationCost, uint256 newArbitrationCost);

    /**
     * @notice Emitted when a vote has been cast on a dispute
     * @param voter The address of the voter
     * @param disputeId The ID of the dispute
     * @param commitHash The keccak256 hash of the voter's choice, reason (optional) and salt (tightly packed in this order)
     */
    event VoteCommitted(address indexed voter, uint256 disputeId, bytes32 commitHash);

    /**
     * @notice Emitted when a vote has been revealed for a dispute
     * @param voter The address of the voter
     * @param disputeId The ID of the dispute
     * @param commitHash The keccak256 hash of the voter's choice, reason (optional) and salt (tightly packed in this order)
     * @param choice The revealed choice of the voter
     * @param reason The reason for the vote
     * @param votes The number of votes cast
     */
    event VoteRevealed(
        address indexed voter,
        uint256 indexed disputeId,
        bytes32 commitHash,
        uint256 choice,
        string reason,
        uint256 votes
    );

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
     * @param totalSupply The total supply of voting tokens at dispute creation
     * @param creationBlock The block number when the dispute was created
     * @param arbitrationCost The cost paid by the arbitrable contract for this voting round.
     * @param extraData Additional data related to the dispute
     * @param choices The number of choices available for voting
     */
    event DisputeCreated(
        uint256 id,
        address indexed arbitrable,
        uint256 votingStartTime,
        uint256 votingEndTime,
        uint256 revealPeriodEndTime,
        uint256 totalSupply,
        uint256 creationBlock,
        uint256 arbitrationCost,
        bytes extraData,
        uint256 choices
    );

    /**
     * @notice Used to initialize the contract
     * @param initialOwner The address of the initial owner
     * @param votingToken The address of the ERC20 voting token
     * @param arbitrable The address of the arbitrable contract
     * @param votingPeriod The initial voting period
     * @param votingDelay The initial voting delay
     * @param revealPeriod The initial reveal period to reveal committed votes
     * @param arbitrationCost The initial arbitration cost
     */
    function initialize(
        address initialOwner,
        address votingToken,
        address arbitrable,
        uint256 votingPeriod,
        uint256 votingDelay,
        uint256 revealPeriod,
        uint256 arbitrationCost
    ) external;
}
