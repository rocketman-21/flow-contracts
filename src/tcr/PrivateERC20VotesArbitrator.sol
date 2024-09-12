// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { IArbitrator } from "./interfaces/IArbitrator.sol";
import { IArbitrable } from "./interfaces/IArbitrable.sol";
import { ArbitratorStorageV1 } from "./storage/ArbitratorStorageV1.sol";

import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { OwnableUpgradeable } from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";

contract PrivateERC20VotesArbitrator is
    IArbitrator,
    ArbitratorStorageV1,
    UUPSUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    constructor() payable initializer {}

    /**
     * @notice Initializes the PrivateERC20VotesArbitrator contract
     * @dev This function can only be called once due to the initializer modifier
     * @param _paymentToken The address of the ERC20 token used for payments
     */
    function initialize(address _paymentToken) public initializer {
        __Ownable_init();
        paymentToken = _paymentToken;
    }

    function createDispute(uint256 _choices, bytes calldata _extraData) external override returns (uint256 disputeID) {
        // TODO: Implement createDispute logic
    }

    function appeal(uint256 _disputeID, bytes calldata _extraData) external payable override {
        // TODO: Implement appeal logic
    }

    function arbitrationCost(bytes calldata _extraData) external view override returns (uint256 cost) {
        // TODO: Implement arbitrationCost logic
    }

    function appealCost(uint256 _disputeID, bytes calldata _extraData) external view override returns (uint256 cost) {
        // TODO: Implement appealCost logic
    }

    function appealPeriod(uint256 _disputeID) external view override returns (uint256 start, uint256 end) {
        // TODO: Implement appealPeriod logic
    }

    function disputeStatus(uint256 _disputeID) external view override returns (DisputeStatus status) {
        // TODO: Implement disputeStatus logic
    }

    function currentRuling(uint256 _disputeID) external view override returns (uint256 ruling) {
        // TODO: Implement currentRuling logic
    }

    /**
     * @notice Ensures the caller is authorized to upgrade the contract
     * @param _newImpl The new implementation address
     */
    function _authorizeUpgrade(address _newImpl) internal view override onlyOwner {}
}
