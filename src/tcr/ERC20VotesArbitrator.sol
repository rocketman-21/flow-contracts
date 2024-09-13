// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IERC20VotesArbitrator } from "./interfaces/IERC20VotesArbitrator.sol";
import { IArbitrable } from "./interfaces/IArbitrable.sol";
import { ArbitratorStorageV1 } from "./storage/ArbitratorStorageV1.sol";

import { ERC20VotesMintable } from "../ERC20VotesMintable.sol";

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract ERC20VotesArbitrator is
    IERC20VotesArbitrator,
    ArbitratorStorageV1,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
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
     * @param quorumVotesBPS_ The initial quorum votes threshold in basis points
     */
    function initialize(
        address votingToken_,
        address arbitrable_,
        uint256 votingPeriod_,
        uint256 votingDelay_,
        uint256 revealPeriod_,
        uint256 appealPeriod_,
        uint256 appealCost_,
        uint256 quorumVotesBPS_
    ) public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        if (votingToken_ == address(0)) revert INVALID_VOTING_TOKEN_ADDRESS();
        if (votingPeriod_ < MIN_VOTING_PERIOD || votingPeriod_ > MAX_VOTING_PERIOD) revert INVALID_VOTING_PERIOD();
        if (votingDelay_ < MIN_VOTING_DELAY || votingDelay_ > MAX_VOTING_DELAY) revert INVALID_VOTING_DELAY();
        if (quorumVotesBPS_ < MIN_QUORUM_VOTES_BPS || quorumVotesBPS_ > MAX_QUORUM_VOTES_BPS)
            revert INVALID_QUORUM_VOTES_BPS();
        if (revealPeriod_ < MIN_REVEAL_PERIOD || revealPeriod_ > MAX_REVEAL_PERIOD) revert INVALID_REVEAL_PERIOD();
        if (appealPeriod_ < MIN_APPEAL_PERIOD || appealPeriod_ > MAX_APPEAL_PERIOD) revert INVALID_APPEAL_PERIOD();
        if (appealCost_ < MIN_APPEAL_COST || appealCost_ > MAX_APPEAL_COST) revert INVALID_APPEAL_COST();

        emit VotingPeriodSet(votingPeriod, votingPeriod_);
        emit VotingDelaySet(votingDelay, votingDelay_);
        emit QuorumVotesBPSSet(quorumVotesBPS, quorumVotesBPS_);
        emit AppealPeriodSet(appealPeriodDuration, appealPeriod_);
        emit AppealCostSet(baseAppealCost, appealCost_);

        votingToken = ERC20VotesMintable(votingToken_);
        arbitrable = IArbitrable(arbitrable_);
        votingPeriod = votingPeriod_;
        votingDelay = votingDelay_;
        quorumVotesBPS = quorumVotesBPS_;
        revealPeriod = revealPeriod_;
        appealPeriodDuration = appealPeriod_;
        baseAppealCost = appealCost_;
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
    ) external onlyArbitrable returns (uint256 disputeID) {
        disputeCount++;
        Dispute storage newDispute = disputes[disputeCount];

        newDispute.id = disputeCount;
        newDispute.arbitrable = address(arbitrable);
        newDispute.votingStartTime = block.timestamp + votingDelay;
        newDispute.votingEndTime = newDispute.votingStartTime + votingPeriod;
        newDispute.revealPeriodEndTime = newDispute.votingEndTime + revealPeriod;
        newDispute.appealPeriodEndTime = newDispute.revealPeriodEndTime + appealPeriodDuration;
        newDispute.choices = _choices;
        newDispute.votes = 0; // total votes cast
        newDispute.ruling = IArbitrable.Party.None; // winning choice
        newDispute.extraData = _extraData;
        newDispute.executed = false;
        newDispute.creationBlock = block.number;
        newDispute.quorumVotes = quorumVotes();
        newDispute.totalSupply = votingToken.totalSupply();

        /// @notice Maintains backwards compatibility with GovernorBravo events
        emit DisputeCreated(
            newDispute.id,
            address(arbitrable),
            newDispute.votingStartTime,
            newDispute.votingEndTime,
            newDispute.revealPeriodEndTime,
            newDispute.appealPeriodEndTime,
            newDispute.quorumVotes,
            newDispute.totalSupply,
            _extraData,
            _choices
        );

        return newDispute.id;
    }

    /**
     * @notice Gets the receipt for a voter on a given dispute
     * @param disputeId the id of dispute
     * @param voter The address of the voter
     * @return The voting receipt
     */
    function getReceipt(uint256 disputeId, address voter) external view returns (Receipt memory) {
        return disputes[disputeId].receipts[voter];
    }

    /**
     * @notice Gets the state of a dispute
     * @param disputeId The id of the dispute
     * @return Dispute state
     */
    function state(uint256 disputeId) public view validDisputeID(disputeId) returns (DisputeState) {
        Dispute storage dispute = disputes[disputeId];
        if (block.timestamp <= dispute.votingStartTime) {
            return DisputeState.Pending;
        } else if (block.timestamp <= dispute.votingEndTime) {
            return DisputeState.Active;
        } else if (block.timestamp <= dispute.revealPeriodEndTime) {
            return DisputeState.Reveal;
        } else if (dispute.votes < dispute.quorumVotes) {
            return DisputeState.QuorumNotReached;
        } else if (dispute.executed) {
            return DisputeState.Executed;
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
        DisputeState disputeState = state(disputeId);

        if (
            disputeState == DisputeState.Pending ||
            disputeState == DisputeState.Active ||
            disputeState == DisputeState.Reveal
        ) {
            return DisputeStatus.Waiting;
        } else if (disputeState == DisputeState.Executed || disputeState == DisputeState.Solved) {
            return DisputeStatus.Solved;
        } else {
            return DisputeStatus.Appealable;
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
        return disputes[disputeId].ruling;
    }

    /**
     * @notice Cast a vote for a dispute
     * @param disputeId The id of the dispute to vote on
     * @param choice The support value for the vote. Based on the choices provided in the createDispute function
     */
    function castVote(uint256 disputeId, uint8 choice) external {
        emit VoteCast(msg.sender, disputeId, choice, _castVoteInternal(msg.sender, disputeId, choice), "");
    }

    /**
     * @notice Cast a vote for a dispute with a reason
     * @param disputeId The id of the dispute to vote on
     * @param choice The support value for the vote. Based on the choices provided in the createDispute function
     * @param reason The reason given for the vote by the voter
     */
    function castVoteWithReason(uint256 disputeId, uint8 choice, string calldata reason) external {
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
        require(state(disputeId) == DisputeState.Active, "NounsDAO::castVoteInternal: voting is closed");
        require(choice <= disputes[disputeId].choices, "NounsDAO::castVoteInternal: invalid vote type");
        Dispute storage dispute = disputes[disputeId];
        Receipt storage receipt = dispute.receipts[voter];
        require(receipt.hasVoted == false, "NounsDAO::castVoteInternal: voter already voted");
        uint256 votes = votingToken.getPastVotes(voter, dispute.creationBlock);

        dispute.votes += votes;

        dispute.choiceVotes[choice] += votes;

        receipt.hasVoted = true;
        receipt.choice = choice;
        receipt.votes = votes;

        return votes;
    }

    /**
     * @notice Execute a dispute and set the ruling
     * @param disputeId The ID of the dispute to execute
     */
    function executeRuling(uint256 disputeId) external {
        Dispute storage dispute = disputes[disputeId];
        if (state(disputeId) != DisputeState.Solved) revert DISPUTE_NOT_SOLVED();
        if (dispute.executed) revert DISPUTE_ALREADY_EXECUTED();

        uint256 winningChoice = 0;
        uint256 winningVotes = 0;

        // Determine the winning choice
        for (uint256 i = 1; i <= dispute.choices; i++) {
            if (dispute.choiceVotes[i] > winningVotes) {
                winningChoice = i;
                winningVotes = dispute.choiceVotes[i];
            }
        }

        // Convert winning choice to Party enum
        IArbitrable.Party ruling;
        if (winningChoice == 1) {
            ruling = IArbitrable.Party.Requester;
        } else if (winningChoice == 2) {
            ruling = IArbitrable.Party.Challenger;
        } else {
            ruling = IArbitrable.Party.None;
        }

        dispute.ruling = ruling;
        dispute.executed = true;

        // Call the rule function on the arbitrable contract
        arbitrable.rule(disputeId, uint256(ruling));

        emit DisputeExecuted(disputeId, ruling);
    }

    /**
     * @notice Owner function for setting the voting delay
     * @param newVotingDelay new voting delay, in blocks
     */
    function _setVotingDelay(uint256 newVotingDelay) external onlyOwner {
        if (newVotingDelay < MIN_VOTING_DELAY || newVotingDelay > MAX_VOTING_DELAY) revert INVALID_VOTING_DELAY();
        uint256 oldVotingDelay = votingDelay;
        votingDelay = newVotingDelay;

        emit VotingDelaySet(oldVotingDelay, votingDelay);
    }

    /**
     * @notice Owner function for setting the quorum votes basis points
     * @dev newQuorumVotesBPS must be greater than the hardcoded min
     * @param newQuorumVotesBPS new dispute threshold
     */
    function _setQuorumVotesBPS(uint256 newQuorumVotesBPS) external onlyOwner {
        if (newQuorumVotesBPS < MIN_QUORUM_VOTES_BPS || newQuorumVotesBPS > MAX_QUORUM_VOTES_BPS)
            revert INVALID_QUORUM_VOTES_BPS();
        uint256 oldQuorumVotesBPS = quorumVotesBPS;
        quorumVotesBPS = newQuorumVotesBPS;

        emit QuorumVotesBPSSet(oldQuorumVotesBPS, quorumVotesBPS);
    }

    /**
     * @notice Owner function for setting the voting period
     * @param newVotingPeriod new voting period, in blocks
     */
    function _setVotingPeriod(uint256 newVotingPeriod) external onlyOwner {
        if (newVotingPeriod < MIN_VOTING_PERIOD || newVotingPeriod > MAX_VOTING_PERIOD) revert INVALID_VOTING_PERIOD();

        uint256 oldVotingPeriod = votingPeriod;
        votingPeriod = newVotingPeriod;

        emit VotingPeriodSet(oldVotingPeriod, votingPeriod);
    }

    function bps2Uint(uint256 bps, uint256 number) internal pure returns (uint256) {
        return (number * bps) / 10000;
    }

    function appealPeriod(uint256 _disputeID) external view override returns (uint256 start, uint256 end) {
        return (disputes[_disputeID].revealPeriodEndTime, disputes[_disputeID].appealPeriodEndTime);
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
     * @notice Current quorum votes using Noun Total Supply
     * Differs from `GovernerBravo` which uses fixed amount
     */
    function quorumVotes() public view returns (uint256) {
        return bps2Uint(quorumVotesBPS, votingToken.totalSupply());
    }

    function appeal(uint256 _disputeID, bytes calldata _extraData) external payable override {
        // TODO: Implement appeal logic
    }

    function arbitrationCost(bytes calldata _extraData) external view override returns (uint256 cost) {
        // TODO: Implement arbitrationCost logic
    }

    /**
     * @notice Returns the cost of appealing a dispute
     * @param _disputeID The ID of the dispute to appeal
     * @param _extraData Additional data for the appeal (unused in current implementation)
     * @return cost The cost of the appeal
     * @dev TODO: Implement logic to adjust cost based on disputeID and number of appeal rounds
     */
    function appealCost(uint256 _disputeID, bytes calldata _extraData) external view returns (uint256 cost) {
        return baseAppealCost;
    }

    /**
     * @notice Ensures the caller is authorized to upgrade the contract
     * @param _newImpl The new implementation address
     */
    function _authorizeUpgrade(address _newImpl) internal view override onlyOwner {}
}
