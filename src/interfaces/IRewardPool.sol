// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import { ISuperfluidPool } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/gdav1/ISuperfluidPool.sol";
import { PoolConfig } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";

/**
 * @title IRewardPool
 * @notice Interface for the RewardPool contract
 */
interface IRewardPool {
    /**
     * @notice Initializes the contract and creates a Superfluid pool
     * @param superToken The address of the SuperToken to be used
     * @param manager The address of the manager of the pool
     */
    function initialize(ISuperToken superToken, address manager) external;

    /**
     * @notice Allows the admin or owner to update the flow rate of the pool
     * @param flowRate The new flow rate to be set
     */
    function setFlowRate(int96 flowRate) external;

    /**
     * @notice Allows the admin to update member units of pool recipients
     * @param member The address of the pool recipient
     * @param units The new member units to assign to the recipient
     */
    function updateMemberUnits(address member, uint128 units) external;

    /**
     * @notice Helper function to get the claimable balance for a member at the current time
     * @param member The address of the member
     * @return claimableBalance The claimable balance for the member
     */
    function getClaimableBalanceNow(address member) external view returns (int256 claimableBalance);
}
