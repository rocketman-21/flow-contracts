// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {FlowStorageV1} from "../storage/FlowStorageV1.sol";

/**
 * @title IFlowEvents
 * @dev This interface defines the events for the Flow contract.
 */
interface IFlowEvents {
    /**
     * @dev Emitted when a vote is cast for a grant application.
     * @param recipientId Id of the recipient of the grant.
     * @param tokenId TokenId owned by the voter.
     * @param memberUnits New member units as a result of the vote.
     * @param bps Basis points of the vote. Proportion of the voters weight that is allocated to the recipient.
     */
    event VoteCast(uint256 indexed recipientId, uint256 indexed tokenId, uint256 memberUnits, uint256 bps);

    /// @notice Emitted when the flow is initialized
    event FlowInitialized(address indexed owner, address indexed superToken, address indexed flowImpl);

    /// @notice Emitted when a new grants recipient is set
    event RecipientCreated(address indexed recipient, address indexed approvedBy);

    /// @notice Emitted when the flow rate is updated
    event FlowRateUpdated(int96 oldFlowRate, int96 newFlowRate);

    /// @notice Emitted when a new child flow contract is created
    event FlowCreated(address indexed parent, address indexed flow);

    /// @notice Emitted when a new flow implementation is set
    event FlowImplementationSet(address indexed flowImpl);

    /// @notice Emitted when a recipient is removed
    event RecipientRemoved(address indexed recipient, uint256 indexed recipientId);
}

/**
 * @title IFlow
 * @dev This interface defines the methods for the Flow contract.
 */
interface IFlow is IFlowEvents {
    ///                                                          ///
    ///                           ERRORS                         ///
    ///                                                          ///

    /// @dev Reverts if the lengths of the provided arrays do not match.
    error ARRAY_LENGTH_MISMATCH();

    /// @dev Reverts if unit updates fail
    error UNITS_UPDATE_FAILED();

    /// @dev Reverts if the recipient is not approved.
    error NOT_APPROVED_RECIPIENT();

    /// @dev Reverts if the token vote weight is invalid (i.e., 0).
    error INVALID_VOTE_WEIGHT();

    /// @dev Reverts if the voter's weight is below the minimum required vote weight.
    error WEIGHT_TOO_LOW();

    /// @dev Reverts if invalid recipientId is passed
    error INVALID_RECIPIENT_ID();

    /// @dev Reverts if the voting signature is invalid
    error INVALID_SIGNATURE();

    /// @dev Reverts if the function caller is not the manager.
    error NOT_MANAGER();

    /// @dev Reverts if voting allocation casts will overflow
    error OVERFLOW();

    /// @dev Reverts if the ERC721 voting token weight is invalid (i.e., 0).
    error INVALID_ERC721_VOTING_WEIGHT();

    /// @dev Reverts if the ERC20 voting token weight is invalid (i.e., 0).
    error INVALID_ERC20_VOTING_WEIGHT();

    /// @dev Reverts if the voting signature has expired
    error SIGNATURE_EXPIRED();

    /// @dev Reverts if address 0 is passed but not allowed
    error ADDRESS_ZERO();

    /// @dev Reverts if bps does not sum to 10000
    error INVALID_BPS_SUM();

    /// @dev Reverts if bps is greater than 10000
    error INVALID_BPS();

    /// @dev Reverts if metadata is invalid
    error INVALID_METADATA();

    /// @dev Reverts if sender is not manager
    error SENDER_NOT_MANAGER();

    /// @dev Reverts if recipient is already approved
    error RECIPIENT_ALREADY_REMOVED();

    /// @dev Reverts if msg.sender is not owner of tokenId when voting
    error NOT_TOKEN_OWNER();

    /// @dev Array lengths of recipients & percentAllocations don't match (`recipientsLength` != `allocationsLength`)
    /// @param recipientsLength Length of recipients array
    /// @param allocationsLength Length of percentAllocations array
    error RECIPIENTS_ALLOCATIONS_MISMATCH(uint256 recipientsLength, uint256 allocationsLength);

    /// @dev Reverts if no recipients are specified
    error TOO_FEW_RECIPIENTS();

    /// @dev Reverts if voting allocation is not positive
    error ALLOCATION_MUST_BE_POSITIVE();


    ///                                                          ///
    ///                         STRUCTS                          ///
    ///                                                          ///

    // Struct representing a voter and their weight for a specific grant application.
    struct Vote {
        address voterAddress;
        uint256 weight;
    }

    /**
     * @notice Structure to hold the parameters for initializing a Flow contract.
     * @param tokenVoteWeight The voting weight of the individual ERC721 tokens.
     */
    struct FlowParams {
        uint256 tokenVoteWeight;
    }

    /**
     * @notice Initializes a token's metadata descriptor
     * @param nounsToken The address of the ERC721Checkpointable contract
     * @param superToken The address of the SuperToken to be used for the pool
     * @param flowImpl The address of the flow implementation contract
     * @param manager The address of the flow manager
     * @param parent The address of the parent flow contract (optional)
     * @param flowParams The parameters for the flow contract
     */
    function initialize(address nounsToken, address superToken, address flowImpl, address manager, address parent, FlowParams memory flowParams, FlowStorageV1.RecipientMetadata memory metadata)
        external;
}
