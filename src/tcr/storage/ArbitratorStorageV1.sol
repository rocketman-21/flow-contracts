// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IArbitrator } from "../interfaces/IArbitrator.sol";
import { IArbitrable } from "../interfaces/IArbitrable.sol";
import { ERC20VotesMintable } from "../../ERC20VotesMintable.sol";

/**
 * @title ArbitratorStorageV1
 * @notice Storage contract for the Arbitrator implementation
 */
contract ArbitratorStorageV1 {
    /** @notice The minimum setable voting period */
    uint256 public constant MIN_VOTING_PERIOD = 86_400; // 24 hours

    /** @notice The max setable voting period */
    uint256 public constant MAX_VOTING_PERIOD = 1_209_600; // 2 weeks

    /** @notice The min setable voting delay */
    uint256 public constant MIN_VOTING_DELAY = 1;

    /** @notice The max setable voting delay */
    uint256 public constant MAX_VOTING_DELAY = 604_800; // 1 week

    /** @notice The minimum setable reveal period */
    uint256 public constant MIN_REVEAL_PERIOD = 86_400; // 24 hours

    /** @notice The maximum setable reveal period */
    uint256 public constant MAX_REVEAL_PERIOD = 604_800; // 7 days

    /** @notice The minimum setable quorum votes basis points */
    uint256 public constant MIN_QUORUM_VOTES_BPS = 200; // 200 basis points or 2%

    /** @notice The maximum setable quorum votes basis points */
    uint256 public constant MAX_QUORUM_VOTES_BPS = 2_000; // 2,000 basis points or 20%

    /** @notice The minimum setable appeal period */
    uint256 public constant MIN_APPEAL_PERIOD = 21_600; // 6 hours

    /** @notice The maximum setable appeal period */
    uint256 public constant MAX_APPEAL_PERIOD = 604_800; // 7 days

    /** @notice The minimum setable appeal cost */
    uint256 public constant MIN_APPEAL_COST = 1e18 / 10_000; // 1 ten-thousandth of a token

    /** @notice The maximum setable appeal cost */
    uint256 public constant MAX_APPEAL_COST = 1e18 * 1_000_000; // 1 million tokens

    /** @notice The minimum setable arbitration cost */
    uint256 public constant MIN_ARBITRATION_COST = 1e18 / 10_000; // 1 ten-thousandth of a token

    /** @notice The maximum setable arbitration cost */
    uint256 public constant MAX_ARBITRATION_COST = 1e18 * 1_000_000; // 1 million tokens

    /** @notice ERC20 token used for voting */
    ERC20VotesMintable public votingToken;

    /** @notice The arbitrable contract associated with this arbitrator */
    IArbitrable public arbitrable;

    /** @notice The number of seconds between the vote start and the vote end */
    uint256 public votingPeriod;

    /** @notice The number of seconds after a dispute is executed that a party can appeal the decision */
    uint256 public _appealPeriod;

    /** @notice The number of seconds between the proposal creation and the vote start */
    uint256 public votingDelay;

    /** @notice The number of votes required to reach quorum, in basis points */
    uint256 public quorumVotesBPS;

    /** @notice The number of seconds for the reveal period after voting ends */
    uint256 public revealPeriod;

    /** @notice The total number of disputes created */
    uint256 public disputeCount;

    /** @notice The cost of appealing a dispute */
    uint256 public _appealCost;

    /** @notice The cost of arbitration */
    uint256 public _arbitrationCost;

    /** @notice Ballot receipt record for a voter */
    struct Receipt {
        /** @notice Whether or not a vote has been cast */
        bool hasVoted;
        /** @notice The choice of the voter */
        uint256 choice;
        /** @notice The number of votes the voter had, which were cast */
        uint256 votes;
    }

    /** @notice Possible states that a dispute may be in */
    enum DisputeState {
        Pending, // Dispute is pending and not yet active for voting
        Active, // Dispute is active and open for voting
        Reveal, // Voting has ended, and votes can be revealed
        QuorumNotReached, // Voting and reveal periods have ended, but quorum was not met
        Solved, // Dispute has been solved but not yet executed
        Executed // Dispute has been executed
    }

    /** @notice Struct containing dispute data */
    struct Dispute {
        /** @notice Unique identifier for the dispute */
        uint256 id;
        /** @notice Address of the arbitrable contract that created this dispute */
        address arbitrable;
        /** @notice Timestamp when voting commit period starts */
        uint256 votingStartTime;
        /** @notice Timestamp when voting commit period ends */
        uint256 votingEndTime;
        /** @notice Timestamp when the reveal period ends */
        uint256 revealPeriodEndTime;
        /** @notice Timestamp when the appeal period ends */
        uint256 appealPeriodEndTime;
        /** @notice Number of choices available for voting */
        uint256 choices;
        /** @notice Total number of votes cast */
        uint256 votes;
        /** @notice The winning choice in the dispute */
        IArbitrable.Party ruling;
        /** @notice The votes for each choice */
        mapping(uint256 => uint256) choiceVotes;
        /** @notice Additional data related to the dispute */
        bytes extraData;
        /** @notice Whether the dispute has been executed */
        bool executed;
        /** @notice Block number when the dispute was created */
        uint256 creationBlock;
        /** @notice Number of votes required to reach quorum */
        uint256 quorumVotes;
        /** @notice Total supply of voting tokens at dispute creation */
        uint256 totalSupply;
        /** @notice Mapping of voter addresses to their voting receipts */
        mapping(address => Receipt) receipts;
    }

    /** @notice Mapping of dispute IDs to Dispute structs */
    mapping(uint256 => Dispute) public disputes;
}
