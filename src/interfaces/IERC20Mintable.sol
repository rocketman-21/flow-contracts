// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

interface IERC20Mintable {
    ///                                                          ///
    ///                           EVENTS                         ///
    ///                                                          ///

    event MinterUpdated(address minter);

    event MinterLocked();

    ///                                                          ///
    ///                           ERRORS                         ///
    ///                                                          ///

    /// @dev Revert if not the manager
    error ONLY_MANAGER();

    /// @dev Revert if 0 address
    error INVALID_ADDRESS_ZERO();

    /// @dev Revert if minter is locked
    error MINTER_LOCKED();

    /// @dev Revert if not minter
    error NOT_MINTER();

    ///                                                          ///
    ///                         FUNCTIONS                        ///
    ///                                                          ///

    function minter() external view returns (address);

    function setMinter(address minter) external;

    function lockMinter() external;

    function mint(address account, uint256 amount) external;

    function decimals() external view returns (uint8);

    /// @notice Initializes an ERC-20 token contract
    /// @param initialOwner The address of the initial owner
    /// @param minter The address of the minter
    /// @param name The name of the token
    /// @param symbol The symbol of the token
    function initialize(address initialOwner, address minter, string calldata name, string calldata symbol) external;
}
