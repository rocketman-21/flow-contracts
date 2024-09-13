// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import { IArbitrator } from "../interfaces/IArbitrator.sol";
import { IGeneralizedTCR } from "../interfaces/IGeneralizedTCR.sol";
import { IArbitrable } from "../interfaces/IArbitrable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title GeneralizedTCRStorageV1
 * @author rocketman
 * @notice The GeneralizedTCR storage contract
 */
contract GeneralizedTCRStorageV1 {
    /* Structs */

    /**
     * @notice Struct representing an item in the registry
     */
    struct Item {
        bytes data; // The data describing the item.
        IGeneralizedTCR.Status status; // The current status of the item.
        Request[] requests; // List of status change requests made for the item in the form requests[requestID].
    }

    /**
     * @notice Struct representing a request to change the status of an item
     */
    struct Request {
        bool disputed; // True if a dispute was raised.
        uint256 disputeID; // ID of the dispute, if any.
        uint256 submissionTime; // Time when the request was made. Used to track when the challenge period ends.
        bool resolved; // True if the request was executed and/or any raised disputes were resolved.
        address[3] parties; // Address of requester and challenger, if any, in the form parties[party].
        Round[] rounds; // Tracks each round of a dispute in the form rounds[roundID].
        IArbitrable.Party ruling; // The final ruling given, if any.
        IArbitrator arbitrator; // The arbitrator trusted to solve disputes for this request.
        bytes arbitratorExtraData; // The extra data for the trusted arbitrator of this request.
        uint256 metaEvidenceID; // The meta evidence to be used in a dispute for this case.
    }

    /**
     * @notice Struct representing a round in a dispute
     */
    struct Round {
        uint256[3] amountPaid; // Tracks the sum paid for each Party in this round. Includes arbitration fees, fee stakes and deposits.
        bool[3] hasPaid; // True if the Party has fully paid its fee in this round.
        uint256 feeRewards; // Sum of reimbursable fees and stake rewards available to the parties that made contributions to the side that ultimately wins a dispute.
        mapping(address => uint256[3]) contributions; // Maps contributors to their contributions for each side in the form contributions[address][party].
    }

    /* Storage */

    /**
     * @notice The arbitrator contract
     */
    IArbitrator public arbitrator;
    /**
     * @notice Extra data for the arbitrator contract
     */
    bytes public arbitratorExtraData;

    /**
     * @notice The amount of non-zero choices the arbitrator can give
     */
    uint256 public constant RULING_OPTIONS = 2;

    /**
     * @notice The address that can make changes to the parameters of the contract
     */
    address public governor;

    /**
     * @notice The address of the ERC20 contract used for deposits
     */
    IERC20 public erc20;

    /**
     * @notice The base deposit to submit an item
     */
    uint256 public submissionBaseDeposit;
    /**
     * @notice The base deposit to remove an item
     */
    uint256 public removalBaseDeposit;
    /**
     * @notice The base deposit to challenge a submission
     */
    uint256 public submissionChallengeBaseDeposit;
    /**
     * @notice The base deposit to challenge a removal request
     */
    uint256 public removalChallengeBaseDeposit;
    /**
     * @notice The time after which a request becomes executable if not challenged
     */
    uint256 public challengePeriodDuration;
    /**
     * @notice The number of times the meta evidence has been updated. Used to track the latest meta evidence ID
     */
    uint256 public metaEvidenceUpdates;

    /**
     * @notice Multiplier for calculating the fee stake paid by the party that won the previous round
     */
    uint256 public winnerStakeMultiplier;
    /**
     * @notice Multiplier for calculating the fee stake paid by the party that lost the previous round
     */
    uint256 public loserStakeMultiplier;
    /**
     * @notice Multiplier for calculating the fee stake that must be paid in the case where arbitrator refused to arbitrate
     */
    uint256 public sharedStakeMultiplier;
    /**
     * @notice Divisor parameter for multipliers
     */
    uint256 public constant MULTIPLIER_DIVISOR = 10000;

    /**
     * @notice List of IDs of all submitted items
     */
    bytes32[] public itemList;
    /**
     * @notice Maps the item ID to its data in the form items[_itemID]
     */
    mapping(bytes32 => Item) public items;
    /**
     * @notice Maps a dispute ID to the ID of the item with the disputed request in the form arbitratorDisputeIDToItem[arbitrator][disputeID]
     */
    mapping(address => mapping(uint256 => bytes32)) public arbitratorDisputeIDToItem;
    /**
     * @notice Maps an item's ID to its position in the list in the form itemIDtoIndex[itemID]
     */
    mapping(bytes32 => uint256) public itemIDtoIndex;
}
