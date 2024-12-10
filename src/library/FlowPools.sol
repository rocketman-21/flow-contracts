// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { FlowTypes } from "../storage/FlowStorageV1.sol";
import { IFlow } from "../interfaces/IFlow.sol";
import { Flow } from "../Flow.sol";
import { IRewardPool } from "../interfaces/IRewardPool.sol";

import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

library FlowPools {
    using SuperTokenV1Library for ISuperToken;

    /**
     * @notice Connects a new Flow contract to both pools and initializes its member units
     * @param fs The storage of the Flow contract
     * @param recipient The address of the new Flow contract
     * @param baselineMemberUnits The number of units to be assigned to the baseline pool
     * @param defaultBonusMemberUnits The number of units to be assigned to the bonus pool
     */
    function connectAndInitializeFlowRecipient(
        FlowTypes.Storage storage fs,
        address recipient,
        uint128 baselineMemberUnits,
        uint128 defaultBonusMemberUnits
    ) public {
        // Connect the new child contract to both pools
        Flow(recipient).connectPool(fs.bonusPool);
        Flow(recipient).connectPool(fs.baselinePool);

        // Initialize member units
        updateBaselineMemberUnits(fs, recipient, baselineMemberUnits);
        updateBonusMemberUnits(fs, recipient, defaultBonusMemberUnits);
    }

    /**
     * @notice Updates the member units in the Superfluid pool
     * @param fs The storage of the Flow contract
     * @param member The address of the member whose units are being updated
     * @param units The new number of units to be assigned to the member
     * @dev Reverts with UNITS_UPDATE_FAILED if the update fails
     */
    function updateBonusMemberUnits(FlowTypes.Storage storage fs, address member, uint128 units) public {
        bool success = fs.superToken.updateMemberUnits(fs.bonusPool, member, units);

        if (!success) revert IFlow.UNITS_UPDATE_FAILED();
    }

    /**
     * @notice Updates the member units for the baseline Superfluid pool
     * @param fs The storage of the Flow contract
     * @param member The address of the member whose units are being updated
     * @param units The new number of units to be assigned to the member
     * @dev Reverts with UNITS_UPDATE_FAILED if the update fails
     */
    function updateBaselineMemberUnits(FlowTypes.Storage storage fs, address member, uint128 units) public {
        bool success = fs.superToken.updateMemberUnits(fs.baselinePool, member, units);

        if (!success) revert IFlow.UNITS_UPDATE_FAILED();
    }
}
