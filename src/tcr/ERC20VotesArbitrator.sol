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
     * @param quorumVotesBPS_ The initial quorum votes threshold in basis points
     */
    function initialize(
        address votingToken_,
        address arbitrable_,
        uint256 votingPeriod_,
        uint256 votingDelay_,
        uint256 revealPeriod_,
        uint256 quorumVotesBPS_
    ) public initializer {
        __Ownable_init();

        if (votingToken_ == address(0)) revert INVALID_VOTING_TOKEN_ADDRESS();
        if (votingPeriod_ < MIN_VOTING_PERIOD || votingPeriod_ > MAX_VOTING_PERIOD) revert INVALID_VOTING_PERIOD();
        if (votingDelay_ < MIN_VOTING_DELAY || votingDelay_ > MAX_VOTING_DELAY) revert INVALID_VOTING_DELAY();
        if (quorumVotesBPS_ < MIN_QUORUM_VOTES_BPS || quorumVotesBPS_ > MAX_QUORUM_VOTES_BPS)
            revert INVALID_QUORUM_VOTES_BPS();
        if (revealPeriod_ < MIN_REVEAL_PERIOD || revealPeriod_ > MAX_REVEAL_PERIOD) revert INVALID_REVEAL_PERIOD();

        emit VotingPeriodSet(votingPeriod, votingPeriod_);
        emit VotingDelaySet(votingDelay, votingDelay_);
        emit QuorumVotesBPSSet(quorumVotesBPS, quorumVotesBPS_);

        votingToken = ERC20VotesMintable(votingToken_);
        arbitrable = IArbitrable(arbitrable_);
        votingPeriod = votingPeriod_;
        votingDelay = votingDelay_;
        quorumVotesBPS = quorumVotesBPS_;
        revealPeriod = revealPeriod_;
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
        newDispute.votingStartBlock = block.number + votingDelay;
        newDispute.votingEndBlock = newDispute.votingStartBlock + votingPeriod;
        newDispute.revealPeriodEndBlock = newDispute.votingEndBlock + revealPeriod;
        newDispute.choices = _choices;
        newDispute.votes = 0; // total votes cast
        newDispute.extraData = _extraData;
        newDispute.executed = false;
        newDispute.creationBlock = block.number;
        newDispute.quorumVotes = quorumVotes();
        newDispute.totalSupply = votingToken.totalSupply();

        /// @notice Maintains backwards compatibility with GovernorBravo events
        emit DisputeCreated(
            newDispute.id,
            address(arbitrable),
            newDispute.votingStartBlock,
            newDispute.votingEndBlock,
            newDispute.revealPeriodEndBlock,
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
    function state(uint256 disputeId) public view returns (DisputeState) {
        require(disputeCount >= disputeId, "NounsDAO::state: invalid dispute id");
        Dispute storage dispute = disputes[disputeId];
        if (block.number <= dispute.votingStartBlock) {
            return DisputeState.Pending;
        } else if (block.number <= dispute.votingEndBlock) {
            return DisputeState.Active;
        } else if (block.number <= dispute.revealPeriodEndBlock) {
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
    function _castVoteInternal(address voter, uint256 disputeId, uint8 choice) internal returns (uint256) {
        require(state(disputeId) == DisputeState.Active, "NounsDAO::castVoteInternal: voting is closed");
        require(choice <= disputes[disputeId].choices, "NounsDAO::castVoteInternal: invalid vote type");
        Dispute storage dispute = disputes[disputeId];
        Receipt storage receipt = dispute.receipts[voter];
        require(receipt.hasVoted == false, "NounsDAO::castVoteInternal: voter already voted");
        uint256 votes = votingToken.getPastVotes(voter, dispute.creationBlock);

        dispute.votes += votes;

        receipt.hasVoted = true;
        receipt.choice = choice;
        receipt.votes = votes;

        return votes;
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

    /**
     * @notice Modifier to restrict function access to only the arbitrable contract
     */
    modifier onlyArbitrable() {
        if (msg.sender != address(arbitrable)) revert ONLY_ARBITRABLE();
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

    function appealCost(uint256 _disputeID, bytes calldata _extraData) external view override returns (uint256 cost) {
        // TODO: Implement appealCost logic
    }

    function appealPeriod(uint256 _disputeID) external view override returns (uint256 start, uint256 end) {
        // TODO: Implement appealPeriod logic
    }

    function disputeStatus(uint256 _disputeID) external view override returns (DisputeStatus status) {
        // TODO: Implement disputeStatus logic
    }

    function currentRuling(uint256 _disputeID) external view override returns (uint256 ruling) {
        // TODO: Implement currentRuling logic
    }

    /**
     * @notice Ensures the caller is authorized to upgrade the contract
     * @param _newImpl The new implementation address
     */
    function _authorizeUpgrade(address _newImpl) internal view override onlyOwner {}
}
