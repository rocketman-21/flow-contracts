// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;
import { IArbitrable } from "./IArbitrable.sol";
import { IManagedFlow } from "../../interfaces/IManagedFlow.sol";
import { IArbitrator } from "./IArbitrator.sol";
import { GeneralizedTCRStorageV1 } from "../storage/GeneralizedTCRStorageV1.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ITCRFactory } from "./ITCRFactory.sol";

interface IGeneralizedTCR {
    /* Errors */

    /// @notice Thrown when attempting to add an item that is not in the 'Absent' state.
    /// @dev This error is used to ensure that only items not currently in the registry can be added.
    error MUST_BE_ABSENT_TO_BE_ADDED();

    /// @notice Thrown when the item data is invalid.
    /// @dev This error is used to ensure that only valid item data can be added to the registry.
    error INVALID_ITEM_DATA();

    /// @notice Thrown when attempting to remove an item that is not in the 'Registered' state.
    /// @dev This error is used to ensure that only items currently in the registry can be removed.
    error MUST_BE_REGISTERED_TO_BE_REMOVED();

    /// @notice The item must have a pending request to be challenged.
    /// @dev This error is used to ensure that only items with a pending request can be challenged.
    error ITEM_MUST_HAVE_PENDING_REQUEST();

    /// @notice Challenges must occur during the challenge period.
    /// @dev This error is used to ensure that only challenges within the specified time limit can be made.
    error CHALLENGE_MUST_BE_WITHIN_TIME_LIMIT();

    /// @notice The request should not have already been disputed.
    /// @dev This error is used to ensure that only requests that have not been disputed can be challenged.
    error REQUEST_ALREADY_DISPUTED();

    /// @notice The party must fully fund their side.
    error MUST_FULLY_FUND_YOUR_SIDE();

    /// @notice The side must be either Requester or Challenger.
    error INVALID_SIDE();

    /// @notice The request must be resolved before executing the ruling.
    error REQUEST_MUST_BE_RESOLVED();

    /// @notice The request must not be already resolved.
    error REQUEST_MUST_NOT_BE_RESOLVED();

    /// @notice The time to challenge the request must pass before execution.
    error CHALLENGE_PERIOD_MUST_PASS();

    /// @notice The request should not be disputed to be executed.
    error REQUEST_MUST_NOT_BE_DISPUTED();

    /// @notice There must be a request to execute the ruling.
    error MUST_BE_A_REQUEST();

    /// @notice The caller must be the governor.
    error MUST_BE_GOVERNOR();

    /// @notice The ruling option provided is invalid.
    error INVALID_RULING_OPTION();

    /// @notice Only the arbitrator can give a ruling.
    error ONLY_ARBITRATOR_CAN_RULE();

    /// @notice The dispute must not already be resolved.
    error DISPUTE_MUST_NOT_BE_RESOLVED();

    /// @notice If address 0 is passed as an argument, the function will revert.
    error ADDRESS_ZERO();

    /* Enums */

    /**
     * @notice Enum representing the status of an item in the registry
     */
    enum Status {
        Absent, // The item is not in the registry.
        Registered, // The item is in the registry.
        RegistrationRequested, // The item has a request to be added to the registry.
        ClearingRequested // The item has a request to be removed from the registry.
    }

    /**
     * @notice Emitted when a party makes a request, raises a dispute or when a request is resolved
     * @param _itemID The ID of the affected item
     * @param _requestIndex The index of the request
     * @param _roundIndex The index of the round
     * @param _disputed Whether the request is disputed
     * @param _resolved Whether the request is executed
     * @param _itemStatus The new status of the item
     */
    event ItemStatusChange(
        bytes32 indexed _itemID,
        uint indexed _requestIndex,
        uint indexed _roundIndex,
        bool _disputed,
        bool _resolved,
        Status _itemStatus
    );

    /**
     * @notice Emitted when someone submits an item for the first time
     * @param _itemID The ID of the new item
     * @param _submitter The address of the requester
     * @param _evidenceGroupID Unique identifier of the evidence group the evidence belongs to
     * @param _data The item data
     */
    event ItemSubmitted(
        bytes32 indexed _itemID,
        address indexed _submitter,
        uint indexed _evidenceGroupID,
        bytes _data
    );

    /**
     * @notice Emitted when someone submits a request
     * @param _itemID The ID of the affected item
     * @param _requestIndex The index of the latest request
     * @param _requestType Whether it is a registration or a removal request
     */
    event RequestSubmitted(bytes32 indexed _itemID, uint indexed _requestIndex, Status indexed _requestType);

    /**
     * @notice Emitted when someone submits a request. This is useful to quickly find an item and request from an evidence event and vice-versa
     * @param _itemID The ID of the affected item
     * @param _requestIndex The index of the latest request
     * @param _evidenceGroupID The evidence group ID used for this request
     */
    event RequestEvidenceGroupID(bytes32 indexed _itemID, uint indexed _requestIndex, uint indexed _evidenceGroupID);
}

interface IFlowTCR is IGeneralizedTCR {
    /**
     * @dev Initializes the FlowTCR contract with necessary parameters and links it to a Flow contract.
     * @param contractParams Struct containing address parameters and interfaces
     * @param tcrParams Struct containing TCR parameters, including deposits, durations, and evidence
     */
    function initialize(
        GeneralizedTCRStorageV1.ContractParams memory contractParams,
        GeneralizedTCRStorageV1.TCRParams memory tcrParams,
        ITCRFactory.TokenEmitterParams memory tokenEmitterParams
    ) external;
}
