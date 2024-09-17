// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { Test } from "forge-std/Test.sol";
import { ERC20VotesArbitrator } from "../../src/tcr/ERC20VotesArbitrator.sol";
import { ERC20VotesMintable } from "../../src/ERC20VotesMintable.sol";
import { GeneralizedTCR } from "../../src/tcr/GeneralizedTCR.sol";
import { IArbitrable } from "../../src/tcr/interfaces/IArbitrable.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20VotesArbitrator } from "../../src/tcr/interfaces/IERC20VotesArbitrator.sol";
import { IArbitrator } from "../../src/tcr/interfaces/IArbitrator.sol";

contract ERC20VotesArbitratorTest is Test {
    // Contracts
    ERC20VotesArbitrator public arbitrator;
    ERC20VotesMintable public erc20Token;
    GeneralizedTCR public generalizedTCR;

    // Addresses
    address public owner;
    address public voter1;
    address public voter2;
    address public voter3;
    address public requester;
    address public challenger;

    // Test Parameters
    uint256 public constant VOTING_PERIOD = 86_400; // MIN_VOTING_PERIOD
    uint256 public constant VOTING_DELAY = 1; // MIN_VOTING_DELAY
    uint256 public constant REVEAL_PERIOD = 86_400; // MIN_REVEAL_PERIOD
    uint256 public constant APPEAL_PERIOD = 21_600; // MIN_APPEAL_PERIOD
    uint256 public constant APPEAL_COST = 1e18 / 10_000; // MIN_APPEAL_COST
    uint256 public constant ARBITRATION_COST = 1e18 / 10_000; // MIN_ARBITRATION_COST

    // GeneralizedTCR Parameters
    bytes public constant ARBITRATOR_EXTRA_DATA = "";
    bytes public constant ITEM_DATA = "item_data";
    string public constant BASIC_EVIDENCE = "basic_evidence";
    string public constant REGISTRATION_META_EVIDENCE = "meta_evidence/registration";
    string public constant CLEARING_META_EVIDENCE = "meta_evidence/clearing";
    uint256 public constant SUBMISSION_BASE_DEPOSIT = 100 ether;
    uint256 public constant REMOVAL_BASE_DEPOSIT = 100 ether;
    uint256 public constant SUBMISSION_CHALLENGE_BASE_DEPOSIT = 100 ether;
    uint256 public constant REMOVAL_CHALLENGE_BASE_DEPOSIT = 100 ether;
    uint256 public constant CHALLENGE_PERIOD = 3 days;
    uint256[3] public STAKE_MULTIPLIERS = [10000, 10000, 10000]; // 100% for all

    function setUp() public {
        owner = address(this);
        voter1 = makeAddr("voter1");
        voter2 = makeAddr("voter2");
        voter3 = makeAddr("voter3");
        requester = makeAddr("requester");
        challenger = makeAddr("challenger");

        address arbitratorImpl = address(new ERC20VotesArbitrator());
        address arbitratorProxy = address(new ERC1967Proxy(arbitratorImpl, ""));
        address erc20TokenImpl = address(new ERC20VotesMintable());
        address erc20TokenProxy = address(new ERC1967Proxy(erc20TokenImpl, ""));
        address generalizedTCRImpl = address(new GeneralizedTCR());
        address generalizedTCRProxy = address(new ERC1967Proxy(generalizedTCRImpl, ""));

        arbitrator = ERC20VotesArbitrator(arbitratorProxy);
        erc20Token = ERC20VotesMintable(erc20TokenProxy);
        generalizedTCR = GeneralizedTCR(generalizedTCRProxy);

        erc20Token.initialize(owner, owner, "Test Token", "TST");

        generalizedTCR.initialize(
            IArbitrator(arbitratorProxy),
            ARBITRATOR_EXTRA_DATA,
            REGISTRATION_META_EVIDENCE,
            CLEARING_META_EVIDENCE,
            owner,
            IERC20(address(erc20Token)),
            SUBMISSION_BASE_DEPOSIT,
            REMOVAL_BASE_DEPOSIT,
            SUBMISSION_CHALLENGE_BASE_DEPOSIT,
            REMOVAL_CHALLENGE_BASE_DEPOSIT,
            CHALLENGE_PERIOD,
            STAKE_MULTIPLIERS
        );

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
        erc20Token.mint(voter1, 1000 ether);
        erc20Token.mint(voter2, 1000 ether);
        erc20Token.mint(voter3, 1000 ether);
        erc20Token.mint(requester, 1000 ether);
        erc20Token.mint(challenger, 1000 ether);

        // Approve arbitrator to spend tokens
        vm.prank(voter1);
        erc20Token.approve(address(generalizedTCR), type(uint256).max);
        vm.prank(voter2);
        erc20Token.approve(address(generalizedTCR), type(uint256).max);
        vm.prank(voter3);
        erc20Token.approve(address(generalizedTCR), type(uint256).max);
        vm.prank(requester);
        erc20Token.approve(address(generalizedTCR), type(uint256).max);
        vm.prank(challenger);
        erc20Token.approve(address(generalizedTCR), type(uint256).max);
    }

    function commitVote(uint256 disputeID, address voter, uint256 choice, string memory reason, bytes32 salt) internal {
        bytes32 secretHash = keccak256(abi.encode(choice, reason, salt));
        vm.prank(voter);
        arbitrator.commitVote(disputeID, secretHash);
    }

    function revealVote(uint256 disputeID, address voter, uint256 choice, string memory reason, bytes32 salt) internal {
        vm.prank(voter);
        arbitrator.revealVote(disputeID, choice, bytes(reason), salt);
    }

    function advanceTime(uint256 _seconds) internal {
        uint256 blockTime = 2;
        vm.warp(block.timestamp + _seconds);
        vm.roll(block.number + _seconds / blockTime);
    }

    // Helper function to submit an item
    function submitItem(bytes memory _itemData, address _submitter) internal returns (bytes32) {
        vm.prank(_submitter);
        generalizedTCR.addItem(_itemData);
        bytes32 itemID = keccak256(_itemData);
        return itemID;
    }

    // Helper function to challenge an item
    function challengeItem(bytes32 _itemID, address _challenger) internal returns (uint256) {
        vm.prank(_challenger);
        generalizedTCR.challengeRequest(_itemID, BASIC_EVIDENCE);

        // Get the dispute ID from the last request
        (, uint256 disputeID, , , , , , , , ) = generalizedTCR.getRequestInfo(_itemID, 0);
        return disputeID;
    }

    // Helper function to submit an item and challenge it
    function submitItemAndChallenge(
        bytes memory _itemData,
        address _requester,
        address _challenger
    ) internal returns (bytes32 itemID, uint256 disputeID) {
        itemID = submitItem(_itemData, _requester);
        disputeID = challengeItem(itemID, _challenger);
    }
}
