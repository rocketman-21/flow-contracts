// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import { GeneralizedTCR } from "./GeneralizedTCR.sol";
import { IArbitrator } from "./interfaces/IArbitrator.sol";
import { IManagedFlow } from "../interfaces/IManagedFlow.sol";
import { IFlowTCR } from "./interfaces/IGeneralizedTCR.sol";
import { FlowTypes } from "../storage/FlowStorageV1.sol";
import { ITCRFactory } from "./interfaces/ITCRFactory.sol";
import { FlowRecipients } from "../library/FlowRecipients.sol";
import { FlowTCRItems } from "./library/FlowTCRItems.sol";
import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";

/**
 * @title FlowTCR
 * @dev This contract extends GeneralizedTCR to provide a Token Curated Registry (TCR)
 * specifically designed to interface with the Flow.sol contract as a manager.
 * It allows for the curation of recipients in the Flow ecosystem through a
 * decentralized voting and challenge process.
 */
contract FlowTCR is GeneralizedTCR, IFlowTCR {
    using FlowTCRItems for bytes;

    // The Flow contract this TCR is managing
    IManagedFlow public flowContract;

    // The address of the TCR factory
    ITCRFactory public tcrFactory;

    // The required FlowRecipient type for the TCR (optional)
    FlowTypes.RecipientType public requiredRecipientType;

    // TokenEmitter parameters
    int256 public curveSteepness;
    int256 public basePrice;
    int256 public maxPriceIncrease;
    int256 public supplyOffset;

    // Error emitted when the curve steepness is invalid
    error INVALID_CURVE_STEEPNESS();

    // Event emitted when TokenEmitter parameters are set
    event TokenEmitterParamsSet(int256 curveSteepness, int256 basePrice, int256 maxPriceIncrease, int256 supplyOffset);

    // Event emitted when the required recipient type is set
    event RequiredRecipientTypeSet(FlowTypes.RecipientType requiredRecipientType);

    constructor() payable initializer {}

    /**
     * @dev Initializes the FlowTCR contract with necessary parameters and links it to a Flow contract.
     * @param _contractParams Struct containing address parameters and interfaces
     * @param _tcrParams Struct containing TCR parameters, including deposits, durations, and evidence
     */
    function initialize(
        ContractParams memory _contractParams,
        TCRParams memory _tcrParams,
        TokenEmitterParams memory _tokenEmitterParams
    ) public initializer {
        flowContract = _contractParams.flowContract;
        tcrFactory = _contractParams.tcrFactory;
        requiredRecipientType = _tcrParams.requiredRecipientType;

        _setTokenEmitterParams(
            _tokenEmitterParams.curveSteepness,
            _tokenEmitterParams.basePrice,
            _tokenEmitterParams.maxPriceIncrease,
            _tokenEmitterParams.supplyOffset
        );

        __GeneralizedTCR_init(
            _contractParams.initialOwner,
            _contractParams.arbitrator,
            _tcrParams.arbitratorExtraData,
            _tcrParams.registrationMetaEvidence,
            _tcrParams.clearingMetaEvidence,
            _contractParams.governor,
            _contractParams.erc20,
            _tcrParams.submissionBaseDeposit,
            _tcrParams.removalBaseDeposit,
            _tcrParams.submissionChallengeBaseDeposit,
            _tcrParams.removalChallengeBaseDeposit,
            _tcrParams.challengePeriodDuration,
            _tcrParams.stakeMultipliers
        );
    }

    /**
     * @notice Removes an item from the Flow contract when it's removed from the TCR
     * @param _itemID The ID of the item being removed
     * @dev This function is called internally when an item is removed from the TCR
     * @dev IMPORTANT: Assumes that the itemID is consistent with the recipientId in the Flow contract
     */
    function _onItemRemoved(bytes32 _itemID) internal override {
        flowContract.removeRecipient(_itemID);
    }

    /**
     * @dev Verifies the data of an item before it's added to the registry.
     * @param _item The data describing the item to be added.
     * @return valid True if the item data is valid, false otherwise.
     */
    function _verifyItemData(bytes calldata _item) internal override returns (bool valid) {
        return _item.verifyItemData(requiredRecipientType);
    }

    /**
     * @notice Handles the registration of an item in the TCR
     * @param _item The data describing the item
     * @dev This function is called internally when an item is registered in the TCR
     */
    function _onItemRegistered(bytes32, bytes memory _item) internal override {
        // Decode the item data
        (address recipient, FlowTypes.RecipientMetadata memory metadata, FlowTypes.RecipientType recipientType) = _item
            .decodeItemData();

        // Add the recipient to the Flow contract
        if (recipientType == FlowTypes.RecipientType.ExternalAccount) {
            flowContract.addRecipient(recipient, metadata);
        } else if (recipientType == FlowTypes.RecipientType.FlowContract) {
            // temporarily set manager to owner
            (, address flowRecipient) = flowContract.addFlowRecipient(metadata, owner(), owner());

            ITCRFactory.DeployedContracts memory deployedContracts = tcrFactory.deployFlowTCR(
                ITCRFactory.FlowTCRParams({
                    flowContract: IManagedFlow(flowRecipient),
                    arbitratorExtraData: arbitratorExtraData,
                    registrationMetaEvidence: registrationMetaEvidence,
                    clearingMetaEvidence: clearingMetaEvidence,
                    governor: governor,
                    submissionBaseDeposit: submissionBaseDeposit,
                    removalBaseDeposit: removalBaseDeposit,
                    submissionChallengeBaseDeposit: submissionChallengeBaseDeposit,
                    removalChallengeBaseDeposit: removalChallengeBaseDeposit,
                    challengePeriodDuration: challengePeriodDuration,
                    stakeMultipliers: [sharedStakeMultiplier, winnerStakeMultiplier, loserStakeMultiplier],
                    requiredRecipientType: FlowTypes.RecipientType.None
                }),
                arbitrator.getArbitratorParamsForFactory(),
                ITCRFactory.ERC20Params({ initialOwner: owner(), name: metadata.title, symbol: "TCRT" }), // TODO update all
                ITCRFactory.RewardPoolParams({ superToken: ISuperToken(flowContract.getSuperToken()) }),
                ITCRFactory.TokenEmitterParams({
                    initialOwner: owner(),
                    curveSteepness: curveSteepness,
                    basePrice: basePrice,
                    maxPriceIncrease: maxPriceIncrease,
                    supplyOffset: supplyOffset
                })
            );

            // set manager to new TCR and manager reward pool
            flowContract.setManager(deployedContracts.tcrAddress);
            flowContract.setManagerRewardPool(deployedContracts.rewardPoolAddress);
        }
    }

    /**
     * @notice Sets the required recipient type for the TCR
     * @param _requiredRecipientType The required recipient type
     * @dev This function is called internally when the required recipient type is set
     */
    function setRequiredRecipientType(FlowTypes.RecipientType _requiredRecipientType) external onlyOwner {
        requiredRecipientType = _requiredRecipientType;
        emit RequiredRecipientTypeSet(_requiredRecipientType);
    }

    /**
     * @notice Sets the TokenEmitter parameters
     * @param _curveSteepness The steepness of the curve
     * @param _basePrice The base price for a token if sold on pace
     * @param _maxPriceIncrease The maximum price increase for a token if sold on pace
     * @param _supplyOffset The supply offset for a token if sold on pace
     */
    function setTokenEmitterParams(
        int256 _curveSteepness,
        int256 _basePrice,
        int256 _maxPriceIncrease,
        int256 _supplyOffset
    ) external onlyOwner {
        _setTokenEmitterParams(_curveSteepness, _basePrice, _maxPriceIncrease, _supplyOffset);
    }

    /**
     * @notice Internal function to set the TokenEmitter parameters
     * @param _curveSteepness The steepness of the curve
     * @param _basePrice The base price for a token if sold on pace
     * @param _maxPriceIncrease The maximum price increase for a token if sold on pace
     * @param _supplyOffset The supply offset for a token if sold on pace
     */
    function _setTokenEmitterParams(
        int256 _curveSteepness,
        int256 _basePrice,
        int256 _maxPriceIncrease,
        int256 _supplyOffset
    ) internal {
        if (_curveSteepness <= 0) revert INVALID_CURVE_STEEPNESS();

        curveSteepness = _curveSteepness;
        basePrice = _basePrice;
        maxPriceIncrease = _maxPriceIncrease;
        supplyOffset = _supplyOffset;

        emit TokenEmitterParamsSet(_curveSteepness, _basePrice, _maxPriceIncrease, _supplyOffset);
    }
}
