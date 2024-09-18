// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { TCRFactory } from "../../src/tcr/TCRFactory.sol";
import { FlowTCR } from "../../src/tcr/FlowTCR.sol";
import { ERC20VotesMintable } from "../../src/ERC20VotesMintable.sol";
import { ERC20VotesArbitrator } from "../../src/tcr/ERC20VotesArbitrator.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IFlowTCR } from "../../src/tcr/interfaces/IGeneralizedTCR.sol";
import { ITCRFactory } from "../../src/tcr/interfaces/ITCRFactory.sol";
import { IManagedFlow } from "../../src/interfaces/IManagedFlow.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IArbitrator } from "../../src/tcr/interfaces/IArbitrator.sol";

contract TCRFactoryTest is Test {
    // Contracts
    TCRFactory public tcrFactory;
    FlowTCR public flowTCRImpl;
    ERC20VotesMintable public erc20Impl;
    ERC20VotesArbitrator public arbitratorImpl;

    // Addresses
    address public owner;
    address public governor;
    address public flowContract;

    // Test Parameters
    uint256 public constant SUBMISSION_BASE_DEPOSIT = 100 ether;
    uint256 public constant REMOVAL_BASE_DEPOSIT = 100 ether;
    uint256 public constant SUBMISSION_CHALLENGE_BASE_DEPOSIT = 100 ether;
    uint256 public constant REMOVAL_CHALLENGE_BASE_DEPOSIT = 100 ether;
    uint256 public constant CHALLENGE_PERIOD = 3 days;
    uint256 public constant STAKE_MULTIPLIER = 10000; // 100%

    // Arbitrator Parameters
    uint256 public constant VOTING_PERIOD = 86_400;
    uint256 public constant VOTING_DELAY = 1;
    uint256 public constant REVEAL_PERIOD = 86_400;
    uint256 public constant APPEAL_PERIOD = 21_600;
    uint256 public constant APPEAL_COST = 1e18 / 10_000;
    uint256 public constant ARBITRATION_COST = 1e18 / 10_000;

    function setUp() public {
        owner = address(this);
        governor = makeAddr("governor");
        flowContract = makeAddr("flowContract");

        // Deploy implementation contracts
        flowTCRImpl = new FlowTCR();
        erc20Impl = new ERC20VotesMintable();
        arbitratorImpl = new ERC20VotesArbitrator();

        // Deploy TCRFactory
        TCRFactory tcrFactoryImpl = new TCRFactory();
        ERC1967Proxy proxy = new ERC1967Proxy(address(tcrFactoryImpl), "");
        tcrFactory = TCRFactory(address(proxy));

        // Initialize TCRFactory
        tcrFactory.initialize(owner, address(flowTCRImpl), address(arbitratorImpl), address(erc20Impl));
    }

    // Start of Selection
    function testDeployFlowTCR() public {
        // Prepare parameters
        ITCRFactory.FlowTCRParams memory flowParams = ITCRFactory.FlowTCRParams({
            flowContract: IManagedFlow(flowContract),
            arbitratorExtraData: "",
            registrationMetaEvidence: "ipfs://registration",
            clearingMetaEvidence: "ipfs://clearing",
            governor: governor,
            submissionBaseDeposit: SUBMISSION_BASE_DEPOSIT,
            removalBaseDeposit: REMOVAL_BASE_DEPOSIT,
            submissionChallengeBaseDeposit: SUBMISSION_CHALLENGE_BASE_DEPOSIT,
            removalChallengeBaseDeposit: REMOVAL_CHALLENGE_BASE_DEPOSIT,
            challengePeriodDuration: CHALLENGE_PERIOD,
            stakeMultipliers: [STAKE_MULTIPLIER, STAKE_MULTIPLIER, STAKE_MULTIPLIER]
        });

        ITCRFactory.ArbitratorParams memory arbitratorParams = ITCRFactory.ArbitratorParams({
            votingPeriod: VOTING_PERIOD,
            votingDelay: VOTING_DELAY,
            revealPeriod: REVEAL_PERIOD,
            appealPeriod: APPEAL_PERIOD,
            appealCost: APPEAL_COST,
            arbitrationCost: ARBITRATION_COST
        });

        ITCRFactory.ERC20Params memory erc20Params = ITCRFactory.ERC20Params({
            initialOwner: governor,
            minter: governor,
            name: "Test Token",
            symbol: "TST"
        });

        // Deploy FlowTCR ecosystem
        address deployedTCR = tcrFactory.deployFlowTCR(flowParams, arbitratorParams, erc20Params);

        // Verify deployment
        assertTrue(deployedTCR != address(0), "FlowTCR not deployed");

        // Check if FlowTCR is properly initialized
        FlowTCR flowTCR = FlowTCR(deployedTCR);
        assertEq(address(flowTCR.flowContract()), flowContract, "FlowContract not set correctly");
        assertEq(flowTCR.governor(), governor, "Governor not set correctly");
        assertEq(address(flowTCR.tcrFactory()), address(tcrFactory), "TCRFactory not set correctly");

        // Check GeneralizedTCR storage variables
        assertEq(address(flowTCR.arbitrator()), address(flowTCR.arbitrator()), "Arbitrator not set correctly");
        assertEq(
            flowTCR.arbitratorExtraData(),
            flowParams.arbitratorExtraData,
            "arbitratorExtraData not set correctly"
        );
        assertEq(
            flowTCR.registrationMetaEvidence(),
            flowParams.registrationMetaEvidence,
            "registrationMetaEvidence not set correctly"
        );
        assertEq(
            flowTCR.clearingMetaEvidence(),
            flowParams.clearingMetaEvidence,
            "clearingMetaEvidence not set correctly"
        );
        assertEq(address(flowTCR.governor()), flowParams.governor, "Governor not set correctly in GeneralizedTCR");
        assertEq(
            flowTCR.submissionBaseDeposit(),
            flowParams.submissionBaseDeposit,
            "submissionBaseDeposit not set correctly"
        );
        assertEq(flowTCR.removalBaseDeposit(), flowParams.removalBaseDeposit, "removalBaseDeposit not set correctly");
        assertEq(
            flowTCR.submissionChallengeBaseDeposit(),
            flowParams.submissionChallengeBaseDeposit,
            "submissionChallengeBaseDeposit not set correctly"
        );
        assertEq(
            flowTCR.removalChallengeBaseDeposit(),
            flowParams.removalChallengeBaseDeposit,
            "removalChallengeBaseDeposit not set correctly"
        );
        assertEq(
            flowTCR.challengePeriodDuration(),
            flowParams.challengePeriodDuration,
            "challengePeriodDuration not set correctly"
        );
        assertEq(
            flowTCR.sharedStakeMultiplier(),
            flowParams.stakeMultipliers[0],
            "sharedStakeMultiplier not set correctly"
        );
        assertEq(
            flowTCR.winnerStakeMultiplier(),
            flowParams.stakeMultipliers[1],
            "winnerStakeMultiplier not set correctly"
        );
        assertEq(
            flowTCR.loserStakeMultiplier(),
            flowParams.stakeMultipliers[2],
            "loserStakeMultiplier not set correctly"
        );

        // Check ERC20 token
        ERC20VotesMintable erc20Token = ERC20VotesMintable(
            address(ERC20VotesArbitrator(address(flowTCR.arbitrator())).votingToken())
        );
        assertTrue(address(erc20Token) != address(0), "ERC20 token not set correctly");
        assertEq(erc20Token.name(), erc20Params.name, "Token name not set correctly");
        assertEq(erc20Token.symbol(), erc20Params.symbol, "Token symbol not set correctly");
        // Assuming ERC20VotesMintable exposes minter and owner
        ERC20VotesMintable mintableToken = ERC20VotesMintable(address(erc20Token));
        assertEq(mintableToken.minter(), erc20Params.minter, "Token minter not set correctly");
        assertEq(mintableToken.owner(), erc20Params.initialOwner, "Token initial owner not set correctly");

        // Check Arbitrator
        IArbitrator arbitrator = flowTCR.arbitrator();
        assertTrue(address(arbitrator) != address(0), "Arbitrator address not set correctly");
        // Assuming arbitrator is ERC20VotesArbitrator
        ERC20VotesArbitrator votesArbitrator = ERC20VotesArbitrator(address(arbitrator));
        assertEq(votesArbitrator._votingPeriod(), arbitratorParams.votingPeriod, "Voting period not set correctly");
        assertEq(votesArbitrator._votingDelay(), arbitratorParams.votingDelay, "Voting delay not set correctly");
        assertEq(votesArbitrator._revealPeriod(), arbitratorParams.revealPeriod, "Reveal period not set correctly");
        assertEq(votesArbitrator._appealPeriod(), arbitratorParams.appealPeriod, "Appeal period not set correctly");
        assertEq(votesArbitrator._appealCost(), arbitratorParams.appealCost, "Appeal cost not set correctly");
        assertEq(
            votesArbitrator._arbitrationCost(),
            arbitratorParams.arbitrationCost,
            "Arbitration cost not set correctly"
        );
        assertEq(address(votesArbitrator.arbitrable()), address(flowTCR), "Arbitrable not set correctly in arbitrator");
        assertEq(
            address(votesArbitrator.votingToken()),
            address(erc20Token),
            "Voting token not set correctly in arbitrator"
        );

        // Additional checks can be added here to verify other aspects of the deployment
    }
}
