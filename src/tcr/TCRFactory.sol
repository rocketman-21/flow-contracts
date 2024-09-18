// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IManagedFlow } from "../interfaces/IManagedFlow.sol";
import { IArbitrator } from "./interfaces/IArbitrator.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IFlowTCR } from "./interfaces/IGeneralizedTCR.sol";
import { IERC20Mintable } from "../interfaces/IERC20Mintable.sol";
import { IOwnable2Step } from "../interfaces/IOwnable2Step.sol";
import { IERC20VotesArbitrator } from "./interfaces/IERC20VotesArbitrator.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ITCRFactory } from "./interfaces/ITCRFactory.sol";

/**
 * @title TCRFactory
 * @dev Factory contract for deploying and initializing FlowTCR, ERC20VotesArbitrator, and ERC20VotesMintable contracts
 * @notice This contract allows for the creation of new TCR ecosystems with associated arbitration and token contracts
 */
contract TCRFactory is ITCRFactory, Ownable2StepUpgradeable, UUPSUpgradeable {
    /// @notice The address of the FlowTCR implementation contract
    address public flowTCRImplementation;
    /// @notice The address of the ERC20VotesArbitrator implementation contract
    address public arbitratorImplementation;
    /// @notice The address of the ERC20VotesMintable implementation contract
    address public erc20Implementation;

    /// @dev Initializer function for the contract
    constructor() initializer {}

    /**
     * @notice Initializes the TCRFactory contract
     * @dev Sets up the contract with an initial owner and deploys implementation contracts
     * @param initialOwner The address that will be set as the initial owner of the contract
     * @param flowTCRImplementation_ The address of the FlowTCR implementation contract
     * @param arbitratorImplementation_ The address of the ERC20VotesArbitrator implementation contract
     * @param erc20Implementation_ The address of the ERC20VotesMintable implementation contract
     */
    function initialize(
        address initialOwner,
        address flowTCRImplementation_,
        address arbitratorImplementation_,
        address erc20Implementation_
    ) public initializer {
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
        _transferOwnership(initialOwner);

        flowTCRImplementation = flowTCRImplementation_;
        arbitratorImplementation = arbitratorImplementation_;
        erc20Implementation = erc20Implementation_;
    }

    /**
     * @notice Deploys a new FlowTCR ecosystem with associated contracts
     * @dev Creates and initializes FlowTCR, ERC20VotesArbitrator, and ERC20VotesMintable contracts
     * @param params Parameters for initializing the FlowTCR contract
     * @param arbitratorParams Parameters for initializing the ERC20VotesArbitrator contract
     * @param erc20Params Parameters for initializing the ERC20VotesMintable contract
     * @return The address of the newly deployed FlowTCR proxy contract
     */
    function deployFlowTCR(
        FlowTCRParams memory params,
        ArbitratorParams memory arbitratorParams,
        ERC20Params memory erc20Params
    ) external returns (address) {
        // Deploy FlowTCR proxy
        address flowTCRProxy = address(new ERC1967Proxy(flowTCRImplementation, ""));

        // Deploy ERC20VotesArbitrator proxy
        address arbitratorProxy = address(new ERC1967Proxy(arbitratorImplementation, ""));

        // Deploy ERC20VotesMintable proxy
        address erc20Proxy = address(new ERC1967Proxy(erc20Implementation, ""));

        // Initialize the ERC20VotesMintable token
        IERC20Mintable(erc20Proxy).initialize({
            initialOwner: erc20Params.initialOwner,
            minter: erc20Params.minter,
            name: erc20Params.name,
            symbol: erc20Params.symbol
        });

        // Initialize the arbitrator
        IERC20VotesArbitrator(arbitratorProxy).initialize({
            votingToken: address(erc20Proxy),
            arbitrable: flowTCRProxy,
            votingPeriod: arbitratorParams.votingPeriod,
            votingDelay: arbitratorParams.votingDelay,
            revealPeriod: arbitratorParams.revealPeriod,
            appealPeriod: arbitratorParams.appealPeriod,
            appealCost: arbitratorParams.appealCost,
            arbitrationCost: arbitratorParams.arbitrationCost
        });

        // Initialize the FlowTCR
        IFlowTCR(flowTCRProxy).initialize({
            flowContract: params.flowContract,
            arbitrator: IArbitrator(arbitratorProxy),
            flowTCRImpl: flowTCRImplementation,
            arbitratorExtraData: params.arbitratorExtraData,
            registrationMetaEvidence: params.registrationMetaEvidence,
            clearingMetaEvidence: params.clearingMetaEvidence,
            governor: params.governor,
            erc20: IERC20(address(erc20Proxy)),
            submissionBaseDeposit: params.submissionBaseDeposit,
            removalBaseDeposit: params.removalBaseDeposit,
            submissionChallengeBaseDeposit: params.submissionChallengeBaseDeposit,
            removalChallengeBaseDeposit: params.removalChallengeBaseDeposit,
            challengePeriodDuration: params.challengePeriodDuration,
            stakeMultipliers: params.stakeMultipliers
        });

        // Transfer ownership of the contracts to the governor
        IOwnable2Step(flowTCRProxy).transferOwnership(params.governor);
        IOwnable2Step(arbitratorProxy).transferOwnership(params.governor);
        IOwnable2Step(erc20Proxy).transferOwnership(params.governor);

        emit FlowTCRDeployed(msg.sender, flowTCRProxy, arbitratorProxy, erc20Proxy);

        return flowTCRProxy;
    }

    /**
     * @dev Function to authorize an upgrade to a new implementation
     * @param newImplementation Address of the new implementation contract
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
