// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IArbitrator } from "../interfaces/IArbitrator.sol";
import { IArbitrable } from "../interfaces/IArbitrable.sol";

/**
 * @title ArbitratorStorageV1
 * @notice Storage contract for the Arbitrator implementation
 */
contract ArbitratorStorageV1 {
    // ERC20 token used for payments
    address public paymentToken;
}
