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

    /**
     * @notice Emitted when the voting period is set
     * @param oldVotingPeriod The previous voting period
     * @param newVotingPeriod The new voting period
     */
    event VotingPeriodSet(uint256 oldVotingPeriod, uint256 newVotingPeriod);

    /**
     * @notice Emitted when the voting delay is set
     * @param oldVotingDelay The previous voting delay
     * @param newVotingDelay The new voting delay
     */
    event VotingDelaySet(uint256 oldVotingDelay, uint256 newVotingDelay);

    /**
     * @notice Emitted when the quorum votes basis points are set
     * @param oldQuorumVotesBPS The previous quorum votes basis points
     * @param newQuorumVotesBPS The new quorum votes basis points
     */
    event QuorumVotesBPSSet(uint256 oldQuorumVotesBPS, uint256 newQuorumVotesBPS);

    /**
     * @notice Emitted when a vote has been cast on a dispute
     * @param voter The address of the voter
     * @param disputeId The ID of the dispute
     * @param choice The choice that was voted for
     * @param votes The number of votes cast
     * @param reason The reason given for the vote by the voter
     */
    event VoteCast(address indexed voter, uint256 disputeId, uint8 choice, uint96 votes, string reason);

    /**
     * @notice Emitted when a new dispute is created
     * @param id The ID of the newly created dispute
     * @param arbitrable The address of the arbitrable contract
     * @param votingStartBlock The block number when voting starts
     * @param votingEndBlock The block number when voting ends
     * @param revealPeriodEndBlock The block number when the reveal period ends
     * @param quorumVotes The number of votes required for quorum
     * @param totalSupply The total supply of voting tokens at dispute creation
     * @param extraData Additional data related to the dispute
     * @param choices The number of choices available for voting
     */
    event DisputeCreated(
        uint256 id,
        address indexed arbitrable,
        uint256 votingStartBlock,
        uint256 votingEndBlock,
        uint256 revealPeriodEndBlock,
        uint256 quorumVotes,
        uint256 totalSupply,
        bytes extraData,
        uint256 choices
    );
}
