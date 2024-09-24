// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import { BondingSCurve } from "./bonding-curve/BondingSCurve.sol";
import { ERC20VotesMintable } from "./ERC20VotesMintable.sol";
import { ITokenEmitter } from "./interfaces/ITokenEmitter.sol";
import { IWETH } from "./interfaces/IWETH.sol";

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

/**
 * @title TokenEmitter
 * @dev Contract for emitting tokens using a bonding curve mechanism
 */
contract TokenEmitter is ITokenEmitter, BondingSCurve, ReentrancyGuardUpgradeable {
    /// @notice The ERC20 token being emitted
    ERC20VotesMintable public erc20;

    /// @notice The WETH token
    IWETH public WETH;

    /**
     * @dev Constructor function
     * @notice Initializes the contract
     */
    constructor() payable initializer {}

    /**
     * @dev Initializes the TokenEmitter contract
     * @param _initialOwner The address of the initial owner of the contract
     * @param _erc20 The address of the ERC20 token to be emitted
     * @param _weth The address of the WETH token
     * @param _curveSteepness The steepness of the bonding curve
     * @param _basePrice The base price for token emission
     * @param _maxPriceIncrease The maximum price increase for token emission
     * @param _supplyOffset The supply offset for the bonding curve
     */
    function initialize(
        address _initialOwner,
        address _erc20,
        address _weth,
        int256 _curveSteepness,
        int256 _basePrice,
        int256 _maxPriceIncrease,
        int256 _supplyOffset
    ) public initializer {
        if (_erc20 == address(0)) revert INVALID_ADDRESS_ZERO();
        if (_weth == address(0)) revert INVALID_ADDRESS_ZERO();
        if (_initialOwner == address(0)) revert INVALID_ADDRESS_ZERO();

        erc20 = ERC20VotesMintable(_erc20);
        WETH = IWETH(_weth);

        __ReentrancyGuard_init();

        __BondingSCurve_init(_initialOwner, _curveSteepness, _basePrice, _maxPriceIncrease, _supplyOffset);
    }

    /**
     * @notice Calculates the cost to buy a certain amount of tokens
     * @dev Uses the bonding curve to determine the cost
     * @param amount The number of tokens to buy
     * @return cost The cost to buy the specified amount of tokens
     */
    function buyTokenQuote(uint256 amount) public view returns (int256 cost) {
        return costForToken(int256(IERC20(address(erc20)).totalSupply()), int256(amount));
    }

    /**
     * @notice Calculates the payment received when selling a certain amount of tokens
     * @dev Uses the bonding curve to determine the payment
     * @param amount The number of tokens to sell
     * @return payment The payment received for selling the specified amount of tokens
     */
    function sellTokenQuote(uint256 amount) public view returns (int256 payment) {
        return paymentToSell(int256(IERC20(address(erc20)).totalSupply()), int256(amount));
    }

    /**
     * @notice Allows users to buy tokens by sending ETH with slippage protection
     * @dev Uses nonReentrant modifier to prevent reentrancy attacks
     * @param amount The number of tokens to buy
     * @param maxCost The maximum acceptable cost in wei
     */
    function buyToken(uint256 amount, uint256 maxCost) public payable nonReentrant {
        int256 costInt = buyTokenQuote(amount);
        if (costInt < 0) revert INVALID_COST();
        uint256 cost = uint256(costInt);

        if (cost > maxCost) revert SLIPPAGE_EXCEEDED();

        // Handle overpayment
        if (msg.value < cost) revert INSUFFICIENT_FUNDS();
        if (msg.value > cost) {
            _safeTransferETHWithFallback(_msgSender(), msg.value - cost);
        }

        erc20.mint(_msgSender(), amount);

        emit TokensBought(_msgSender(), amount, cost);
    }

    /**
     * @notice Allows users to sell tokens and receive ETH with slippage protection
     * @dev Uses nonReentrant modifier to prevent reentrancy attacks
     * @param amount The number of tokens to sell
     * @param minPayment The minimum acceptable payment in wei
     */
    function sellToken(uint256 amount, uint256 minPayment) public nonReentrant {
        int256 paymentInt = sellTokenQuote(amount);
        if (paymentInt < 0) revert INVALID_PAYMENT();
        uint256 payment = uint256(paymentInt);

        if (payment < minPayment) revert SLIPPAGE_EXCEEDED();
        if (payment > address(this).balance) revert INSUFFICIENT_CONTRACT_BALANCE();
        if (erc20.balanceOf(_msgSender()) < amount) revert INSUFFICIENT_TOKEN_BALANCE();

        erc20.burn(_msgSender(), amount);

        _safeTransferETHWithFallback(_msgSender(), payment);

        emit TokensSold(_msgSender(), amount, payment);
    }

    /**
     * @notice Transfer ETH/WETH from the contract
     * @dev Attempts to transfer ETH first, falls back to WETH if ETH transfer fails
     * @param _to The recipient address
     * @param _amount The amount transferring
     */
    function _safeTransferETHWithFallback(address _to, uint256 _amount) private {
        // Ensure the contract has enough ETH to transfer
        if (address(this).balance < _amount) revert("Insufficient balance");

        // Used to store if the transfer succeeded
        bool success;

        assembly {
            // Transfer ETH to the recipient
            // Limit the call to 50,000 gas
            success := call(50000, _to, _amount, 0, 0, 0, 0)
        }

        // If the transfer failed:
        if (!success) {
            // Wrap as WETH
            WETH.deposit{ value: _amount }();

            // Transfer WETH instead
            bool wethSuccess = WETH.transfer(_to, _amount);

            // Ensure successful transfer
            if (!wethSuccess) revert("WETH transfer failed");
        }
    }
}
