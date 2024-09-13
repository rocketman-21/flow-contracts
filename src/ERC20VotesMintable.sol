// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.27;

import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20Upgradeable } from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";

import { ERC20VotesUpgradeable } from "./base/erc20/ERC20VotesUpgradeable.sol";

import { IERC20Mintable } from "./interfaces/IERC20Mintable.sol";

contract ERC20VotesMintable is
    IERC20Mintable,
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    ReentrancyGuardUpgradeable,
    ERC20VotesUpgradeable
{
    // An address who has permissions to mint tokens
    address public minter;

    // Whether the minter can be updated
    bool public isMinterLocked;

    ///                                                          ///
    ///                          MODIFIERS                       ///
    ///                                                          ///

    /**
     * @notice Require that the minter has not been locked.
     */
    modifier whenMinterNotLocked() {
        if (isMinterLocked) revert MINTER_LOCKED();
        _;
    }

    /**
     * @notice Require that the sender is the minter.
     */
    modifier onlyMinter() {
        if (msg.sender != minter) revert NOT_MINTER();
        _;
    }

    ///                                                          ///
    ///                         CONSTRUCTOR                      ///
    ///                                                          ///

    constructor() initializer {}

    ///                                                          ///
    ///                         INITIALIZER                      ///
    ///                                                          ///

    /**
     * @dev Initializes the ERC20Mintable contract.
     * @param _name The name of the token.
     * @param _symbol The symbol of the token.
     * @notice This function should only be called once during initialization.
     */
    function __ERC20Mintable_init(string calldata _name, string calldata _symbol) internal onlyInitializing {
        __ReentrancyGuard_init();
        __Ownable_init();
        __ERC20_init(_name, _symbol);
    }

    /**
     * @notice Initializes an ERC-20 mintable token contract
     * @param _initialOwner The address of the initial owner
     * @param _minter The address of the minter
     * @param _name The name of the token
     * @param _symbol The symbol of the token
     */
    function initialize(
        address _initialOwner,
        address _minter,
        string calldata _name,
        string calldata _symbol
    ) external initializer {
        if (_minter == address(0)) revert INVALID_ADDRESS_ZERO();
        if (_initialOwner == address(0)) revert INVALID_ADDRESS_ZERO();

        minter = _minter;

        __ERC20Mintable_init(_name, _symbol);

        emit MinterUpdated(_minter);
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5.05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the default value returned by this function, unless
     * it's overridden.
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual override(ERC20Upgradeable, IERC20Mintable) returns (uint8) {
        return 18;
    }

    /**
     * @notice Mints new tokens and assigns them to the specified account
     * @dev Only callable by the minter role and protected against reentrancy
     * @param account The address that will receive the minted tokens
     * @param amount The amount of tokens to mint
     */
    function mint(address account, uint256 amount) public nonReentrant onlyMinter {
        _mint(account, amount);
    }

    ///                                                          ///
    ///                       ACCESS CONTROL                     ///
    ///                                                          ///

    /**
     * @notice Set the token minter.
     * @dev Only callable by the owner when not locked.
     */
    function setMinter(address _minter) external override onlyOwner nonReentrant whenMinterNotLocked {
        if (_minter == address(0)) revert INVALID_ADDRESS_ZERO();
        minter = _minter;

        emit MinterUpdated(_minter);
    }

    /**
     * @notice Lock the minter.
     * @dev This cannot be reversed and is only callable by the owner when not locked.
     */
    function lockMinter() external override onlyOwner whenMinterNotLocked {
        isMinterLocked = true;

        emit MinterLocked();
    }

    ///                                                          ///
    ///                       TOKEN UPGRADE                      ///
    ///                                                          ///

    /// @notice Ensures the caller is authorized to upgrade the contract
    /// @dev This function is called in `upgradeTo` & `upgradeToAndCall`
    /// @param _newImpl The new implementation address
    function _authorizeUpgrade(address _newImpl) internal view override onlyOwner {}
}
