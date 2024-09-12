// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20VotesArbitrator } from "./interfaces/IERC20VotesArbitrator.sol";
import { IArbitrable } from "./interfaces/IArbitrable.sol";
import { ArbitratorStorageV1 } from "./storage/ArbitratorStorageV1.sol";

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
     * @param votingPeriod_ The initial voting period
     * @param votingDelay_ The initial voting delay
     * @param quorumVotesBPS_ The initial quorum votes threshold in basis points
     */
    function initialize(
        address votingToken_,
        uint256 votingPeriod_,
        uint256 votingDelay_,
        uint256 quorumVotesBPS_
    ) public initializer {
        __Ownable_init();

        if (votingToken_ == address(0)) revert INVALID_VOTING_TOKEN_ADDRESS();
        if (votingPeriod_ < MIN_VOTING_PERIOD || votingPeriod_ > MAX_VOTING_PERIOD) revert INVALID_VOTING_PERIOD();
        if (votingDelay_ < MIN_VOTING_DELAY || votingDelay_ > MAX_VOTING_DELAY) revert INVALID_VOTING_DELAY();
        if (quorumVotesBPS_ < MIN_QUORUM_VOTES_BPS || quorumVotesBPS_ > MAX_QUORUM_VOTES_BPS)
            revert INVALID_QUORUM_VOTES_BPS();

        emit VotingPeriodSet(votingPeriod, votingPeriod_);
        emit VotingDelaySet(votingDelay, votingDelay_);
        emit QuorumVotesBPSSet(quorumVotesBPS, quorumVotesBPS_);

        votingToken = votingToken_;
        votingPeriod = votingPeriod_;
        votingDelay = votingDelay_;
        quorumVotesBPS = quorumVotesBPS_;
    }

    /**
     * @notice Function used to create a new dispute.
     * @param description String description of the dispute
     * @return Dispute id of new dispute
     */
    function dispute(string memory description) public returns (uint256) {
        disputeCount++;
        Dispute storage newDispute = disputes[disputeCount];

        newDispute.id = disputeCount;
        newDispute.disputer = msg.sender;
        newDispute.eta = 0;
        newDispute.startBlock = block.number + votingDelay;
        newDispute.endBlock = newDispute.startBlock + votingPeriod;
        newDispute.forVotes = 0;
        newDispute.againstVotes = 0;
        newDispute.abstainVotes = 0;
        newDispute.executed = false;
        newDispute.creationBlock = block.number;
        newDispute.quorumVotes = quorumVotes();
        newDispute.totalSupply = votingToken.totalSupply();

        latestDisputeIds[newDispute.disputer] = newDispute.id;

        /// @notice Maintains backwards compatibility with GovernorBravo events
        emit DisputeCreated(newDispute.id, msg.sender, newDispute.startBlock, newDispute.endBlock, description);

        emit DisputeCreatedWithRequirements(
            newDispute.id,
            msg.sender,
            newDispute.startBlock,
            newDispute.endBlock,
            description
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
        if (block.number <= dispute.startBlock) {
            return DisputeState.Pending;
        } else if (block.number <= dispute.endBlock) {
            return DisputeState.Active;
        } else if (dispute.forVotes <= dispute.againstVotes || dispute.forVotes < dispute.quorumVotes) {
            return DisputeState.Defeated;
        } else if (dispute.eta == 0) {
            return DisputeState.Succeeded;
        } else if (dispute.executed) {
            return DisputeState.Executed;
        }
    }

    /**
     * @notice Cast a vote for a dispute
     * @param disputeId The id of the dispute to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     */
    function castVote(uint256 disputeId, uint8 support) external {
        emit VoteCast(msg.sender, disputeId, support, castVoteInternal(msg.sender, disputeId, support), "");
    }

    /**
     * @notice Cast a vote for a dispute with a reason
     * @param disputeId The id of the dispute to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the voter
     */
    function castVoteWithReason(uint256 disputeId, uint8 support, string calldata reason) external {
        emit VoteCast(msg.sender, disputeId, support, castVoteInternal(msg.sender, disputeId, support), reason);
    }

    /**
     * @notice Internal function that caries out voting logic
     * @param voter The voter that is casting their vote
     * @param disputeId The id of the dispute to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @return The number of votes cast
     */
    function castVoteInternal(address voter, uint256 disputeId, uint8 support) internal returns (uint96) {
        require(state(disputeId) == DisputeState.Active, "NounsDAO::castVoteInternal: voting is closed");
        require(support <= 2, "NounsDAO::castVoteInternal: invalid vote type");
        Dispute storage dispute = disputes[disputeId];
        Receipt storage receipt = dispute.receipts[voter];
        require(receipt.hasVoted == false, "NounsDAO::castVoteInternal: voter already voted");

        /// @notice: Unlike GovernerBravo, votes are considered from the block the dispute was created in order to normalize quorumVotes and disputeThreshold metrics
        uint96 votes = nouns.getPriorVotes(voter, dispute.creationBlock);

        if (support == 0) {
            dispute.againstVotes = dispute.againstVotes + votes;
        } else if (support == 1) {
            dispute.forVotes = dispute.forVotes + votes;
        } else if (support == 2) {
            dispute.abstainVotes = dispute.abstainVotes + votes;
        }

        receipt.hasVoted = true;
        receipt.support = support;
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
     * @notice Current quorum votes using Noun Total Supply
     * Differs from `GovernerBravo` which uses fixed amount
     */
    function quorumVotes() public view returns (uint256) {
        return bps2Uint(quorumVotesBPS, votingToken.totalSupply());
    }

    function createDispute(uint256 _choices, bytes calldata _extraData) external override returns (uint256 disputeID) {
        // TODO: Implement createDispute logic
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
