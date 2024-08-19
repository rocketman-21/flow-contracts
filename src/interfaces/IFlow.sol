// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

/**
 * @title IFlowEvents
 * @dev This interface defines the events for the Flow contract.
 */
interface IFlowEvents {
    /**
     * @dev Emitted when a vote is cast for a grant application.
     * @param recipient Address of the recipient of the grant.
     * @param voter Address of the voter.
     * @param memberUnits New member units as a result of the vote.
     * @param bps Basis points of the vote. Proportion of the voters weight that is allocated to the recipient.
     */
    event VoteCast(address indexed recipient, address indexed voter, uint256 memberUnits, uint256 bps);

    /// @notice Emitted when quorum votes basis points is set
    event QuorumVotesBPSSet(uint256 oldQuorumVotesBPS, uint256 newQuorumVotesBPS);

    /// @notice Emitted when the flow is initialized
    event FlowInitialized(address indexed owner, address indexed superToken, address indexed flowImpl);

    /// @notice Emitted when a new grants recipient is set
    event GrantRecipientApproved(address indexed recipient, address indexed approvedBy);

    /// @notice Emitted when the flow rate is updated
    event FlowRateUpdated(int96 oldFlowRate, int96 newFlowRate);

    /// @notice Emitted when min voting power to vote is set
    event MinVotingPowerToVoteSet(uint256 oldMinVotingPowerToVote, uint256 newMinVotingPowerToVote);

    /// @notice Emitted when min voting power to create is set
    event MinVotingPowerToCreateSet(uint256 oldMinVotingPowerToCreate, uint256 newMinVotingPowerToCreate);

    /// @notice Emitted when a new child flow contract is created
    event FlowCreated(address indexed parent, address indexed flow);

    /// @notice Emitted when a new flow implementation is set
    event FlowImplementationSet(address indexed flowImpl);
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

    /// @dev Reverts if the voter's weight is below the minimum required vote weight.
    error WEIGHT_TOO_LOW();

    /// @dev Reverts if the voting signature is invalid
    error INVALID_SIGNATURE();

    /// @dev Reverts if the function caller is not the manager.
    error NOT_MANAGER();

    /// @dev Reverts if the quorum votes basis points exceed the maximum allowed value.
    error INVALID_QUORUM_BPS();

    /// @dev Reverts if voting allocation casts will overflow
    error OVERFLOW();

    /// @dev Reverts if the ERC721 voting token weight is invalid (i.e., 0).
    error INVALID_ERC721_VOTING_WEIGHT();

    /// @dev Reverts if the ERC20 voting token weight is invalid (i.e., 0).
    error INVALID_ERC20_VOTING_WEIGHT();

    /// @dev Reverts if the total vote weights do not meet the required quorum votes for a grant to receive funding.
    error DOES_NOT_MEET_QUORUM();

    /// @dev Reverts if the voting signature has expired
    error SIGNATURE_EXPIRED();

    /// @dev Reverts if address 0 is passed but not allowed
    error ADDRESS_ZERO();

    /// @dev Reverts if bps does not sum to 10000
    error INVALID_BPS_SUM();

    /// @dev Reverts if bps is greater than 10000
    error INVALID_BPS();

    /// @dev Reverts if sender is not manager
    error SENDER_NOT_MANAGER();

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
     * @param quorumVotesBPS The initial quorum votes threshold in basis points.
     * @param minVotingPowerToVote The minimum vote weight that a voter must have to be able to vote.
     * @param minVotingPowerToCreate The minimum vote weight that a voter must have to be able to create a grant.
     */
    struct FlowParams {
        uint256 tokenVoteWeight;
        uint256 quorumVotesBPS;
        uint256 minVotingPowerToVote;
        uint256 minVotingPowerToCreate;
    }

    /**
     * @notice Initializes a token's metadata descriptor
     * @param nounsToken The address of the ERC721Checkpointable contract
     * @param superToken The address of the SuperToken to be used for the pool
     * @param flowImpl The address of the flow implementation contract
     * @param flowParams The parameters for the flow contract
     */
    function initialize(address nounsToken, address superToken, address flowImpl, FlowParams memory flowParams)
        external;
}
