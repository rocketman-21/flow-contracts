// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.23;

import {Flow} from "./Flow.sol";
import {FlowStorageV1} from "./storage/FlowStorageV1.sol";
import {IFlow} from "./interfaces/IFlow.sol";
import {IERC721Checkpointable} from "./interfaces/IERC721Checkpointable.sol";
import {L2NounsVerifier} from "./state-proof/L2NounsVerifier.sol";

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import {ISuperfluidPool} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/gdav1/ISuperfluidPool.sol";
import {SuperTokenV1Library} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";

contract NounsFlow is
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    ReentrancyGuardUpgradeable,
    EIP712Upgradeable,
    FlowStorageV1,
    Flow
{
    L2NounsVerifier public verifier;

    constructor() payable initializer Flow() {}

    function initialize(
        address _nounsToken,
        address _superToken,
        address _flowImpl,
        address _manager,
        address _parent,
        FlowParams memory _flowParams,
        RecipientMetadata memory _metadata
    ) public override initializer {
        __Flow_init(_nounsToken, _superToken, _flowImpl, _manager, _parent, _flowParams, _metadata);

        verifier = new L2NounsVerifier();
    }
}
