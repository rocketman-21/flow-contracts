// Start of Selection
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { FlowTCR } from "../../src/tcr/FlowTCR.sol";
import { ERC20VotesMintable } from "../../src/ERC20VotesMintable.sol";
import { ERC20VotesArbitrator } from "../../src/tcr/ERC20VotesArbitrator.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IGeneralizedTCR } from "../../src/tcr/interfaces/IGeneralizedTCR.sol";
import { IArbitrator } from "../../src/tcr/interfaces/IArbitrator.sol";
import { IArbitrable } from "../../src/tcr/interfaces/IArbitrable.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ArbitratorStorageV1 } from "../../src/tcr/storage/ArbitratorStorageV1.sol";
import { FlowStorageV1 } from "../../src/storage/FlowStorageV1.sol";
import { IManagedFlow } from "../../src/interfaces/IManagedFlow.sol";
import { ERC721FlowTest } from "../erc721-flow/ERC721Flow.t.sol";
import { TCRFactory } from "../../src/tcr/TCRFactory.sol";
import { ITCRFactory } from "../../src/tcr/interfaces/ITCRFactory.sol";
import { RewardPool } from "../../src/RewardPool.sol";

contract FlowTCRTest is ERC721FlowTest {
    // Contracts
    FlowTCR public flowTCR;
    ERC20VotesMintable public erc20Token;
    ERC20VotesArbitrator public arbitrator;

    // Addresses
    address public owner;
    address public governor;
    address public requester;
    address public challenger;
    address public swingVoter;
    address public recipient;

    // Test Parameters
    uint256 public constant SUBMISSION_BASE_DEPOSIT = 100 ether;
    uint256 public constant REMOVAL_BASE_DEPOSIT = 100 ether;
    uint256 public constant SUBMISSION_CHALLENGE_BASE_DEPOSIT = 100 ether;
    uint256 public constant REMOVAL_CHALLENGE_BASE_DEPOSIT = 100 ether;
    uint256 public constant CHALLENGE_PERIOD = 3 days;
    uint256 public constant STAKE_MULTIPLIER_SHARED = 10000; // 100%
    uint256 public constant STAKE_MULTIPLIER_WINNER = 10000; // 100%
    uint256 public constant STAKE_MULTIPLIER_LOSER = 10000; // 100%
    bytes public ITEM_DATA = "0x1234";

    // FlowTCR Parameters
    bytes public constant ARBITRATOR_EXTRA_DATA = "";
    string public constant REGISTRATION_META_EVIDENCE = "meta_evidence/registration";
    string public constant CLEARING_META_EVIDENCE = "meta_evidence/clearing";
    string public constant BASIC_EVIDENCE = "basic_evidence";
    uint256[3] public STAKE_MULTIPLIERS = [
        uint256(STAKE_MULTIPLIER_SHARED),
        uint256(STAKE_MULTIPLIER_WINNER),
        uint256(STAKE_MULTIPLIER_LOSER)
    ];

    // Arbitrator Parameters
    uint256 public constant VOTING_PERIOD = 86_400; // MIN_VOTING_PERIOD
    uint256 public constant VOTING_DELAY = 1; // MIN_VOTING_DELAY
    uint256 public constant REVEAL_PERIOD = 86_400; // MIN_REVEAL_PERIOD
    uint256 public constant APPEAL_PERIOD = 21_600; // MIN_APPEAL_PERIOD
    uint256 public constant APPEAL_COST = 1e18 / 10_000; // MIN_APPEAL_COST
    uint256 public constant ARBITRATION_COST = 1e18 / 10_000; // MIN_ARBITRATION_COST

    function setUp() public virtual override {
        super.setUp();
        governor = address(this);
        requester = makeAddr("requester");
        challenger = makeAddr("challenger");
        owner = makeAddr("owner");
        swingVoter = makeAddr("swingVoter");
        recipient = makeAddr("recipient");

        address rewardPoolImpl = address(new RewardPool());
        address flowTCRImpl = address(new FlowTCR());
        address flowTCRProxy = address(new ERC1967Proxy(flowTCRImpl, ""));
        address arbitratorImpl = address(new ERC20VotesArbitrator());
        address arbitratorProxy = address(new ERC1967Proxy(arbitratorImpl, ""));
        address erc20TokenImpl = address(new ERC20VotesMintable());
        address erc20TokenProxy = address(new ERC1967Proxy(erc20TokenImpl, ""));

        address tcrFactoryImpl = address(new TCRFactory());
        address tcrFactoryProxy = address(new ERC1967Proxy(tcrFactoryImpl, ""));

        ITCRFactory(tcrFactoryProxy).initialize({
            initialOwner: owner,
            flowTCRImplementation_: flowTCRImpl,
            arbitratorImplementation_: arbitratorImpl,
            erc20Implementation_: erc20TokenImpl,
            rewardPoolImplementation_: rewardPoolImpl
        });

        ITEM_DATA = abi.encode(recipient, recipientMetadata, FlowStorageV1.RecipientType.ExternalAccount);

        flowTCR = FlowTCR(flowTCRProxy);
        flowTCR.initialize(
            address(owner),
            IManagedFlow(address(flow)),
            IArbitrator(arbitratorProxy),
            ITCRFactory(tcrFactoryProxy),
            ARBITRATOR_EXTRA_DATA,
            REGISTRATION_META_EVIDENCE,
            CLEARING_META_EVIDENCE,
            governor,
            IERC20(erc20TokenProxy),
            SUBMISSION_BASE_DEPOSIT,
            REMOVAL_BASE_DEPOSIT,
            SUBMISSION_CHALLENGE_BASE_DEPOSIT,
            REMOVAL_CHALLENGE_BASE_DEPOSIT,
            CHALLENGE_PERIOD,
            STAKE_MULTIPLIERS
        );

        erc20Token = ERC20VotesMintable(erc20TokenProxy);
        erc20Token.initialize(governor, governor, "Test Token", "TST");

        arbitrator = ERC20VotesArbitrator(arbitratorProxy);
        arbitrator.initialize(
            address(owner),
            address(erc20Token),
            address(flowTCR),
            VOTING_PERIOD,
            VOTING_DELAY,
            REVEAL_PERIOD,
            APPEAL_PERIOD,
            APPEAL_COST,
            ARBITRATION_COST
        );

        // Mint tokens to test addresses
        erc20Token.mint(requester, 1000 ether);
        erc20Token.mint(challenger, 1000 ether);
        erc20Token.mint(swingVoter, 1000 ether);

        vm.prank(flow.owner());
        flow.setManager(address(flowTCR));

        // Approve FlowTCR to spend tokens
        vm.prank(requester);
        erc20Token.approve(address(flowTCR), type(uint256).max);
        vm.prank(challenger);
        erc20Token.approve(address(flowTCR), type(uint256).max);
    }

    // Helper Functions
    function submitItem(bytes memory _itemData, address _submitter) internal returns (bytes32) {
        vm.prank(_submitter);
        flowTCR.addItem(_itemData);
        bytes32 itemID = keccak256(_itemData);
        return itemID;
    }

    /**
     * @notice Helper function to commit, reveal votes, and execute ruling for a given dispute ID
     * @param disputeID The ID of the dispute to process
     * @param winner The winner of the dispute
     */
    function voteAndExecute(uint256 disputeID, IArbitrable.Party winner) internal {
        // Advance time to reveal period
        advanceTime(VOTING_DELAY + 2);

        // Commit votes
        bytes32 requesterSecretHash = keccak256(abi.encode(uint256(1), "For registration", bytes32("salt")));
        vm.prank(requester);
        arbitrator.commitVote(disputeID, requesterSecretHash);

        bytes32 challengerSecretHash = keccak256(abi.encode(uint256(2), "Against registration", bytes32("salt2")));
        vm.prank(challenger);
        arbitrator.commitVote(disputeID, challengerSecretHash);

        bytes32 swingVoterSecretHash = keccak256(abi.encode(uint256(winner), "Swing vote", bytes32("salt3")));
        vm.prank(swingVoter);
        arbitrator.commitVote(disputeID, swingVoterSecretHash);

        // Advance time to reveal period
        advanceTime(VOTING_PERIOD);

        // Reveal votes
        vm.prank(requester);
        arbitrator.revealVote(disputeID, 1, "For registration", bytes32("salt"));

        vm.prank(challenger);
        arbitrator.revealVote(disputeID, 2, "Against registration", bytes32("salt2"));

        vm.prank(swingVoter);
        arbitrator.revealVote(disputeID, uint256(winner), "Swing vote", bytes32("salt3"));

        // Advance time to end of reveal and appeal periods
        advanceTime(REVEAL_PERIOD + APPEAL_PERIOD);

        // Execute the ruling
        arbitrator.executeRuling(disputeID);
    }

    // Helper function to challenge an item
    function challengeItem(bytes32 _itemID, address _challenger) internal returns (uint256) {
        vm.prank(_challenger);
        flowTCR.challengeRequest(_itemID, BASIC_EVIDENCE);

        // Get the dispute ID from the last request
        (, uint256 disputeID, , , , , , , , ) = flowTCR.getRequestInfo(_itemID, 0);
        return disputeID;
    }

    function advanceTime(uint256 _seconds) internal {
        uint blockTime = 2; // 2 seconds per block
        vm.warp(block.timestamp + _seconds);
        vm.roll(block.number + _seconds / blockTime);
    }
}
