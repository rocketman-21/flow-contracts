// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IArbitrator } from "../interfaces/IArbitrator.sol";
import { IArbitrable } from "../interfaces/IArbitrable.sol";

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

    // ERC20 token used for voting
    address public votingToken;
}
