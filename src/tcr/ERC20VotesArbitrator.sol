// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IERC20VotesArbitrator } from "./interfaces/IERC20VotesArbitrator.sol";
import { IArbitrable } from "./interfaces/IArbitrable.sol";
import { ArbitratorStorageV1 } from "./storage/ArbitratorStorageV1.sol";

import { ERC20VotesMintable } from "../ERC20VotesMintable.sol";

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract ERC20VotesArbitrator is
    IERC20VotesArbitrator,
    ArbitratorStorageV1,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeERC20 for IERC20;
    constructor() payable initializer {}

    /**
     * @notice Used to initialize the contract
     * @param votingToken_ The address of the ERC20 voting token
     * @param arbitrable_ The address of the arbitrable contract
     * @param votingPeriod_ The initial voting period
     * @param votingDelay_ The initial voting delay
     * @param revealPeriod_ The initial reveal period to reveal committed votes
     * @param appealPeriod_ The initial appeal period
     * @param appealCost_ The initial appeal cost
     * @param arbitrationCost_ The initial arbitration cost
     */
    function initialize(
        address votingToken_,
        address arbitrable_,
        uint256 votingPeriod_,
        uint256 votingDelay_,
        uint256 revealPeriod_,
        uint256 appealPeriod_,
        uint256 appealCost_,
        uint256 arbitrationCost_
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        if (votingToken_ == address(0)) revert INVALID_VOTING_TOKEN_ADDRESS();
        if (votingPeriod_ < MIN_VOTING_PERIOD || votingPeriod_ > MAX_VOTING_PERIOD) revert INVALID_VOTING_PERIOD();
        if (votingDelay_ < MIN_VOTING_DELAY || votingDelay_ > MAX_VOTING_DELAY) revert INVALID_VOTING_DELAY();
        if (revealPeriod_ < MIN_REVEAL_PERIOD || revealPeriod_ > MAX_REVEAL_PERIOD) revert INVALID_REVEAL_PERIOD();
        if (appealPeriod_ < MIN_APPEAL_PERIOD || appealPeriod_ > MAX_APPEAL_PERIOD) revert INVALID_APPEAL_PERIOD();
        if (appealCost_ < MIN_APPEAL_COST || appealCost_ > MAX_APPEAL_COST) revert INVALID_APPEAL_COST();
        if (arbitrationCost_ < MIN_ARBITRATION_COST || arbitrationCost_ > MAX_ARBITRATION_COST)
            revert INVALID_ARBITRATION_COST();

        emit VotingPeriodSet(votingPeriod, votingPeriod_);
        emit VotingDelaySet(votingDelay, votingDelay_);
        emit AppealPeriodSet(_appealPeriod, appealPeriod_);
        emit AppealCostSet(_appealCost, appealCost_);
        emit ArbitrationCostSet(_arbitrationCost, arbitrationCost_);

        votingToken = ERC20VotesMintable(votingToken_);
        arbitrable = IArbitrable(arbitrable_);
        votingPeriod = votingPeriod_;
        votingDelay = votingDelay_;
        revealPeriod = revealPeriod_;
        _appealPeriod = appealPeriod_;
        _appealCost = appealCost_;
        _arbitrationCost = arbitrationCost_;
    }

    /**
     * @notice Function used to create a new dispute. Only callable by the arbitrable contract.
     * @param _choices The number of choices for the dispute
     * @param _extraData Additional data for the dispute
     * @return disputeID The ID of the new dispute
     */
    function createDispute(
        uint256 _choices,
        bytes calldata _extraData
    ) external onlyArbitrable nonReentrant returns (uint256 disputeID) {
        // only support 2 choices for now
        if (_choices != 2) revert INVALID_DISPUTE_CHOICES();

        // get tokens from arbitrable
        // arbitrable must have approved the arbitrator to transfer the tokens
        // fails otherwise
        IERC20(address(votingToken)).safeTransferFrom(address(arbitrable), address(this), _arbitrationCost);

        disputeCount++;
        Dispute storage newDispute = disputes[disputeCount];

        newDispute.id = disputeCount;
        newDispute.arbitrable = address(arbitrable);
        newDispute.currentRound = 0;
        newDispute.choices = _choices;
        newDispute.executed = false;

        newDispute.rounds[0].votingStartTime = block.timestamp + votingDelay;
        newDispute.rounds[0].votingEndTime = newDispute.rounds[0].votingStartTime + votingPeriod;
        newDispute.rounds[0].revealPeriodEndTime = newDispute.rounds[0].votingEndTime + revealPeriod;
        newDispute.rounds[0].appealPeriodEndTime = newDispute.rounds[0].revealPeriodEndTime + _appealPeriod;
        newDispute.rounds[0].votes = 0; // total votes cast
        newDispute.rounds[0].ruling = IArbitrable.Party.None; // winning choice
        newDispute.rounds[0].extraData = _extraData;
        newDispute.rounds[0].creationBlock = block.number;
        newDispute.rounds[0].totalSupply = votingToken.totalSupply();
        newDispute.rounds[0].cost = _arbitrationCost;

        emit DisputeCreated(
            newDispute.id,
            address(arbitrable),
            newDispute.rounds[0].votingStartTime,
            newDispute.rounds[0].votingEndTime,
            newDispute.rounds[0].revealPeriodEndTime,
            newDispute.rounds[0].appealPeriodEndTime,
            newDispute.rounds[0].totalSupply,
            _extraData,
            _choices
        );
        emit DisputeCreation(newDispute.id, arbitrable);

        return newDispute.id;
    }

    /**
     * @notice Gets the receipt for a voter on a given dispute
     * @param disputeId the id of dispute
     * @param voter The address of the voter
     * @return The voting receipt
     */
    function getReceipt(uint256 disputeId, address voter) external view returns (Receipt memory) {
        uint256 round = disputes[disputeId].currentRound;
        return disputes[disputeId].rounds[round].receipts[voter];
    }

    /**
     * @notice Gets the state of a dispute
     * @param disputeId The id of the dispute
     * @return Dispute state
     */
    function currentRoundState(uint256 disputeId) external view returns (DisputeState) {
        return _getVotingRoundState(disputeId, disputes[disputeId].currentRound);
    }

    /**
     * @notice Get the state of a specific voting round for a dispute
     * @param disputeId The ID of the dispute
     * @param round The round number
     * @return The state of the voting round
     */
    function _getVotingRoundState(
        uint256 disputeId,
        uint256 round
    ) internal view validDisputeID(disputeId) returns (DisputeState) {
        VotingRound storage votingRound = disputes[disputeId].rounds[round];

        if (block.timestamp <= votingRound.votingStartTime) {
            return DisputeState.Pending;
        } else if (block.timestamp <= votingRound.votingEndTime) {
            return DisputeState.Active;
        } else if (block.timestamp <= votingRound.revealPeriodEndTime) {
            return DisputeState.Reveal;
        } else if (block.timestamp <= votingRound.appealPeriodEndTime) {
            return DisputeState.Appealable;
        } else {
            return DisputeState.Solved;
        }
    }

    /**
     * @notice Get the status of a dispute
     * @dev This function maps the DisputeState to the IArbitrator.DisputeStatus
     * @param disputeId The ID of the dispute to check
     * @return The status of the dispute as defined in IArbitrator.DisputeStatus
     * @dev checks for valid dispute ID first in the state function
     */
    function disputeStatus(uint256 disputeId) public view returns (DisputeStatus) {
        DisputeState disputeState = _getVotingRoundState(disputeId, disputes[disputeId].currentRound);

        if (disputeState == DisputeState.Appealable) {
            return DisputeStatus.Appealable;
        } else if (disputeState == DisputeState.Solved) {
            // executed or solved
            return DisputeStatus.Solved;
        } else {
            // pending, active, reveal voting states
            return DisputeStatus.Waiting;
        }
    }

    /**
     * @notice Returns the current ruling for a dispute.
     * @param disputeId The ID of the dispute.
     * @return ruling The current ruling of the dispute.
     */
    function currentRuling(
        uint256 disputeId
    ) external view override validDisputeID(disputeId) returns (IArbitrable.Party) {
        uint256 round = disputes[disputeId].currentRound;
        return disputes[disputeId].rounds[round].ruling;
    }

    /**
     * @notice Cast a vote for a dispute
     * @param disputeId The id of the dispute to vote on
     * @param choice The support value for the vote. Based on the choices provided in the createDispute function
     */
    function castVote(uint256 disputeId, uint8 choice) external nonReentrant {
        emit VoteCast(msg.sender, disputeId, choice, _castVoteInternal(msg.sender, disputeId, choice), "");
    }

    /**
     * @notice Cast a vote for a dispute with a reason
     * @param disputeId The id of the dispute to vote on
     * @param choice The support value for the vote. Based on the choices provided in the createDispute function
     * @param reason The reason given for the vote by the voter
     */
    function castVoteWithReason(uint256 disputeId, uint8 choice, string calldata reason) external nonReentrant {
        emit VoteCast(msg.sender, disputeId, choice, _castVoteInternal(msg.sender, disputeId, choice), reason);
    }

    /**
     * @notice Internal function that caries out voting logic
     * @param voter The voter that is casting their vote
     * @param disputeId The id of the dispute to vote on
     * @param choice The support value for the vote. Based on the choices provided in the createDispute function
     * @return The number of votes cast
     */
    function _castVoteInternal(address voter, uint256 disputeId, uint256 choice) internal returns (uint256) {
        Dispute storage dispute = disputes[disputeId];
        uint256 round = dispute.currentRound;

        if (_getVotingRoundState(disputeId, round) != DisputeState.Active) revert VOTING_CLOSED();
        if (choice == 0 || choice > dispute.choices) revert INVALID_VOTE_CHOICE();

        Receipt storage receipt = dispute.rounds[round].receipts[voter];
        if (receipt.hasVoted) revert VOTER_ALREADY_VOTED();
        uint256 votes = votingToken.getPastVotes(voter, dispute.rounds[round].creationBlock);

        if (votes == 0) revert VOTER_HAS_NO_VOTES();

        dispute.rounds[round].votes += votes;

        dispute.rounds[round].choiceVotes[choice] += votes;

        receipt.hasVoted = true;
        receipt.choice = choice;
        receipt.votes = votes;

        return votes;
    }

    /**
     * @notice Implements the appeal process for disputes within the ERC20VotesArbitrator.
     * @param _disputeID The ID of the dispute to appeal.
     * @param _extraData Additional data for the appeal
     * @dev Any party involved in the dispute can appeal via the arbitrable contract by calling fundAppeal()
     */
    function appeal(
        uint256 _disputeID,
        bytes calldata _extraData
    ) external payable override onlyArbitrable nonReentrant {
        Dispute storage dispute = disputes[_disputeID];

        // Ensure the dispute exists and is in a state that allows appeals
        if (dispute.executed) revert DISPUTE_ALREADY_EXECUTED();
        if (disputeStatus(_disputeID) != DisputeStatus.Appealable) revert DISPUTE_NOT_APPEALABLE();
        if (block.timestamp >= dispute.rounds[dispute.currentRound].appealPeriodEndTime) revert APPEAL_PERIOD_ENDED();

        // Calculate the appeal cost
        uint256 newRound = dispute.currentRound + 1;
        uint256 costToAppeal = _calculateAppealCost(newRound);

        // transfer erc20 tokens from arbitrable to arbitrator (this contract)
        // assumes that the arbitrable contract has approved the arbitrator to transfer the tokens
        // fails otherwise
        IERC20(address(votingToken)).safeTransferFrom(address(arbitrable), address(this), costToAppeal);

        // todo give winning voters tokens somehow

        emit AppealDecision(_disputeID, arbitrable);
        emit AppealRaised(_disputeID, newRound, msg.sender, costToAppeal);

        dispute.rounds[newRound].votingStartTime = block.timestamp + votingDelay;
        dispute.rounds[newRound].votingEndTime = dispute.rounds[newRound].votingStartTime + votingPeriod;
        dispute.rounds[newRound].revealPeriodEndTime = dispute.rounds[newRound].votingEndTime + revealPeriod;
        dispute.rounds[newRound].appealPeriodEndTime = dispute.rounds[newRound].revealPeriodEndTime + _appealPeriod;
        dispute.rounds[newRound].votes = 0;
        dispute.rounds[newRound].ruling = IArbitrable.Party.None;
        dispute.rounds[newRound].creationBlock = block.number;
        dispute.rounds[newRound].totalSupply = votingToken.totalSupply();
        dispute.rounds[newRound].cost = costToAppeal;
        dispute.rounds[newRound].extraData = _extraData;
        dispute.currentRound = newRound;

        emit DisputeReset(
            _disputeID,
            dispute.rounds[newRound].votingStartTime,
            dispute.rounds[newRound].votingEndTime,
            dispute.rounds[newRound].revealPeriodEndTime,
            dispute.rounds[newRound].appealPeriodEndTime,
            dispute.rounds[newRound].totalSupply,
            dispute.rounds[newRound].cost,
            dispute.rounds[newRound].extraData
        );
    }

    /**
     * @notice Calculates the cost required to appeal a specific dispute.
     * @param _currentRound The current round number of the dispute.
     * @return The calculated appeal cost.
     */
    function _calculateAppealCost(uint256 _currentRound) internal view returns (uint256) {
        if (_currentRound > MAX_APPEAL_ROUNDS) revert MAX_APPEAL_ROUNDS_REACHED();
        // Increase the appeal cost with each round
        return _appealCost * (2 ** (_currentRound));
    }

    /**
     * @notice Execute a dispute and set the ruling
     * @param disputeId The ID of the dispute to execute
     */
    function executeRuling(uint256 disputeId) external nonReentrant {
        Dispute storage dispute = disputes[disputeId];
        uint256 round = dispute.currentRound;
        if (dispute.executed) revert DISPUTE_ALREADY_EXECUTED();
        if (_getVotingRoundState(disputeId, round) != DisputeState.Solved) revert DISPUTE_NOT_SOLVED();

        uint256 winningChoice = _determineWinningChoice(disputeId, round);

        // Convert winning choice to Party enum
        IArbitrable.Party ruling = _convertChoiceToParty(winningChoice);

        dispute.rounds[round].ruling = ruling;
        dispute.executed = true;
        dispute.winningChoice = winningChoice;

        // Call the rule function on the arbitrable contract
        arbitrable.rule(disputeId, uint256(ruling));

        emit DisputeExecuted(disputeId, ruling);
    }

    /**
     * @notice Allows voters to withdraw their proportional share of the cost for a voting round if they voted on the correct side of the ruling.
     * @param disputeId The ID of the dispute.
     * @param round The round number.
     * @param voter The address of the voter.
     */
    function withdrawVoterRewards(uint256 disputeId, uint256 round, address voter) external nonReentrant {
        Dispute storage dispute = disputes[disputeId];

        // Get the voting round
        VotingRound storage votingRound = dispute.rounds[round];

        if (round > dispute.currentRound) revert INVALID_ROUND();

        // Ensure the dispute round is finalized
        if (_getVotingRoundState(disputeId, round) != DisputeState.Solved) {
            revert DISPUTE_NOT_SOLVED();
        }

        // Check that the voter hasn't already claimed
        if (votingRound.rewardsClaimed[voter]) {
            revert REWARD_ALREADY_CLAIMED();
        }

        // Get the receipt for the voter
        Receipt storage receipt = votingRound.receipts[voter];

        // Check that the voter has voted
        if (!receipt.hasVoted) {
            revert VOTER_HAS_NOT_VOTED();
        }

        uint256 winningChoice = _determineWinningChoice(disputeId, round);

        uint256 amount = 0;
        uint256 totalRewards = votingRound.cost; // Total amount to distribute among voters

        if (votingRound.votes == 0) revert NO_VOTES();

        if (winningChoice == 0) {
            // Ruling is 0 or Party.None, both sides can withdraw proportional share
            amount = (receipt.votes * totalRewards) / votingRound.votes;
        } else {
            // Ruling is not 0, only winning voters can withdraw
            if (receipt.choice != winningChoice) {
                revert VOTER_ON_LOSING_SIDE();
            }
            uint256 totalWinningVotes = votingRound.choiceVotes[winningChoice];

            if (totalWinningVotes == 0) revert NO_WINNING_VOTES();

            // Calculate voter's share
            amount = (receipt.votes * totalRewards) / totalWinningVotes;
        }

        // Mark as claimed
        votingRound.rewardsClaimed[voter] = true;

        // Transfer tokens to voter
        IERC20(address(votingToken)).safeTransfer(voter, amount);

        emit RewardWithdrawn(disputeId, round, voter, amount);
    }

    /**
     * @notice Determines the winning choice based on the votes.
     * @param _disputeID The ID of the dispute.
     * @param _round The round number.
     * @return The choice with the highest votes.
     */
    function _determineWinningChoice(uint256 _disputeID, uint256 _round) internal view returns (uint256) {
        Dispute storage dispute = disputes[_disputeID];
        VotingRound storage votingRound = dispute.rounds[_round];

        uint256 winningChoice = 0;
        uint256 highestVotes = 0;
        bool tie = false;

        for (uint256 i = 1; i <= dispute.choices; i++) {
            uint256 votesForChoice = votingRound.choiceVotes[i];
            if (votesForChoice > highestVotes) {
                highestVotes = votesForChoice;
                winningChoice = i;
            } else if (votesForChoice == highestVotes && votesForChoice != 0) {
                tie = true;
            }
        }

        if (tie) {
            return 0;
        }

        return winningChoice;
    }

    /**
     * @notice Converts a choice number to the corresponding Party enum.
     * @param _choice The choice number.
     * @return The corresponding Party.
     */
    function _convertChoiceToParty(uint256 _choice) internal pure returns (IArbitrable.Party) {
        if (_choice == 0) {
            return IArbitrable.Party.None;
        } else if (_choice == 1) {
            return IArbitrable.Party.Requester;
        } else if (_choice == 2) {
            return IArbitrable.Party.Challenger;
        } else {
            return IArbitrable.Party.None;
        }
    }

    /**
     * @notice Owner function for setting the voting delay
     * @param newVotingDelay new voting delay, in blocks
     */
    function setVotingDelay(uint256 newVotingDelay) external onlyOwner {
        if (newVotingDelay < MIN_VOTING_DELAY || newVotingDelay > MAX_VOTING_DELAY) revert INVALID_VOTING_DELAY();
        uint256 oldVotingDelay = votingDelay;
        votingDelay = newVotingDelay;

        emit VotingDelaySet(oldVotingDelay, votingDelay);
    }

    /**
     * @notice Owner function for setting the voting period
     * @param newVotingPeriod new voting period, in blocks
     */
    function setVotingPeriod(uint256 newVotingPeriod) external onlyOwner {
        if (newVotingPeriod < MIN_VOTING_PERIOD || newVotingPeriod > MAX_VOTING_PERIOD) revert INVALID_VOTING_PERIOD();

        uint256 oldVotingPeriod = votingPeriod;
        votingPeriod = newVotingPeriod;

        emit VotingPeriodSet(oldVotingPeriod, votingPeriod);
    }

    function bps2Uint(uint256 bps, uint256 number) internal pure returns (uint256) {
        return (number * bps) / 10000;
    }

    function appealPeriod(uint256 _disputeID) external view override returns (uint256 start, uint256 end) {
        uint256 round = disputes[_disputeID].currentRound;
        return (
            disputes[_disputeID].rounds[round].revealPeriodEndTime,
            disputes[_disputeID].rounds[round].appealPeriodEndTime
        );
    }

    /**
     * @notice Modifier to restrict function access to only the arbitrable contract
     */
    modifier onlyArbitrable() {
        if (msg.sender != address(arbitrable)) revert ONLY_ARBITRABLE();
        _;
    }

    /**
     * @notice Modifier to check if a dispute ID is valid
     * @param _disputeID The ID of the dispute to check
     */
    modifier validDisputeID(uint256 _disputeID) {
        if (_disputeID == 0 || _disputeID > disputeCount) revert INVALID_DISPUTE_ID();
        _;
    }

    /**
     * @notice Returns the cost of arbitration
     * @return cost The cost of arbitration
     */
    function arbitrationCost(bytes calldata) external view override returns (uint256 cost) {
        return _arbitrationCost;
    }

    /**
     * @notice Returns the cost of appealing a dispute
     * @param disputeID The ID of the dispute
     * @return cost The cost of the appeal
     */
    function appealCost(uint256 disputeID, bytes calldata) external view returns (uint256 cost) {
        return _calculateAppealCost(disputes[disputeID].currentRound + 1);
    }

    /**
     * @notice Ensures the caller is authorized to upgrade the contract
     * @param _newImpl The new implementation address
     */
    function _authorizeUpgrade(address _newImpl) internal view override onlyOwner {}
}
