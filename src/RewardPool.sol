// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import { ISuperfluidPool } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/gdav1/ISuperfluidPool.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import { PoolConfig } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";

/**
 * @title RewardPool
 * @notice A contract that creates a singular Superfluid pool on initialization.
 * @dev Functions similarly to Flow.sol but simplified.
 * @dev Allows an admin or owner to update flow rate.
 * @dev Allows an admin to update member units of pool recipients.
 */
contract RewardPool is UUPSUpgradeable, Ownable2StepUpgradeable, ReentrancyGuardUpgradeable {
    using SuperTokenV1Library for ISuperToken;

    /// @notice The SuperToken used for the pool
    ISuperToken public superToken;

    /// @notice The Superfluid pool created on initialization
    ISuperfluidPool public rewardPool;

    /// @notice The manager of the pool
    address public manager;

    /// The Superfluid pool configuration
    PoolConfig public poolConfig =
        PoolConfig({ transferabilityForUnitsOwner: false, distributionFromAnyAddress: false });

    error ADDRESS_ZERO();
    error FLOW_RATE_NEGATIVE();
    error UNITS_UPDATE_FAILED();
    error NOT_MANAGER_OR_OWNER();
    /**
     * @notice Initializes the contract and creates a Superfluid pool
     * @dev On initialization, the contract creates a Superfluid pool with the specified SuperToken
     * @param _superToken The address of the SuperToken to be used
     * @param _manager The address of the manager of the pool
     */
    function initialize(ISuperToken _superToken, address _manager) public initializer {
        if (address(_superToken) == address(0)) revert ADDRESS_ZERO();
        __Ownable2Step_init();
        __ReentrancyGuard_init();
        superToken = _superToken;
        manager = _manager;
        rewardPool = superToken.createPool(address(this), poolConfig);
    }

    /**
     * @notice Allows the admin or owner to update the flow rate of the pool
     * @dev The flow rate controls the distribution rate of tokens in the pool
     * @param _flowRate The new flow rate to be set
     */
    function setFlowRate(int96 _flowRate) public onlyOwner nonReentrant {
        if (_flowRate < 0) revert FLOW_RATE_NEGATIVE();

        superToken.distributeFlow(address(this), rewardPool, _flowRate);
    }

    /**
     * @notice Allows the admin to update member units of pool recipients
     * @dev Member units represent the share of each recipient in the pool
     * @param _member The address of the pool recipient
     * @param _units The new member units to assign to the recipient
     */
    function updateMemberUnits(address _member, uint128 _units) external onlyManagerOrOwner nonReentrant {
        if (_member == address(0)) revert ADDRESS_ZERO();

        uint128 totalUnitsBefore = rewardPool.getTotalUnits();

        bool success = superToken.updateMemberUnits(rewardPool, _member, _units);
        if (!success) revert UNITS_UPDATE_FAILED();

        uint128 totalUnitsAfter = rewardPool.getTotalUnits();

        // limitation of superfluid means that when total member units decrease, you must call `distributeFlow` again
        if (totalUnitsBefore > totalUnitsAfter) setFlowRate(getTotalFlowRate());
    }

    /**
     * @notice Helper function to get the claimable balance for a member at the current time
     * @param member The address of the member
     * @return claimableBalance The claimable balance for the member
     */
    function getClaimableBalanceNow(address member) public view returns (int256 claimableBalance) {
        (claimableBalance, ) = rewardPool.getClaimableNow(member);
    }

    /**
     * @notice Retrieves the flow rate for a specific member in the pool
     * @param member The address of the member
     * @return flowRate The flow rate for the member
     */
    function getMemberFlowRate(address member) public view returns (int96 flowRate) {
        flowRate = rewardPool.getMemberFlowRate(member);
    }

    /**
     * @notice Helper function to get the total flow rate of the pool
     * @return totalFlowRate The total flow rate of the pool
     */
    function getTotalFlowRate() public view returns (int96 totalFlowRate) {
        totalFlowRate = rewardPool.getTotalFlowRate();
    }

    /**
     * @notice Modifier to restrict access to only the manager or owner
     */
    modifier onlyManagerOrOwner() {
        if (msg.sender != owner() && msg.sender != manager) revert NOT_MANAGER_OR_OWNER();
        _;
    }

    /**
     * @notice Ensures the caller is authorized to upgrade the contract
     * @param newImplementation The new implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
