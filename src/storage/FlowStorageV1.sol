// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {IFlow} from "../interfaces/IFlow.sol";
import {IERC721Checkpointable} from "../interfaces/IERC721Checkpointable.sol";

import {ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import {ISuperfluidPool} from
    "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/gdav1/ISuperfluidPool.sol";
import {PoolConfig} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";

/// @notice Flow Storage V1
/// @author rocketman
/// @notice The Flow storage contract
contract FlowStorageV1 {
    /// @notice constant to scale uints into percentages (1e6 == 100%)
    uint256 public constant PERCENTAGE_SCALE = 1e6;

    /// The flow implementation
    address public flowImpl;

    /// Counter for recipients added
    uint256 public recipientCount;

    /// The mapping of recipients
    /// [recipientCount++] = new FlowRecipient()
    mapping(uint256 => FlowRecipient) public recipients;

    /// The SuperToken used to pay out the grantees
    ISuperToken public superToken;

    /// The Superfluid pool used to distribute the SuperToken
    ISuperfluidPool public pool;

    /// The mapping of a tokenId to the member units assigned to each recipient they voted for
    mapping(uint256 => mapping(address => uint256)) public tokenIdToRecipientMemberUnits;

    /// The Superfluid pool configuration
    PoolConfig public poolConfig = PoolConfig({transferabilityForUnitsOwner: false, distributionFromAnyAddress: false});

    // The ERC721 voting token contract used to get the voting power of an account
    IERC721Checkpointable public erc721Votes;

    // The weight of the 721 voting token
    uint256 public tokenVoteWeight;

    // The mapping of a token to a list of votes allocations (recipient, BPS)
    mapping(uint256 => VoteAllocation[]) public votes;

    // Struct to hold the recipientId and their corresponding BPS for a vote
    struct VoteAllocation {
        uint256 recipientId;
        uint32 bps;
        uint128 memberUnits;
    }

    // Enum to handle type of grant recipient, either address or flow contract
    // Helpful to set a flow rate if recipient is flow contract
    enum RecipientType {
        ExternalAccount,
        FlowContract
    }

    //todo change recipient prefix in subfields
    // Struct to handle potential recipients
    struct FlowRecipient {
        // the account to stream funds to
        address recipient;
        // whether or not the grant is currently approved
        bool approved;
        // the type of recipient, either account or flow contract
        RecipientType recipientType;
        // the id of the recipient
        uint256 recipientId;
    }
}
