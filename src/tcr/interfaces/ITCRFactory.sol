// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import { IManagedFlow } from "../../interfaces/IManagedFlow.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";

/**
 * @title ITCRFactory
 * @dev Interface for the TCRFactory contract
 */
interface ITCRFactory {
    /**
     * @dev Parameters for initializing a FlowTCR
     * @param flowContract The address of the Flow contract this TCR will manage
     * @param arbitratorExtraData Extra data for the arbitrator
     * @param registrationMetaEvidence MetaEvidence for registration requests
     * @param clearingMetaEvidence MetaEvidence for removal requests
     * @param governor The governor of this contract
     * @param submissionBaseDeposit Base deposit for submitting an item
     * @param removalBaseDeposit Base deposit for removing an item
     * @param submissionChallengeBaseDeposit Base deposit for challenging a submission
     * @param removalChallengeBaseDeposit Base deposit for challenging a removal
     * @param challengePeriodDuration Duration of the challenge period
     * @param stakeMultipliers Multipliers for appeals
     */
    struct FlowTCRParams {
        IManagedFlow flowContract;
        bytes arbitratorExtraData;
        string registrationMetaEvidence;
        string clearingMetaEvidence;
        address governor;
        uint submissionBaseDeposit;
        uint removalBaseDeposit;
        uint submissionChallengeBaseDeposit;
        uint removalChallengeBaseDeposit;
        uint challengePeriodDuration;
        uint[3] stakeMultipliers;
    }

    /**
     * @dev Parameters for initializing an Arbitrator
     * @param votingPeriod The voting period duration
     * @param votingDelay The delay before voting starts
     * @param revealPeriod The period for revealing votes
     * @param appealPeriod The period for appealing decisions
     * @param appealCost The cost of appealing a decision
     * @param arbitrationCost The cost of arbitration
     */
    struct ArbitratorParams {
        uint256 votingPeriod;
        uint256 votingDelay;
        uint256 revealPeriod;
        uint256 appealPeriod;
        uint256 appealCost;
        uint256 arbitrationCost;
    }

    /**
     * @notice Struct to hold the return values of deployFlowTCR function
     * @dev Contains addresses of deployed contracts in the FlowTCR ecosystem
     */
    struct DeployedContracts {
        address tcrAddress;
        address arbitratorAddress;
        address erc20Address;
        address rewardPoolAddress;
    }

    /**
     * @dev Parameters for initializing an ERC20 token
     * @param initialOwner The initial owner of the token
     * @param minter The address with minting rights
     * @param name The name of the token
     * @param symbol The symbol of the token
     */
    struct ERC20Params {
        address initialOwner;
        address minter;
        string name;
        string symbol;
    }

    /**
     * @dev Parameters for initializing a RewardPool
     * @param superToken The address of the SuperToken to be used
     */
    struct RewardPoolParams {
        ISuperToken superToken;
    }

    /// @notice Emitted when a new FlowTCR ecosystem is deployed
    event FlowTCRDeployed(
        address indexed sender,
        address indexed flowTCRProxy,
        address indexed arbitratorProxy,
        address erc20Proxy
    );

    /// @notice Emitted when the RewardPool implementation address is updated
    event RewardPoolImplementationUpdated(address oldImplementation, address newImplementation);

    /// @notice Emitted when the FlowTCR implementation address is updated
    event FlowTCRImplementationUpdated(address oldImplementation, address newImplementation);

    /// @notice Emitted when the ERC20VotesArbitrator implementation address is updated
    event ArbitratorImplementationUpdated(address oldImplementation, address newImplementation);

    /// @notice Emitted when the ERC20VotesMintable implementation address is updated
    event ERC20ImplementationUpdated(address oldImplementation, address newImplementation);

    /**
     * @dev Returns the address of the FlowTCR implementation
     * @return The address of the FlowTCR implementation
     */
    function flowTCRImplementation() external view returns (address);

    /**
     * @dev Returns the address of the Arbitrator implementation
     * @return The address of the Arbitrator implementation
     */
    function arbitratorImplementation() external view returns (address);

    /**
     * @dev Returns the address of the ERC20 implementation
     * @return The address of the ERC20 implementation
     */
    function erc20Implementation() external view returns (address);

    /**
     * @dev Deploys a new FlowTCR ecosystem with associated contracts
     * @param params Parameters for initializing the FlowTCR contract
     * @param arbitratorParams Parameters for initializing the Arbitrator contract
     * @param erc20Params Parameters for initializing the ERC20 contract
     * @param rewardPoolParams Parameters for initializing the RewardPool contract
     * @return deployedContracts The addresses of the deployed contracts
     */
    function deployFlowTCR(
        FlowTCRParams memory params,
        ArbitratorParams memory arbitratorParams,
        ERC20Params memory erc20Params,
        RewardPoolParams memory rewardPoolParams
    ) external returns (DeployedContracts memory deployedContracts);

    /**
     * @dev Initializes the TCRFactory contract
     * @param initialOwner The address that will be set as the initial owner of the contract
     * @param flowTCRImplementation The address of the FlowTCR implementation contract
     * @param arbitratorImplementation The address of the Arbitrator implementation contract
     * @param erc20Implementation The address of the ERC20 implementation contract
     * @param rewardPoolImplementation The address of the RewardPool implementation contract
     */
    function initialize(
        address initialOwner,
        address flowTCRImplementation,
        address arbitratorImplementation,
        address erc20Implementation,
        address rewardPoolImplementation
    ) external;
}
