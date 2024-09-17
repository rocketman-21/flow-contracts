// Start of Selection
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { GeneralizedTCR } from "../../src/tcr/GeneralizedTCR.sol";
import { ERC20VotesMintable } from "../../src/ERC20VotesMintable.sol";
import { ERC20VotesArbitrator } from "../../src/tcr/ERC20VotesArbitrator.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IGeneralizedTCR } from "../../src/tcr/interfaces/IGeneralizedTCR.sol";
import { IArbitrator } from "../../src/tcr/interfaces/IArbitrator.sol";
import { IArbitrable } from "../../src/tcr/interfaces/IArbitrable.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { ArbitratorStorageV1 } from "../../src/tcr/storage/ArbitratorStorageV1.sol";

contract GeneralizedTCRTest is Test {
    // Contracts
    GeneralizedTCR public generalizedTCR;
    ERC20VotesMintable public erc20Token;
    ERC20VotesArbitrator public arbitrator;

    // Addresses
    address public owner;
    address public governor;
    address public requester;
    address public challenger;
    address public swingVoter;

    // Test Parameters
    uint256 public constant SUBMISSION_BASE_DEPOSIT = 100 ether;
    uint256 public constant REMOVAL_BASE_DEPOSIT = 100 ether;
    uint256 public constant SUBMISSION_CHALLENGE_BASE_DEPOSIT = 100 ether;
    uint256 public constant REMOVAL_CHALLENGE_BASE_DEPOSIT = 100 ether;
    uint256 public constant CHALLENGE_PERIOD = 3 days;
    uint256 public constant STAKE_MULTIPLIER_SHARED = 10000; // 100%
    uint256 public constant STAKE_MULTIPLIER_WINNER = 10000; // 100%
    uint256 public constant STAKE_MULTIPLIER_LOSER = 10000; // 100%
    bytes public constant ITEM_DATA = "0x1234";

    // GeneralizedTCR Parameters
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

    function setUp() public {
        governor = address(this);
        requester = makeAddr("requester");
        challenger = makeAddr("challenger");
        owner = makeAddr("owner");
        swingVoter = makeAddr("swingVoter");

        address generalizedTCRImpl = address(new GeneralizedTCR());
        address generalizedTCRProxy = address(new ERC1967Proxy(generalizedTCRImpl, ""));
        address arbitratorImpl = address(new ERC20VotesArbitrator());
        address arbitratorProxy = address(new ERC1967Proxy(arbitratorImpl, ""));
        address erc20TokenImpl = address(new ERC20VotesMintable());
        address erc20TokenProxy = address(new ERC1967Proxy(erc20TokenImpl, ""));

        generalizedTCR = GeneralizedTCR(generalizedTCRProxy);
        generalizedTCR.initialize(
            IArbitrator(arbitratorProxy),
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
            address(erc20Token),
            address(generalizedTCR),
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

        // Approve GeneralizedTCR to spend tokens
        vm.prank(requester);
        erc20Token.approve(address(generalizedTCR), type(uint256).max);
        vm.prank(challenger);
        erc20Token.approve(address(generalizedTCR), type(uint256).max);
    }

    // Helper Functions
    function submitItem(bytes memory _itemData, address _submitter) internal returns (bytes32) {
        vm.prank(_submitter);
        generalizedTCR.addItem(_itemData);
        bytes32 itemID = keccak256(_itemData);
        return itemID;
    }

    function challengeItem(bytes32 _itemID, address _challenger) internal {
        vm.prank(_challenger);
        generalizedTCR.challengeRequest(_itemID, BASIC_EVIDENCE);
    }

    function advanceTime(uint256 _seconds) internal {
        uint blockTime = 2; // 2 seconds per block
        vm.warp(block.timestamp + _seconds);
        vm.roll(block.number + _seconds / blockTime);
    }
}
