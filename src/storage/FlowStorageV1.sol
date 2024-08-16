// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { IFlow } from "../interfaces/IFlow.sol";
import { IERC721Checkpointable } from "../interfaces/IERC721Checkpointable.sol";

import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import { ISuperfluidPool } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/gdav1/ISuperfluidPool.sol";
import { PoolConfig } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";

/// @notice Flow Storage V1
/// @author rocketman
/// @notice The Flow storage contract
contract FlowStorageV1 {
    /// @notice constant to scale uints into percentages (1e6 == 100%)
    uint256 public constant PERCENTAGE_SCALE = 1e6;

    /// The snapshot block number for voting
    uint256 public snapshotBlock;

    /// The flow implementation
    address public flowImpl;

    /// The mapping of approved recipients
    mapping(address => bool) public approvedRecipients;

    /// The SuperToken used to pay out the grantees
    ISuperToken public superToken;

    /// The Superfluid pool used to distribute the SuperToken
    ISuperfluidPool public pool;

    /// The child flow pools, mapping of recipients to whether or not they are a flow pool
    mapping(address => bool) public isGrantPool;

    /// The mapping of a voter to the member units assigned to each recipient they voted for
    mapping(address => mapping(address => uint256)) public voterToRecipientMemberUnits;

    /// The Superfluid pool configuration
    PoolConfig public poolConfig =
        PoolConfig({ transferabilityForUnitsOwner: false, distributionFromAnyAddress: false });

    /// @notice An account's nonce for gasless votes
    mapping(address => uint256) public nonces;

    // The ERC721 voting token contract used to get the voting power of an account
    IERC721Checkpointable public erc721Votes;

    /// @notice The minimum vote power required to vote on a grant
    uint256 public minVotingPowerToVote;

    /// @notice The minimum voting power required to create a grant
    uint256 public minVotingPowerToCreate;

    /// @notice The basis point number of votes in support of a grant required in order for a quorum to be reached and for a grant to be funded.
    uint256 public quorumVotesBPS;

    // The weight of the 721 voting token
    uint256 public tokenVoteWeight;

    // The weight of the 20 voting token
    uint256 public pointsVoteWeight;

    // The mapping of a voter to a list of votes allocations (recipient, BPS)
    mapping(address => VoteAllocation[]) public votes;

    // Struct to hold the recipient and their corresponding BPS for a vote
    struct VoteAllocation {
        address recipient;
        uint32 bps;
        uint128 memberUnits;
    }
}
