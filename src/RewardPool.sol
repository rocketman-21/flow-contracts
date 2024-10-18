// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

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

    /// @notice The funder of the pool
    address public funder;

    /// @notice The cached flow rate
    /// @dev Used to prevent precision loss from removing members from a flow
    /// !! Especially important when tokens will be burned often
    int96 public cachedFlowRate;

    /// The Superfluid pool configuration
    PoolConfig public poolConfig =
        PoolConfig({ transferabilityForUnitsOwner: false, distributionFromAnyAddress: false });

    error ADDRESS_ZERO();
    error FLOW_RATE_NEGATIVE();
    error UNITS_UPDATE_FAILED();
    error NOT_MANAGER_OR_OWNER();
    error NOT_OWNER_OR_FUNDER();

    /**
     * @notice Initializes the contract and creates a Superfluid pool
     * @dev On initialization, the contract creates a Superfluid pool with the specified SuperToken
     * @param _superToken The address of the SuperToken to be used
     * @param _manager The address of the manager of the pool
     * @param _funder The address of the funder of the pool (usually the Flow contract)
     */
    function initialize(ISuperToken _superToken, address _manager, address _funder) public initializer {
        if (address(_superToken) == address(0)) revert ADDRESS_ZERO();
        if (_manager == address(0)) revert ADDRESS_ZERO();
        if (_funder == address(0)) revert ADDRESS_ZERO();

        __Ownable2Step_init();
        __ReentrancyGuard_init();
        superToken = _superToken;
        manager = _manager;
        funder = _funder;
        rewardPool = superToken.createPool(address(this), poolConfig);
    }

    /**
     * @notice Allows the admin to update member units of pool recipients
     * @dev Member units represent the share of each recipient in the pool
     * @param _member The address of the pool recipient
     * @param _units The new member units to assign to the recipient
     * @dev Ensure _member is not address(0)
     */
    function updateMemberUnits(address _member, uint128 _units) public onlyManagerOrOwner nonReentrant {
        bool success = superToken.updateMemberUnits(rewardPool, _member, _units);
        if (!success) revert UNITS_UPDATE_FAILED();
    }

    /**
     * @notice Allows the admin or owner to update the flow rate of the pool
     * @dev The flow rate controls the distribution rate of tokens in the pool
     * @param _flowRate The new flow rate to be set
     */
    function setFlowRate(int96 _flowRate) public onlyOwnerOrFunder nonReentrant {
        if (_flowRate < 0) revert FLOW_RATE_NEGATIVE();

        cachedFlowRate = _flowRate;

        // if total flow rate is 0, ensure there is at least 1 unit in the pool to prevent flow rate from resetting to 0
        if (rewardPool.getTotalUnits() == 0) {
            updateMemberUnits(address(this), 1);
        }

        superToken.distributeFlow(address(this), rewardPool, _flowRate);
    }

    /**
     * @notice Resets the flow rate of the pool to its current total flow rate
     * @dev This function can only be called by the owner or manager
     */
    function resetFlowRate() external onlyManagerOrOwner nonReentrant {
        superToken.distributeFlow(address(this), rewardPool, getTotalFlowRate());
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
     * @notice Retrieves the units for a specific member in the pool
     * @param member The address of the member
     * @return units The units assigned to the member
     */
    function getMemberUnits(address member) public view returns (uint128 units) {
        units = rewardPool.getUnits(member);
    }

    /**
     * @notice Helper function to get the total flow rate of the pool
     * @return totalFlowRate The total flow rate of the pool
     */
    function getTotalFlowRate() public view returns (int96) {
        return cachedFlowRate;
    }

    /**
     * @notice Modifier to restrict access to only the manager or owner
     */
    modifier onlyManagerOrOwner() {
        if (msg.sender != owner() && msg.sender != manager) revert NOT_MANAGER_OR_OWNER();
        _;
    }

    /**
     * @notice Modifier to restrict access to only the owner or funder
     */
    modifier onlyOwnerOrFunder() {
        if (msg.sender != owner() && msg.sender != funder) revert NOT_OWNER_OR_FUNDER();
        _;
    }

    /**
     * @notice Ensures the caller is authorized to upgrade the contract
     * @param newImplementation The new implementation address
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}
}
