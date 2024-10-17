// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.28;

import { FlowTypes } from "../storage/FlowStorageV1.sol";
import { IFlow } from "../interfaces/IFlow.sol";

import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

library FlowRates {
    using SuperTokenV1Library for ISuperToken;

    /**
     * @notice Calculates the flow rates for the flow contract
     * @param fs The storage of the Flow contract
     * @return baselineFlowRate The baseline flow rate
     * @return bonusFlowRate The bonus flow rate
     * @return managerRewardFlowRate The manager reward pool flow rate
     */
    function calculateFlowRates(
        FlowTypes.Storage storage fs,
        int96 _flowRate,
        uint256 _percentageScale
    ) external returns (int96 baselineFlowRate, int96 bonusFlowRate, int96 managerRewardFlowRate) {
        int256 managerRewardFlowRatePercent = int256(
            _scaleAmountByPercentage(uint96(_flowRate), fs.managerRewardPoolFlowRatePercent, _percentageScale)
        );

        if (managerRewardFlowRatePercent > type(int96).max) revert IFlow.FLOW_RATE_TOO_HIGH();

        managerRewardFlowRate = int96(managerRewardFlowRatePercent);

        int96 remainingFlowRate = _flowRate - managerRewardFlowRate;

        int256 baselineFlowRate256 = int256(
            _scaleAmountByPercentage(uint96(remainingFlowRate), fs.baselinePoolFlowRatePercent, _percentageScale)
        );

        if (baselineFlowRate256 > type(int96).max) revert IFlow.FLOW_RATE_TOO_HIGH();

        baselineFlowRate = int96(baselineFlowRate256);
        // cannot be negative because remainingFlowRate will always be greater than baselineFlowRate
        bonusFlowRate = remainingFlowRate - baselineFlowRate;
    }

    /**
     * @notice Sets the flow rate for a child Flow contract
     * @param childAddress The address of the child Flow contract
     * @param flowAddress The address of the flow contract
     */
    function calculateBufferAmount(
        FlowTypes.Storage storage fs,
        address childAddress,
        address flowAddress
    ) public returns (bool shouldTransfer, uint256 transferAmount, uint256 bufferAmount) {
        if (childAddress == address(0)) revert IFlow.ADDRESS_ZERO();
        int96 memberFlowRate = getMemberTotalFlowRate(fs, childAddress);

        // add 1% buffer to the flow rate to account for some weird rounding errors
        bufferAmount = (fs.superToken.getBufferAmountByFlowRate(memberFlowRate) * 101) / 100;
        if (bufferAmount > fs.superToken.balanceOf(childAddress)) {
            // ensure this contract has enough balance to transfer to the child contract
            if (bufferAmount < fs.superToken.balanceOf(flowAddress)) {
                // transfer supertoken to the new flow contract so the flow can be started
                shouldTransfer = true;
                transferAmount = bufferAmount - fs.superToken.balanceOf(childAddress);
            }
        }
    }

    /**
     * @notice Retrieves the flow rate for a specific member in the pool
     * @param memberAddr The address of the member
     * @return flowRate The flow rate for the member
     */
    function getMemberTotalFlowRate(
        FlowTypes.Storage storage fs,
        address memberAddr
    ) public view returns (int96 flowRate) {
        flowRate = fs.bonusPool.getMemberFlowRate(memberAddr) + fs.baselinePool.getMemberFlowRate(memberAddr);
    }

    /**
     * @notice Retrieves the buffer amount required for the manager reward pool
     * @param fs The storage of the Flow contract
     * @param flowAddress The address of the flow contract
     * @return bufferAmount The buffer amount required for the manager reward pool
     */
    function getManagerRewardPoolBufferAmount(
        FlowTypes.Storage storage fs,
        address flowAddress
    ) public view returns (uint256 bufferAmount) {
        int96 managerRewardPoolFlowRate = getManagerRewardPoolFlowRate(fs, flowAddress);
        bufferAmount = fs.superToken.getBufferAmountByFlowRate(managerRewardPoolFlowRate);
    }

    /**
     * @notice Retrieves the current flow rate to the manager reward pool
     * @param fs The storage of the Flow contract
     * @param flowAddress The address of the flow contract
     * @return flowRate The current flow rate to the manager reward pool
     */
    function getManagerRewardPoolFlowRate(
        FlowTypes.Storage storage fs,
        address flowAddress
    ) public view returns (int96 flowRate) {
        flowRate = fs.superToken.getFlowRate(flowAddress, fs.managerRewardPool);
    }

    /**
     * @notice Retrieves the claimable balance from both pools for a member address
     * @param fs The storage of the Flow contract
     * @param member The address of the member to check the claimable balance for
     * @return claimable The claimable balance from both pools
     */
    function getClaimableBalance(FlowTypes.Storage storage fs, address member) public view returns (uint256) {
        (int256 baselineClaimable, ) = fs.baselinePool.getClaimableNow(member);
        (int256 bonusClaimable, ) = fs.bonusPool.getClaimableNow(member);

        return uint256(baselineClaimable) + uint256(bonusClaimable);
    }

    /**
     * @notice Retrieves the total member units for a specific member across both pools
     * @param fs The storage of the Flow contract
     * @param memberAddr The address of the member
     * @return totalUnits The total units for the member
     */
    function getTotalMemberUnits(
        FlowTypes.Storage storage fs,
        address memberAddr
    ) public view returns (uint256 totalUnits) {
        totalUnits = fs.bonusPool.getUnits(memberAddr) + fs.baselinePool.getUnits(memberAddr);
    }

    /**
     * @notice Multiplies an amount by a scaled percentage
     *  @param amount Amount to get `scaledPercentage` of
     *  @param scaledPercent Percent scaled by PERCENTAGE_SCALE
     *  @return scaledAmount Percent of `amount`.
     */
    function _scaleAmountByPercentage(
        uint256 amount,
        uint256 scaledPercent,
        uint256 percentageScale
    ) public returns (uint256 scaledAmount) {
        // use assembly to bypass checking for overflow & division by 0
        // scaledPercent has been validated to be < PERCENTAGE_SCALE)
        // & PERCENTAGE_SCALE will never be 0
        assembly {
            /* eg (100 * 2*1e4) / (1e6) */
            scaledAmount := div(mul(amount, scaledPercent), percentageScale)
        }
    }
}
