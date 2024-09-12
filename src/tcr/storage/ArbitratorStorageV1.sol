// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IArbitrator } from "../interfaces/IArbitrator.sol";
import { IArbitrable } from "../interfaces/IArbitrable.sol";
import { IVotes } from "@openzeppelin/contracts/governance/utils/IVotes.sol";

/**
 * @title ArbitratorStorageV1
 * @notice Storage contract for the Arbitrator implementation
 */
contract ArbitratorStorageV1 {
    /// @notice The minimum setable voting period
    uint256 public constant MIN_VOTING_PERIOD = 5_760; // About 24 hours

    /// @notice The max setable voting period
    uint256 public constant MAX_VOTING_PERIOD = 80_640; // About 2 weeks

    /// @notice The min setable voting delay
    uint256 public constant MIN_VOTING_DELAY = 1;

    /// @notice The max setable voting delay
    uint256 public constant MAX_VOTING_DELAY = 40_320; // About 1 week

    /// @notice The minimum setable quorum votes basis points
    uint256 public constant MIN_QUORUM_VOTES_BPS = 200; // 200 basis points or 2%

    /// @notice The maximum setable quorum votes basis points
    uint256 public constant MAX_QUORUM_VOTES_BPS = 2_000; // 2,000 basis points or 20%

    // ERC20 token used for voting
    IVotes public votingToken;

    IArbitrable public arbitrable;

    /// @notice Ballot receipt record for a voter
    struct Receipt {
        /// @notice Whether or not a vote has been cast
        bool hasVoted;
        /// @notice Whether or not the voter supports the proposal or abstains
        uint256 choices;
        /// @notice The number of votes the voter had, which were cast
        uint96 votes;
    }
}
