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
import { IWETH } from "./interfaces/IWETH.sol";

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

    /**
     *  @dev Deploy the arbitrable curated registry.
     *  @param _arbitrator Arbitrator to resolve potential disputes. The arbitrator is trusted to support appeal periods and not reenter.
     *  @param _arbitratorExtraData Extra data for the trusted arbitrator contract.
     *  @param _registrationMetaEvidence The URI of the meta evidence object for registration requests.
     *  @param _clearingMetaEvidence The URI of the meta evidence object for clearing requests.
     *  @param _governor The trusted governor of this contract.
     *  @param _WETH The address of the WETH contract.
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
        address _WETH,
        uint _submissionBaseDeposit,
        uint _removalBaseDeposit,
        uint _submissionChallengeBaseDeposit,
        uint _removalChallengeBaseDeposit,
        uint _challengePeriodDuration,
        uint[3] memory _stakeMultipliers
    ) {
        emit MetaEvidence(0, _registrationMetaEvidence);
        emit MetaEvidence(1, _clearingMetaEvidence);

        arbitrator = _arbitrator;
        arbitratorExtraData = _arbitratorExtraData;
        governor = _governor;
        WETH = _WETH;
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

    /** @dev Submit a request to register an item. Accepts enough ETH to cover the deposit, reimburses the rest.
     *  @param _item The data describing the item.
     */
    function addItem(bytes calldata _item) external payable nonReentrant {
        bytes32 itemID = keccak256(_item);
        require(items[itemID].status == Status.Absent, "Item must be absent to be added.");
        _requestStatusChange(_item, submissionBaseDeposit);
    }

    /** @dev Submit a request to remove an item from the list. Accepts enough ETH to cover the deposit, reimburses the rest.
     *  @param _itemID The ID of the item to remove.
     *  @param _evidence A link to an evidence using its URI. Ignored if not provided.
     */
    function removeItem(bytes32 _itemID, string calldata _evidence) external payable nonReentrant {
        require(items[_itemID].status == Status.Registered, "Item must be registered to be removed.");
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

    /** @dev Challenges the request of the item. Accepts enough ETH to cover the deposit, reimburses the rest.
     *  @param _itemID The ID of the item which request to challenge.
     *  @param _evidence A link to an evidence using its URI. Ignored if not provided.
     */
    function challengeRequest(bytes32 _itemID, string calldata _evidence) external payable nonReentrant {
        Item storage item = items[_itemID];

        require(
            item.status == Status.RegistrationRequested || item.status == Status.ClearingRequested,
            "The item must have a pending request."
        );

        Request storage request = item.requests[item.requests.length - 1];
        require(
            block.timestamp - request.submissionTime <= challengePeriodDuration,
            "Challenges must occur during the challenge period."
        );
        require(!request.disputed, "The request should not have already been disputed.");

        request.parties[uint(Party.Challenger)] = msg.sender;

        Round storage round = request.rounds[0];
        uint arbitrationCost = request.arbitrator.arbitrationCost(request.arbitratorExtraData);
        uint challengerBaseDeposit = item.status == Status.RegistrationRequested
            ? submissionChallengeBaseDeposit
            : removalChallengeBaseDeposit;
        uint totalCost = arbitrationCost.addCap(challengerBaseDeposit);
        contribute(round, Party.Challenger, msg.sender, msg.value, totalCost);
        require(round.amountPaid[uint(Party.Challenger)] >= totalCost, "You must fully fund your side.");
        round.hasPaid[uint(Party.Challenger)] = true;

        // Raise a dispute.
        request.disputeID = request.arbitrator.createDispute{ value: arbitrationCost }(
            RULING_OPTIONS,
            request.arbitratorExtraData
        );
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
     */
    function fundAppeal(bytes32 _itemID, Party _side) external payable nonReentrant {
        require(_side == Party.Requester || _side == Party.Challenger, "Invalid side.");
        require(
            items[_itemID].status == Status.RegistrationRequested || items[_itemID].status == Status.ClearingRequested,
            "The item must have a pending request."
        );
        Request storage request = items[_itemID].requests[items[_itemID].requests.length - 1];
        require(request.disputed, "A dispute must have been raised to fund an appeal.");
        (uint appealPeriodStart, uint appealPeriodEnd) = request.arbitrator.appealPeriod(request.disputeID);
        require(
            block.timestamp >= appealPeriodStart && block.timestamp < appealPeriodEnd,
            "Contributions must be made within the appeal period."
        );

        uint multiplier;
        {
            Party winner = Party(request.arbitrator.currentRuling(request.disputeID));
            Party loser;
            if (winner == Party.Requester) loser = Party.Challenger;
            else if (winner == Party.Challenger) loser = Party.Requester;
            require(
                _side != loser || (block.timestamp - appealPeriodStart < (appealPeriodEnd - appealPeriodStart) / 2),
                "The loser must contribute during the first half of the appeal period."
            );

            if (_side == winner) multiplier = winnerStakeMultiplier;
            else if (_side == loser) multiplier = loserStakeMultiplier;
            else multiplier = sharedStakeMultiplier;
        }

        Round storage round = request.rounds[request.rounds.length - 1];
        uint appealCost = request.arbitrator.appealCost(request.disputeID, request.arbitratorExtraData);
        uint totalCost = appealCost.addCap((appealCost.mulCap(multiplier)) / MULTIPLIER_DIVISOR);
        uint contribution = contribute(round, _side, msg.sender, msg.value, totalCost);

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
            request.arbitrator.appeal{ value: appealCost }(request.disputeID, request.arbitratorExtraData);
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
        require(request.resolved, "Request must be resolved.");

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

        _safeTransferETHWithFallback(_beneficiary, reward);
    }

    /** @dev Executes an unchallenged request if the challenge period has passed.
     *  @param _itemID The ID of the item to execute.
     */
    function executeRequest(bytes32 _itemID) external nonReentrant {
        Item storage item = items[_itemID];
        Request storage request = item.requests[item.requests.length - 1];
        require(
            block.timestamp - request.submissionTime > challengePeriodDuration,
            "Time to challenge the request must pass."
        );
        require(!request.disputed, "The request should not be disputed.");

        if (item.status == Status.RegistrationRequested) item.status = Status.Registered;
        else if (item.status == Status.ClearingRequested) item.status = Status.Absent;
        else revert("There must be a request.");

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
        require(_ruling <= RULING_OPTIONS, "Invalid ruling option");
        require(address(request.arbitrator) == msg.sender, "Only the arbitrator can give a ruling");
        require(!request.resolved, "The request must not be resolved.");

        // The ruling is inverted if the loser paid its fees.
        if (round.hasPaid[uint(Party.Requester)] == true)
            // If one side paid its fees, the ruling is in its favor. Note that if the other side had also paid, an appeal would have been created.
            resultRuling = Party.Requester;
        else if (round.hasPaid[uint(Party.Challenger)] == true) resultRuling = Party.Challenger;

        emit Ruling(IArbitrator(msg.sender), _disputeID, uint(resultRuling));
        executeRuling(_disputeID, uint(resultRuling));
    }

    /** @dev Submit a reference to evidence. EVENT.
     *  @param _itemID The ID of the item which the evidence is related to.
     *  @param _evidence A link to an evidence using its URI.
     */
    function submitEvidence(bytes32 _itemID, string calldata _evidence) external nonReentrant {
        Item storage item = items[_itemID];
        Request storage request = item.requests[item.requests.length - 1];
        require(!request.resolved, "The dispute must not already be resolved.");

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

    /** @dev Submit a request to change item's status. Accepts enough ETH to cover the deposit, reimburses the rest.
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
        contribute(round, Party.Requester, msg.sender, msg.value, totalCost);
        require(round.amountPaid[uint(Party.Requester)] >= totalCost, "You must fully fund your side.");
        round.hasPaid[uint(Party.Requester)] = true;

        emit ItemStatusChange(itemID, item.requests.length - 1, request.rounds.length - 1, false, false);
        emit RequestSubmitted(itemID, item.requests.length - 1, item.status);
        emit RequestEvidenceGroupID(itemID, item.requests.length - 1, evidenceGroupID);
    }

    /** @dev Returns the contribution value and remainder from available ETH and required amount.
     *  @param _available The amount of ETH available for the contribution.
     *  @param _requiredAmount The amount of ETH required for the contribution.
     *  @return taken The amount of ETH taken.
     *  @return remainder The amount of ETH left from the contribution.
     */
    function calculateContribution(
        uint _available,
        uint _requiredAmount
    ) internal pure returns (uint taken, uint remainder) {
        if (_requiredAmount > _available) return (_available, 0);
        // Take whatever is available, return 0 as leftover ETH.
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
    function contribute(
        Round storage _round,
        Party _side,
        address _contributor,
        uint _amount,
        uint _totalRequired
    ) internal returns (uint) {
        // Take up to the amount necessary to fund the current round at the current costs.
        uint contribution; // Amount contributed.
        uint remainingETH; // Remaining ETH to send back.
        (contribution, remainingETH) = calculateContribution(
            _amount,
            _totalRequired.subCap(_round.amountPaid[uint(_side)])
        );
        _round.contributions[_contributor][uint(_side)] += contribution;
        _round.amountPaid[uint(_side)] += contribution;
        _round.feeRewards += contribution;

        // Reimburse leftover ETH.
        _safeTransferETHWithFallback(_contributor, remainingETH);

        return contribution;
    }

    /** @dev Execute the ruling of a dispute.
     *  @param _disputeID ID of the dispute in the arbitrator contract.
     *  @param _ruling Ruling given by the arbitrator. Note that 0 is reserved for "Refused to arbitrate".
     */
    function executeRuling(uint _disputeID, uint _ruling) internal {
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

    /**
     * @notice Transfer ETH/WETH from the contract
     * @param _to The recipient address
     * @param _amount The amount transferring
     */
    function _safeTransferETHWithFallback(address _to, uint256 _amount) private {
        // Ensure the contract has enough ETH to transfer
        if (address(this).balance < _amount) revert("Insufficient balance");

        // Used to store if the transfer succeeded
        bool success;

        assembly {
            // Transfer ETH to the recipient
            // Limit the call to 30,000 gas
            success := call(30000, _to, _amount, 0, 0, 0, 0)
        }

        // If the transfer failed:
        if (!success) {
            // Wrap as WETH
            IWETH(WETH).deposit{ value: _amount }();

            // Transfer WETH instead
            bool wethSuccess = IWETH(WETH).transfer(_to, _amount);

            // Ensure successful transfer
            if (!wethSuccess) revert("WETH transfer failed");
        }
    }

    /* Modifiers */

    modifier onlyGovernor() {
        require(msg.sender == governor, "The caller must be the governor.");
        _;
    }

    /**
     * @notice Ensures the caller is authorized to upgrade the contract
     * @param _newImpl The new implementation address
     */
    function _authorizeUpgrade(address _newImpl) internal view override onlyOwner {}
}