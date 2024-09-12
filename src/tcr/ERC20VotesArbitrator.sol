// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IERC20VotesArbitrator } from "./interfaces/IERC20VotesArbitrator.sol";
import { IArbitrable } from "./interfaces/IArbitrable.sol";
import { ArbitratorStorageV1 } from "./storage/ArbitratorStorageV1.sol";

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract PrivateERC20VotesArbitrator is
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
     */
    function initialize(address votingToken_, uint256 votingPeriod_, uint256 votingDelay_) public initializer {
        __Ownable_init();

        if (votingToken_ == address(0)) revert INVALID_VOTING_TOKEN_ADDRESS();
        if (votingPeriod_ < MIN_VOTING_PERIOD || votingPeriod_ > MAX_VOTING_PERIOD) revert INVALID_VOTING_PERIOD();
        if (votingDelay_ < MIN_VOTING_DELAY || votingDelay_ > MAX_VOTING_DELAY) revert INVALID_VOTING_DELAY();

        emit VotingPeriodSet(votingPeriod, votingPeriod_);
        emit VotingDelaySet(votingDelay, votingDelay_);

        votingToken = votingToken_;
        votingPeriod = votingPeriod_;
        votingDelay = votingDelay_;
    }

    /**
     * @notice Function used to propose a new proposal.
     * @param description String description of the proposal
     * @return Proposal id of new proposal
     */
    function propose(string memory description) public returns (uint256) {
        proposalCount++;
        Proposal storage newProposal = proposals[proposalCount];

        newProposal.id = proposalCount;
        newProposal.proposer = msg.sender;
        newProposal.eta = 0;
        newProposal.startBlock = block.number + votingDelay;
        newProposal.endBlock = newProposal.startBlock + votingPeriod;
        newProposal.forVotes = 0;
        newProposal.againstVotes = 0;
        newProposal.abstainVotes = 0;
        newProposal.executed = false;
        newProposal.creationBlock = block.number;
        newProposal.totalSupply = votingToken.totalSupply();

        latestProposalIds[newProposal.proposer] = newProposal.id;

        /// @notice Maintains backwards compatibility with GovernorBravo events
        emit ProposalCreated(newProposal.id, msg.sender, newProposal.startBlock, newProposal.endBlock, description);

        emit ProposalCreatedWithRequirements(
            newProposal.id,
            msg.sender,
            newProposal.startBlock,
            newProposal.endBlock,
            description
        );

        return newProposal.id;
    }

    /**
     * @notice Gets the receipt for a voter on a given proposal
     * @param proposalId the id of proposal
     * @param voter The address of the voter
     * @return The voting receipt
     */
    function getReceipt(uint256 proposalId, address voter) external view returns (Receipt memory) {
        return proposals[proposalId].receipts[voter];
    }

    /**
     * @notice Gets the state of a proposal
     * @param proposalId The id of the proposal
     * @return Proposal state
     */
    function state(uint256 proposalId) public view returns (ProposalState) {
        require(proposalCount >= proposalId, "NounsDAO::state: invalid proposal id");
        Proposal storage proposal = proposals[proposalId];
        if (block.number <= proposal.startBlock) {
            return ProposalState.Pending;
        } else if (block.number <= proposal.endBlock) {
            return ProposalState.Active;
        } else if (proposal.forVotes <= proposal.againstVotes) {
            return ProposalState.Defeated;
        } else if (proposal.eta == 0) {
            return ProposalState.Succeeded;
        } else if (proposal.executed) {
            return ProposalState.Executed;
        }
    }

    /**
     * @notice Cast a vote for a proposal
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     */
    function castVote(uint256 proposalId, uint8 support) external {
        emit VoteCast(msg.sender, proposalId, support, castVoteInternal(msg.sender, proposalId, support), "");
    }

    /**
     * @notice Cast a vote for a proposal with a reason
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @param reason The reason given for the vote by the voter
     */
    function castVoteWithReason(uint256 proposalId, uint8 support, string calldata reason) external {
        emit VoteCast(msg.sender, proposalId, support, castVoteInternal(msg.sender, proposalId, support), reason);
    }

    /**
     * @notice Internal function that caries out voting logic
     * @param voter The voter that is casting their vote
     * @param proposalId The id of the proposal to vote on
     * @param support The support value for the vote. 0=against, 1=for, 2=abstain
     * @return The number of votes cast
     */
    function castVoteInternal(address voter, uint256 proposalId, uint8 support) internal returns (uint96) {
        require(state(proposalId) == ProposalState.Active, "NounsDAO::castVoteInternal: voting is closed");
        require(support <= 2, "NounsDAO::castVoteInternal: invalid vote type");
        Proposal storage proposal = proposals[proposalId];
        Receipt storage receipt = proposal.receipts[voter];
        require(receipt.hasVoted == false, "NounsDAO::castVoteInternal: voter already voted");

        /// @notice: Unlike GovernerBravo, votes are considered from the block the proposal was created in order to normalize quorumVotes and proposalThreshold metrics
        uint96 votes = nouns.getPriorVotes(voter, proposal.creationBlock);

        if (support == 0) {
            proposal.againstVotes = proposal.againstVotes + votes;
        } else if (support == 1) {
            proposal.forVotes = proposal.forVotes + votes;
        } else if (support == 2) {
            proposal.abstainVotes = proposal.abstainVotes + votes;
        }

        receipt.hasVoted = true;
        receipt.support = support;
        receipt.votes = votes;

        return votes;
    }

    /**
     * @notice Admin function for setting the voting delay
     * @param newVotingDelay new voting delay, in blocks
     */
    function _setVotingDelay(uint256 newVotingDelay) external {
        require(msg.sender == admin, "NounsDAO::_setVotingDelay: admin only");
        require(
            newVotingDelay >= MIN_VOTING_DELAY && newVotingDelay <= MAX_VOTING_DELAY,
            "NounsDAO::_setVotingDelay: invalid voting delay"
        );
        uint256 oldVotingDelay = votingDelay;
        votingDelay = newVotingDelay;

        emit VotingDelaySet(oldVotingDelay, votingDelay);
    }

    /**
     * @notice Admin function for setting the voting period
     * @param newVotingPeriod new voting period, in blocks
     */
    function _setVotingPeriod(uint256 newVotingPeriod) external {
        require(msg.sender == admin, "NounsDAO::_setVotingPeriod: admin only");
        require(
            newVotingPeriod >= MIN_VOTING_PERIOD && newVotingPeriod <= MAX_VOTING_PERIOD,
            "NounsDAO::_setVotingPeriod: invalid voting period"
        );
        uint256 oldVotingPeriod = votingPeriod;
        votingPeriod = newVotingPeriod;

        emit VotingPeriodSet(oldVotingPeriod, votingPeriod);
    }

    function bps2Uint(uint256 bps, uint256 number) internal pure returns (uint256) {
        return (number * bps) / 10000;
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
