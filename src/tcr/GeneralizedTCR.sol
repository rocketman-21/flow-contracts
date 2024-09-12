// SPDX-License-Identifier: GPL-3.0-or-later
// GeneralizedTCR.sol is a modified version of Kleros' GeneralizedTCR.sol:
// https://github.com/kleros/tcr
//
// GeneralizedTCR.sol source code Copyright Kleros licensed under the MIT license.
// With modifications by rocketman for the Nouns Flows project.

pragma solidity ^0.8.27;

import { IArbitrable } from "./interfaces/IArbitrable.sol";
import { IArbitrator } from "./interfaces/IArbitrator.sol";
import { IEvidence } from "./interfaces/IEvidence.sol";
import { IGeneralizedTCR } from "./interfaces/IGeneralizedTCR.sol";
import { CappedMath } from "./utils/CappedMath.sol";
import { GeneralizedTCRStorageV1 } from "./storage/GeneralizedTCRStorageV1.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/**
 *  @title GeneralizedTCR
 *  This contract is a curated registry for any types of items. Just like a TCR contract it features the request-challenge protocol and appeal fees crowdfunding.
 */
contract GeneralizedTCR is
    IArbitrable,
    IEvidence,
    IGeneralizedTCR,
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    ReentrancyGuardUpgradeable,
    GeneralizedTCRStorageV1
{
    using CappedMath for uint256;
    using SafeERC20 for IERC20;
    /**
     *  @dev Deploy the arbitrable curated registry.
     *  @param _arbitrator Arbitrator to resolve potential disputes. The arbitrator is trusted to support appeal periods and not reenter.
     *  @param _arbitratorExtraData Extra data for the trusted arbitrator contract.
     *  @param _registrationMetaEvidence The URI of the meta evidence object for registration requests.
     *  @param _clearingMetaEvidence The URI of the meta evidence object for clearing requests.
     *  @param _governor The trusted governor of this contract.
     *  @param _erc20 The address of the ERC20 token contract used for deposits.
     *  @param _submissionBaseDeposit The base deposit to submit an item.
     *  @param _removalBaseDeposit The base deposit to remove an item.
     *  @param _submissionChallengeBaseDeposit The base deposit to challenge a submission.
     *  @param _removalChallengeBaseDeposit The base deposit to challenge a removal request.
     *  @param _challengePeriodDuration The time in seconds parties have to challenge a request.
     *  @param _stakeMultipliers Multipliers of the arbitration cost in basis points (see MULTIPLIER_DIVISOR) as follows:
     *  - The multiplier applied to each party's fee stake for a round when there is no winner/loser in the previous round (e.g. when the arbitrator refused to arbitrate).
     *  - The multiplier applied to the winner's fee stake for the subsequent round.
     *  - The multiplier applied to the loser's fee stake for the subsequent round.
     */
    constructor(
        IArbitrator _arbitrator,
        bytes memory _arbitratorExtraData,
        string memory _registrationMetaEvidence,
        string memory _clearingMetaEvidence,
        address _governor,
        IERC20 _erc20,
        uint _submissionBaseDeposit,
        uint _removalBaseDeposit,
        uint _submissionChallengeBaseDeposit,
        uint _removalChallengeBaseDeposit,
        uint _challengePeriodDuration,
        uint[3] memory _stakeMultipliers
    ) {
        emit MetaEvidence(0, _registrationMetaEvidence);
        emit MetaEvidence(1, _clearingMetaEvidence);
        if (address(_arbitrator) == address(0)) revert ADDRESS_ZERO();
        if (address(_erc20) == address(0)) revert ADDRESS_ZERO();
        if (_governor == address(0)) revert ADDRESS_ZERO();

        arbitrator = _arbitrator;
        arbitratorExtraData = _arbitratorExtraData;
        governor = _governor;
        erc20 = _erc20;
        submissionBaseDeposit = _submissionBaseDeposit;
        removalBaseDeposit = _removalBaseDeposit;
        submissionChallengeBaseDeposit = _submissionChallengeBaseDeposit;
        removalChallengeBaseDeposit = _removalChallengeBaseDeposit;
        challengePeriodDuration = _challengePeriodDuration;
        sharedStakeMultiplier = _stakeMultipliers[0];
        winnerStakeMultiplier = _stakeMultipliers[1];
        loserStakeMultiplier = _stakeMultipliers[2];
    }

    /* External and Public */

    // ************************ //
    // *       Requests       * //
    // ************************ //

    /** @dev Submit a request to register an item. Must have approved this contract to transfer at least `submissionBaseDeposit` + `arbitrationCost` ERC20 tokens.
     *  @param _item The data describing the item.
     */
    function addItem(bytes calldata _item) external nonReentrant {
        bytes32 itemID = keccak256(_item);
        if (items[itemID].status != Status.Absent) revert MUST_BE_ABSENT_TO_BE_ADDED();
        _requestStatusChange(_item, submissionBaseDeposit);
    }

    /** @dev Submit a request to remove an item from the list. Must have approved this contract to transfer at least `removalBaseDeposit` + `arbitrationCost` ERC20 tokens.
     *  @param _itemID The ID of the item to remove.
     *  @param _evidence A link to an evidence using its URI. Ignored if not provided.
     */
    function removeItem(bytes32 _itemID, string calldata _evidence) external nonReentrant {
        if (items[_itemID].status != Status.Registered) revert MUST_BE_REGISTERED_TO_BE_REMOVED();
        Item storage item = items[_itemID];

        // Emit evidence if it was provided.
        if (bytes(_evidence).length > 0) {
            // Using `length` instead of `length - 1` because a new request will be added on requestStatusChange().
            uint requestIndex = item.requests.length;
            uint evidenceGroupID = uint(keccak256(abi.encodePacked(_itemID, requestIndex)));

            emit Evidence(arbitrator, evidenceGroupID, msg.sender, _evidence);
        }

        _requestStatusChange(item.data, removalBaseDeposit);
    }

    /** @dev Challenges the request of the item. Must have approved this contract to transfer at least `challengeBaseDeposit` + `arbitrationCost` ERC20 tokens.
     *  @param _itemID The ID of the item which request to challenge.
     *  @param _evidence A link to an evidence using its URI. Ignored if not provided.
     */
    function challengeRequest(bytes32 _itemID, string calldata _evidence) external nonReentrant {
        Item storage item = items[_itemID];

        if (item.status != Status.RegistrationRequested && item.status != Status.ClearingRequested)
            revert ITEM_MUST_HAVE_PENDING_REQUEST();

        Request storage request = item.requests[item.requests.length - 1];
        if (block.timestamp - request.submissionTime > challengePeriodDuration)
            revert CHALLENGE_MUST_BE_WITHIN_TIME_LIMIT();
        if (request.disputed) revert REQUEST_ALREADY_DISPUTED();

        request.parties[uint(Party.Challenger)] = msg.sender;

        Round storage round = request.rounds[0];
        uint arbitrationCost = request.arbitrator.arbitrationCost(request.arbitratorExtraData);
        uint challengerBaseDeposit = item.status == Status.RegistrationRequested
            ? submissionChallengeBaseDeposit
            : removalChallengeBaseDeposit;
        uint totalCost = arbitrationCost.addCap(challengerBaseDeposit);
        _contribute(round, Party.Challenger, msg.sender, totalCost, totalCost);
        if (round.amountPaid[uint(Party.Challenger)] < totalCost) revert MUST_FULLY_FUND_YOUR_SIDE();
        round.hasPaid[uint(Party.Challenger)] = true;

        // Raise a dispute.

        // approve arbitrator to spend the ERC20 tokens for the arbitration cost only, not for the challenger base deposit
        erc20.safeIncreaseAllowance(address(request.arbitrator), arbitrationCost);

        // create dispute - arbitrator will transferFrom() the ERC20 tokens to itself
        // changed from Kleros' GeneralizedTCR.sol to not send ETH to arbitrator
        request.disputeID = request.arbitrator.createDispute(RULING_OPTIONS, request.arbitratorExtraData);

        arbitratorDisputeIDToItem[address(request.arbitrator)][request.disputeID] = _itemID;
        request.disputed = true;
        request.rounds.push(); // prepare for any new appeals given the new dispute
        round.feeRewards = round.feeRewards.subCap(arbitrationCost);

        uint evidenceGroupID = uint(keccak256(abi.encodePacked(_itemID, item.requests.length - 1)));
        emit Dispute(request.arbitrator, request.disputeID, request.metaEvidenceID, evidenceGroupID);

        if (bytes(_evidence).length > 0) {
            emit Evidence(request.arbitrator, evidenceGroupID, msg.sender, _evidence);
        }
    }

    /** @dev Takes up to the total amount required to fund a side of an appeal. Reimburses the rest. Creates an appeal if both sides are fully funded.
     *  @param _itemID The ID of the item which request to fund.
     *  @param _side The recipient of the contribution.
     *  @param _erc20Amount The amount of ERC20 tokens to use to fund the appeal.
     */
    function fundAppeal(bytes32 _itemID, Party _side, uint _erc20Amount) external nonReentrant {
        if (_side != Party.Requester && _side != Party.Challenger) revert INVALID_SIDE();
        if (items[_itemID].status != Status.RegistrationRequested && items[_itemID].status != Status.ClearingRequested)
            revert ITEM_MUST_HAVE_PENDING_REQUEST();

        Request storage request = items[_itemID].requests[items[_itemID].requests.length - 1];
        if (!request.disputed) revert A_DISPUTE_MUST_BE_RAISED_TO_FUND_AN_APPEAL();
        (uint appealPeriodStart, uint appealPeriodEnd) = request.arbitrator.appealPeriod(request.disputeID);
        if (block.timestamp < appealPeriodStart || block.timestamp >= appealPeriodEnd)
            revert CONTRIBUTIONS_MUST_BE_MADE_WITHIN_THE_APPEAL_PERIOD();

        uint multiplier;
        {
            Party winner = Party(request.arbitrator.currentRuling(request.disputeID));
            Party loser;
            if (winner == Party.Requester) loser = Party.Challenger;
            else if (winner == Party.Challenger) loser = Party.Requester;
            if (_side == loser && (block.timestamp - appealPeriodStart >= (appealPeriodEnd - appealPeriodStart) / 2))
                revert LOSER_MUST_CONTRIBUTE_DURING_FIRST_HALF_OF_APPEAL_PERIOD();

            if (_side == winner) multiplier = winnerStakeMultiplier;
            else if (_side == loser) multiplier = loserStakeMultiplier;
            else multiplier = sharedStakeMultiplier;
        }

        Round storage round = request.rounds[request.rounds.length - 1];
        uint appealCost = request.arbitrator.appealCost(request.disputeID, request.arbitratorExtraData);
        uint totalCost = appealCost.addCap((appealCost.mulCap(multiplier)) / MULTIPLIER_DIVISOR);
        uint contribution = _contribute(round, _side, msg.sender, _erc20Amount, totalCost);

        emit AppealContribution(
            _itemID,
            msg.sender,
            items[_itemID].requests.length - 1,
            request.rounds.length - 1,
            contribution,
            _side
        );

        if (round.amountPaid[uint(_side)] >= totalCost) {
            round.hasPaid[uint(_side)] = true;
            emit HasPaidAppealFee(_itemID, items[_itemID].requests.length - 1, request.rounds.length - 1, _side);
        }

        // Raise appeal if both sides are fully funded.
        if (round.hasPaid[uint(Party.Challenger)] && round.hasPaid[uint(Party.Requester)]) {
            // increase allowance for arbitrator to spend the ERC20 tokens
            erc20.safeIncreaseAllowance(address(request.arbitrator), appealCost);

            // appeal - arbitrator will transferFrom() the ERC20 tokens to itself
            request.arbitrator.appeal(request.disputeID, request.arbitratorExtraData);

            request.rounds.push(); // if appeal is successfully funded, a new round is created
            round.feeRewards = round.feeRewards.subCap(appealCost);
        }
    }

    /** @dev Reimburses contributions if no disputes were raised. If a dispute was raised, sends the fee stake rewards and reimbursements proportionally to the contributions made to the winner of a dispute.
     *  @param _beneficiary The address that made contributions to a request.
     *  @param _itemID The ID of the item submission to withdraw from.
     *  @param _request The request from which to withdraw from.
     *  @param _round The round from which to withdraw from.
     */
    function withdrawFeesAndRewards(
        address _beneficiary,
        bytes32 _itemID,
        uint _request,
        uint _round
    ) public nonReentrant {
        Item storage item = items[_itemID];
        Request storage request = item.requests[_request];
        Round storage round = request.rounds[_round];
        if (!request.resolved) revert REQUEST_MUST_BE_RESOLVED();

        uint reward;
        if (!round.hasPaid[uint(Party.Requester)] || !round.hasPaid[uint(Party.Challenger)]) {
            // Reimburse if not enough fees were raised to appeal the ruling.
            reward =
                round.contributions[_beneficiary][uint(Party.Requester)] +
                round.contributions[_beneficiary][uint(Party.Challenger)];
        } else if (request.ruling == Party.None) {
            // Reimburse unspent fees proportionally if there is no winner or loser.
            uint rewardRequester = round.amountPaid[uint(Party.Requester)] > 0
                ? (round.contributions[_beneficiary][uint(Party.Requester)] * round.feeRewards) /
                    (round.amountPaid[uint(Party.Challenger)] + round.amountPaid[uint(Party.Requester)])
                : 0;
            uint rewardChallenger = round.amountPaid[uint(Party.Challenger)] > 0
                ? (round.contributions[_beneficiary][uint(Party.Challenger)] * round.feeRewards) /
                    (round.amountPaid[uint(Party.Challenger)] + round.amountPaid[uint(Party.Requester)])
                : 0;

            reward = rewardRequester + rewardChallenger;
        } else {
            // Reward the winner.
            reward = round.amountPaid[uint(request.ruling)] > 0
                ? (round.contributions[_beneficiary][uint(request.ruling)] * round.feeRewards) /
                    round.amountPaid[uint(request.ruling)]
                : 0;
        }
        round.contributions[_beneficiary][uint(Party.Requester)] = 0;
        round.contributions[_beneficiary][uint(Party.Challenger)] = 0;

        // send ERC20 tokens to beneficiary
        erc20.safeTransfer(_beneficiary, reward);
    }

    /** @dev Executes an unchallenged request if the challenge period has passed.
     *  @param _itemID The ID of the item to execute.
     */
    function executeRequest(bytes32 _itemID) external nonReentrant {
        Item storage item = items[_itemID];
        Request storage request = item.requests[item.requests.length - 1];
        if (block.timestamp - request.submissionTime <= challengePeriodDuration) revert CHALLENGE_PERIOD_MUST_PASS();
        if (request.disputed) revert REQUEST_MUST_NOT_BE_DISPUTED();

        if (item.status == Status.RegistrationRequested) item.status = Status.Registered;
        else if (item.status == Status.ClearingRequested) item.status = Status.Absent;
        else revert MUST_BE_A_REQUEST();

        request.resolved = true;
        emit ItemStatusChange(_itemID, item.requests.length - 1, request.rounds.length - 1, false, true);

        withdrawFeesAndRewards(request.parties[uint(Party.Requester)], _itemID, item.requests.length - 1, 0); // Automatically withdraw for the requester.
    }

    /** @dev Give a ruling for a dispute. Can only be called by the arbitrator. TRUSTED.
     *  Accounts for the situation where the winner loses a case due to paying less appeal fees than expected.
     *  @param _disputeID ID of the dispute in the arbitrator contract.
     *  @param _ruling Ruling given by the arbitrator. Note that 0 is reserved for "Refused to arbitrate".
     */
    function rule(uint _disputeID, uint _ruling) public nonReentrant {
        Party resultRuling = Party(_ruling);
        bytes32 itemID = arbitratorDisputeIDToItem[msg.sender][_disputeID];
        Item storage item = items[itemID];

        Request storage request = item.requests[item.requests.length - 1];
        Round storage round = request.rounds[request.rounds.length - 1];
        if (_ruling > RULING_OPTIONS) revert INVALID_RULING_OPTION();
        if (address(request.arbitrator) != msg.sender) revert ONLY_ARBITRATOR_CAN_RULE();
        if (request.resolved) revert REQUEST_MUST_NOT_BE_RESOLVED();

        // The ruling is inverted if the loser paid its fees.
        if (round.hasPaid[uint(Party.Requester)] == true)
            // If one side paid its fees, the ruling is in its favor. Note that if the other side had also paid, an appeal would have been created.
            resultRuling = Party.Requester;
        else if (round.hasPaid[uint(Party.Challenger)] == true) resultRuling = Party.Challenger;

        emit Ruling(IArbitrator(msg.sender), _disputeID, uint(resultRuling));
        _executeRuling(_disputeID, uint(resultRuling));
    }

    /** @dev Submit a reference to evidence. EVENT.
     *  @param _itemID The ID of the item which the evidence is related to.
     *  @param _evidence A link to an evidence using its URI.
     */
    function submitEvidence(bytes32 _itemID, string calldata _evidence) external nonReentrant {
        Item storage item = items[_itemID];
        Request storage request = item.requests[item.requests.length - 1];
        if (request.resolved) revert DISPUTE_MUST_NOT_BE_RESOLVED();

        uint evidenceGroupID = uint(keccak256(abi.encodePacked(_itemID, item.requests.length - 1)));
        emit Evidence(request.arbitrator, evidenceGroupID, msg.sender, _evidence);
    }

    // ************************ //
    // *      Governance      * //
    // ************************ //

    /** @dev Change the duration of the challenge period.
     *  @param _challengePeriodDuration The new duration of the challenge period.
     */
    function changeTimeToChallenge(uint _challengePeriodDuration) external onlyGovernor {
        challengePeriodDuration = _challengePeriodDuration;
    }

    /** @dev Change the base amount required as a deposit to submit an item.
     *  @param _submissionBaseDeposit The new base amount of wei required to submit an item.
     */
    function changeSubmissionBaseDeposit(uint _submissionBaseDeposit) external onlyGovernor {
        submissionBaseDeposit = _submissionBaseDeposit;
    }

    /** @dev Change the base amount required as a deposit to remove an item.
     *  @param _removalBaseDeposit The new base amount of wei required to remove an item.
     */
    function changeRemovalBaseDeposit(uint _removalBaseDeposit) external onlyGovernor {
        removalBaseDeposit = _removalBaseDeposit;
    }

    /** @dev Change the base amount required as a deposit to challenge a submission.
     *  @param _submissionChallengeBaseDeposit The new base amount of wei required to challenge a submission.
     */
    function changeSubmissionChallengeBaseDeposit(uint _submissionChallengeBaseDeposit) external onlyGovernor {
        submissionChallengeBaseDeposit = _submissionChallengeBaseDeposit;
    }

    /** @dev Change the base amount required as a deposit to challenge a removal request.
     *  @param _removalChallengeBaseDeposit The new base amount of wei required to challenge a removal request.
     */
    function changeRemovalChallengeBaseDeposit(uint _removalChallengeBaseDeposit) external onlyGovernor {
        removalChallengeBaseDeposit = _removalChallengeBaseDeposit;
    }

    /** @dev Change the governor of the curated registry.
     *  @param _governor The address of the new governor.
     */
    function changeGovernor(address _governor) external onlyGovernor {
        governor = _governor;
    }

    /** @dev Change the proportion of arbitration fees that must be paid as fee stake by parties when there is no winner or loser.
     *  @param _sharedStakeMultiplier Multiplier of arbitration fees that must be paid as fee stake. In basis points.
     */
    function changeSharedStakeMultiplier(uint _sharedStakeMultiplier) external onlyGovernor {
        sharedStakeMultiplier = _sharedStakeMultiplier;
    }

    /** @dev Change the proportion of arbitration fees that must be paid as fee stake by the winner of the previous round.
     *  @param _winnerStakeMultiplier Multiplier of arbitration fees that must be paid as fee stake. In basis points.
     */
    function changeWinnerStakeMultiplier(uint _winnerStakeMultiplier) external onlyGovernor {
        winnerStakeMultiplier = _winnerStakeMultiplier;
    }

    /** @dev Change the proportion of arbitration fees that must be paid as fee stake by the party that lost the previous round.
     *  @param _loserStakeMultiplier Multiplier of arbitration fees that must be paid as fee stake. In basis points.
     */
    function changeLoserStakeMultiplier(uint _loserStakeMultiplier) external onlyGovernor {
        loserStakeMultiplier = _loserStakeMultiplier;
    }

    /** @dev Change the arbitrator to be used for disputes that may be raised. The arbitrator is trusted to support appeal periods and not reenter.
     *  @param _arbitrator The new trusted arbitrator to be used in disputes.
     *  @param _arbitratorExtraData The extra data used by the new arbitrator.
     */
    function changeArbitrator(IArbitrator _arbitrator, bytes calldata _arbitratorExtraData) external onlyGovernor {
        arbitrator = _arbitrator;
        arbitratorExtraData = _arbitratorExtraData;
    }

    /** @dev Update the meta evidence used for disputes.
     *  @param _registrationMetaEvidence The meta evidence to be used for future registration request disputes.
     *  @param _clearingMetaEvidence The meta evidence to be used for future clearing request disputes.
     */
    function changeMetaEvidence(
        string calldata _registrationMetaEvidence,
        string calldata _clearingMetaEvidence
    ) external onlyGovernor {
        metaEvidenceUpdates++;
        emit MetaEvidence(2 * metaEvidenceUpdates, _registrationMetaEvidence);
        emit MetaEvidence(2 * metaEvidenceUpdates + 1, _clearingMetaEvidence);
    }

    /* Internal */

    /** @dev Submit a request to change item's status. Accepts enough ERC20 tokens to cover the deposit.
     *  @param _item The data describing the item.
     *  @param _baseDeposit The base deposit for the request.
     */
    function _requestStatusChange(bytes memory _item, uint _baseDeposit) internal {
        bytes32 itemID = keccak256(_item);
        Item storage item = items[itemID];

        // Using `length` instead of `length - 1` as index because a new request will be added.
        uint evidenceGroupID = uint(keccak256(abi.encodePacked(itemID, item.requests.length)));
        if (item.requests.length == 0) {
            item.data = _item;
            itemList.push(itemID);
            itemIDtoIndex[itemID] = itemList.length - 1;

            emit ItemSubmitted(itemID, msg.sender, evidenceGroupID, item.data);
        }

        Request storage request = item.requests.push();
        if (item.status == Status.Absent) {
            item.status = Status.RegistrationRequested;
            request.metaEvidenceID = 2 * metaEvidenceUpdates;
        } else if (item.status == Status.Registered) {
            item.status = Status.ClearingRequested;
            request.metaEvidenceID = 2 * metaEvidenceUpdates + 1;
        }

        request.parties[uint(Party.Requester)] = msg.sender;
        request.submissionTime = block.timestamp;
        request.arbitrator = arbitrator;
        request.arbitratorExtraData = arbitratorExtraData;

        Round storage round = request.rounds.push();

        uint arbitrationCost = request.arbitrator.arbitrationCost(request.arbitratorExtraData);
        uint totalCost = arbitrationCost.addCap(_baseDeposit);
        _contribute(round, Party.Requester, msg.sender, totalCost, totalCost);
        if (round.amountPaid[uint(Party.Requester)] < totalCost) revert MUST_FULLY_FUND_YOUR_SIDE();
        round.hasPaid[uint(Party.Requester)] = true;

        emit ItemStatusChange(itemID, item.requests.length - 1, request.rounds.length - 1, false, false);
        emit RequestSubmitted(itemID, item.requests.length - 1, item.status);
        emit RequestEvidenceGroupID(itemID, item.requests.length - 1, evidenceGroupID);
    }

    /** @dev Returns the contribution value and remainder from available ERC20 tokens and required amount.
     *  @param _available The amount of ERC20 tokens available for the contribution.
     *  @param _requiredAmount The amount of ERC20 tokens required for the contribution.
     *  @return taken The amount of ERC20 tokens taken.
     *  @return remainder The amount of ERC20 tokens left from the contribution.
     */
    function _calculateContribution(
        uint _available,
        uint _requiredAmount
    ) internal pure returns (uint taken, uint remainder) {
        // Take whatever is available, return 0 as leftover ERC20 tokens.
        if (_requiredAmount > _available) return (_available, 0);
        // Take the required amount, return the remaining ERC20 tokens.
        else return (_requiredAmount, _available - _requiredAmount);
    }

    /** @dev Make a fee contribution.
     *  @param _round The round to contribute.
     *  @param _side The side for which to contribute.
     *  @param _contributor The contributor.
     *  @param _amount The amount contributed.
     *  @param _totalRequired The total amount required for this side.
     *  @return The amount of appeal fees contributed.
     */
    function _contribute(
        Round storage _round,
        Party _side,
        address _contributor,
        uint _amount,
        uint _totalRequired
    ) internal returns (uint) {
        // Take up to the amount necessary to fund the current round at the current costs.
        uint contribution; // Amount contributed.
        uint remainingERC20; // Remaining ERC20 tokens to send back.
        (contribution, remainingERC20) = _calculateContribution(
            _amount,
            _totalRequired.subCap(_round.amountPaid[uint(_side)])
        );
        _round.contributions[_contributor][uint(_side)] += contribution;
        _round.amountPaid[uint(_side)] += contribution;
        _round.feeRewards += contribution;

        // deposit ERC20 tokens to contract
        // Sender must approve this contract to transfer ERC20 tokens on their behalf.
        erc20.safeTransferFrom(msg.sender, address(this), contribution);

        return contribution;
    }

    /** @dev Execute the ruling of a dispute.
     *  @param _disputeID ID of the dispute in the arbitrator contract.
     *  @param _ruling Ruling given by the arbitrator. Note that 0 is reserved for "Refused to arbitrate".
     */
    function _executeRuling(uint _disputeID, uint _ruling) internal {
        bytes32 itemID = arbitratorDisputeIDToItem[msg.sender][_disputeID];
        Item storage item = items[itemID];
        Request storage request = item.requests[item.requests.length - 1];

        Party winner = Party(_ruling);

        if (winner == Party.Requester) {
            // Execute Request.
            if (item.status == Status.RegistrationRequested) item.status = Status.Registered;
            else if (item.status == Status.ClearingRequested) item.status = Status.Absent;
        } else {
            if (item.status == Status.RegistrationRequested) item.status = Status.Absent;
            else if (item.status == Status.ClearingRequested) item.status = Status.Registered;
        }

        request.resolved = true;
        request.ruling = Party(_ruling);

        emit ItemStatusChange(itemID, item.requests.length - 1, request.rounds.length - 1, true, true);

        // Automatically withdraw first deposits and reimbursements (first round only).
        if (winner == Party.None) {
            withdrawFeesAndRewards(request.parties[uint(Party.Requester)], itemID, item.requests.length - 1, 0);
            withdrawFeesAndRewards(request.parties[uint(Party.Challenger)], itemID, item.requests.length - 1, 0);
        } else {
            withdrawFeesAndRewards(request.parties[uint(winner)], itemID, item.requests.length - 1, 0);
        }
    }

    // ************************ //
    // *       Getters        * //
    // ************************ //

    /** @dev Returns the number of items that were submitted. Includes items that never made it to the list or were later removed.
     *  @return count The number of items on the list.
     */
    function itemCount() external view returns (uint count) {
        return itemList.length;
    }

    /** @dev Gets the contributions made by a party for a given round of a request.
     *  @param _itemID The ID of the item.
     *  @param _request The request to query.
     *  @param _round The round to query.
     *  @param _contributor The address of the contributor.
     *  @return contributions The contributions.
     */
    function getContributions(
        bytes32 _itemID,
        uint _request,
        uint _round,
        address _contributor
    ) external view returns (uint[3] memory contributions) {
        Item storage item = items[_itemID];
        Request storage request = item.requests[_request];
        Round storage round = request.rounds[_round];
        contributions = round.contributions[_contributor];
    }

    /** @dev Returns item's information. Includes length of requests array.
     *  @param _itemID The ID of the queried item.
     *  @return data The data describing the item.
     *  @return status The current status of the item.
     *  @return numberOfRequests Length of list of status change requests made for the item.
     */
    function getItemInfo(
        bytes32 _itemID
    ) external view returns (bytes memory data, Status status, uint numberOfRequests) {
        Item storage item = items[_itemID];
        return (item.data, item.status, item.requests.length);
    }

    /** @dev Gets information on a request made for the item.
     *  @param _itemID The ID of the queried item.
     *  @param _request The request to be queried.
     *  @return disputed True if a dispute was raised.
     *  @return disputeID ID of the dispute, if any..
     *  @return submissionTime Time when the request was made.
     *  @return resolved True if the request was executed and/or any raised disputes were resolved.
     *  @return parties Address of requester and challenger, if any.
     *  @return numberOfRounds Number of rounds of dispute.
     *  @return ruling The final ruling given, if any.
     *  @return arbitrator The arbitrator trusted to solve disputes for this request.
     *  @return arbitratorExtraData The extra data for the trusted arbitrator of this request.
     *  @return metaEvidenceID The meta evidence to be used in a dispute for this case.
     */
    function getRequestInfo(
        bytes32 _itemID,
        uint _request
    )
        external
        view
        returns (
            bool disputed,
            uint disputeID,
            uint submissionTime,
            bool resolved,
            address[3] memory parties,
            uint numberOfRounds,
            Party ruling,
            IArbitrator arbitrator,
            bytes memory arbitratorExtraData,
            uint metaEvidenceID
        )
    {
        Request storage request = items[_itemID].requests[_request];
        return (
            request.disputed,
            request.disputeID,
            request.submissionTime,
            request.resolved,
            request.parties,
            request.rounds.length,
            request.ruling,
            request.arbitrator,
            request.arbitratorExtraData,
            request.metaEvidenceID
        );
    }

    /** @dev Gets the information of a round of a request.
     *  @param _itemID The ID of the queried item.
     *  @param _request The request to be queried.
     *  @param _round The round to be queried.
     *  @return appealed Whether appealed or not.
     *  @return amountPaid Tracks the sum paid for each Party in this round.
     *  @return hasPaid True if the Party has fully paid its fee in this round.
     *  @return feeRewards Sum of reimbursable fees and stake rewards available to the parties that made contributions to the side that ultimately wins a dispute.
     */
    function getRoundInfo(
        bytes32 _itemID,
        uint _request,
        uint _round
    ) external view returns (bool appealed, uint[3] memory amountPaid, bool[3] memory hasPaid, uint feeRewards) {
        Item storage item = items[_itemID];
        Request storage request = item.requests[_request];
        Round storage round = request.rounds[_round];
        return (_round != (request.rounds.length - 1), round.amountPaid, round.hasPaid, round.feeRewards);
    }

    /* Modifiers */

    modifier onlyGovernor() {
        if (msg.sender != governor) revert MUST_BE_GOVERNOR();
        _;
    }

    /**
     * @notice Ensures the caller is authorized to upgrade the contract
     * @param _newImpl The new implementation address
     */
    function _authorizeUpgrade(address _newImpl) internal view override onlyOwner {}
}
