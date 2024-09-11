// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

interface IGeneralizedTCR {
    /* Errors */

    error MUST_BE_ABSENT_TO_BE_ADDED();
    error MUST_BE_REGISTERED_TO_BE_REMOVED();

    /// @notice The item must have a pending request to be challenged.
    error ITEM_MUST_HAVE_PENDING_REQUEST();

    /// @notice Challenges must occur during the challenge period.
    error CHALLENGE_MUST_BE_WITHIN_TIME_LIMIT();

    /// @notice The request should not have already been disputed.
    error REQUEST_ALREADY_DISPUTED();

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
     * @notice Enum representing the parties involved in a dispute
     */
    enum Party {
        None, // Party per default when there is no challenger or requester. Also used for inconclusive ruling.
        Requester, // Party that made the request to change a status.
        Challenger // Party that challenges the request to change a status.
    }

    /**
     * @notice Emitted when a party makes a request, raises a dispute or when a request is resolved
     * @param _itemID The ID of the affected item
     * @param _requestIndex The index of the request
     * @param _roundIndex The index of the round
     * @param _disputed Whether the request is disputed
     * @param _resolved Whether the request is executed
     */
    event ItemStatusChange(
        bytes32 indexed _itemID,
        uint indexed _requestIndex,
        uint indexed _roundIndex,
        bool _disputed,
        bool _resolved
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

    /**
     * @notice Emitted when a party contributes to an appeal
     * @param _itemID The ID of the item
     * @param _contributor The address making the contribution
     * @param _request The index of the request
     * @param _round The index of the round receiving the contribution
     * @param _amount The amount of the contribution
     * @param _side The party receiving the contribution
     */
    event AppealContribution(
        bytes32 indexed _itemID,
        address indexed _contributor,
        uint indexed _request,
        uint _round,
        uint _amount,
        Party _side
    );

    /**
     * @notice Emitted when one of the parties successfully paid its appeal fees
     * @param _itemID The ID of the item
     * @param _request The index of the request
     * @param _round The index of the round
     * @param _side The side that is fully funded
     */
    event HasPaidAppealFee(bytes32 indexed _itemID, uint indexed _request, uint indexed _round, Party _side);
}
