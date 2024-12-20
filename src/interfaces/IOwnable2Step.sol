// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IOwnable2Step {
    /**
     * @dev Starts the ownership transfer of the contract to a new account.
     * Can only be called by the current owner.
     * @param newOwner Address of the new owner.
     */
    function transferOwnership(address newOwner) external;
}
