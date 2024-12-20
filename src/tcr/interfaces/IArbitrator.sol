// SPDX-License-Identifier: MIT
// IArbitrator.sol is a modified version of Kleros' IArbitrator.sol:
// https://github.com/kleros/erc-792
//
// IArbitrator.sol source code Copyright Kleros licensed under the MIT license.
// With modifications by rocketman for the Nouns Flows project.
//
// Modifications:
// - Removed appeal related functions and events

pragma solidity ^0.8.0;

import { IArbitrable } from "./IArbitrable.sol";
import { ITCRFactory } from "./ITCRFactory.sol";

/**
 * @title Arbitrator
 * Arbitrator abstract contract.
 * When developing arbitrator contracts we need to:
 * - Define the functions for dispute creation (createDispute). Don't forget to store the arbitrated contract and the disputeID (which should be unique, may nbDisputes).
 * - Define the functions for cost display (arbitrationCost).
 * - Allow giving rulings. For this a function must call arbitrable.rule(disputeID, ruling).
 */
interface IArbitrator {
    enum DisputeStatus {
        Waiting,
        Solved
    }

    /**
     * @dev To be emitted when a dispute is created.
     * @param _disputeID ID of the dispute.
     * @param _arbitrable The contract which created the dispute.
     */
    event DisputeCreation(uint256 indexed _disputeID, IArbitrable indexed _arbitrable);

    /**
     * @dev Create a dispute. Must be called by the arbitrable contract.
     * Must be paid at least arbitrationCost(_extraData) in ERC20 tokens.
     * Arbitrator must transferFrom() the ERC20 tokens to itself.
     * @param _choices Amount of choices the arbitrator can make in this dispute.
     * @param _extraData Can be used to give additional info on the dispute to be created.
     * @return disputeID ID of the dispute created.
     */
    function createDispute(uint256 _choices, bytes calldata _extraData) external returns (uint256 disputeID);

    /**
     * @dev Compute the cost of arbitration. It is recommended not to increase it often, as it can be highly time and gas consuming for the arbitrated contracts to cope with fee augmentation.
     * @param _extraData Can be used to give additional info on the dispute to be created.
     * @return cost Amount to be paid.
     */
    function arbitrationCost(bytes calldata _extraData) external view returns (uint256 cost);

    /**
     * @dev Return the status of a dispute.
     * @param _disputeID ID of the dispute to rule.
     * @return status The status of the dispute.
     */
    function disputeStatus(uint256 _disputeID) external view returns (DisputeStatus status);

    /**
     * @dev Return the current ruling of a dispute.
     * @param _disputeID ID of the dispute.
     * @return ruling The ruling which has been given.
     */
    function currentRuling(uint256 _disputeID) external view returns (IArbitrable.Party ruling);

    /**
     * @dev Returns the arbitrator parameters for use in the TCR factory.
     * @return ArbitratorParams struct containing the necessary parameters for the factory.
     */
    function getArbitratorParamsForFactory() external view returns (ITCRFactory.ArbitratorParams memory);
}
