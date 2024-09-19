// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import { FlowStorageV1 } from "./storage/FlowStorageV1.sol";
import { IFlow } from "./interfaces/IFlow.sol";

import { Ownable2StepUpgradeable } from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import { UUPSUpgradeable } from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import { ISuperfluidPool } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/gdav1/ISuperfluidPool.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";

abstract contract Flow is IFlow, UUPSUpgradeable, Ownable2StepUpgradeable, ReentrancyGuardUpgradeable, FlowStorageV1 {
    using SuperTokenV1Library for ISuperToken;

    /**
     * @notice Initializes the Flow contract
     * @param _initialOwner The address of the initial owner
     * @param _superToken The address of the SuperToken to be used for the pool
     * @param _manager The address of the flow manager
     * @param _managerRewardPool The address of the manager reward pool
     * @param _parent The address of the parent flow contract (optional)
     * @param _flowParams The parameters for the flow contract
     * @param _metadata The metadata for the flow contract
     */
    function __Flow_init(
        address _initialOwner,
        address _superToken,
        address _flowImpl,
        address _manager,
        address _managerRewardPool,
        address _parent,
        FlowParams memory _flowParams,
        RecipientMetadata memory _metadata
    ) public {
        if (_initialOwner == address(0)) revert ADDRESS_ZERO();
        if (_flowImpl == address(0)) revert ADDRESS_ZERO();
        if (_manager == address(0)) revert ADDRESS_ZERO();
        if (_superToken == address(0)) revert ADDRESS_ZERO();
        if (_flowParams.tokenVoteWeight == 0) revert INVALID_VOTE_WEIGHT();
        if (bytes(_metadata.title).length == 0) revert INVALID_METADATA();
        if (bytes(_metadata.description).length == 0) revert INVALID_METADATA();
        if (bytes(_metadata.image).length == 0) revert INVALID_METADATA();
        if (_flowParams.baselinePoolFlowRatePercent > PERCENTAGE_SCALE) revert INVALID_RATE_PERCENT();

        __Ownable2Step_init();
        __ReentrancyGuard_init();

        _transferOwnership(_initialOwner);

        // Set the voting power info
        tokenVoteWeight = _flowParams.tokenVoteWeight; // scaled by 1e18
        baselinePoolFlowRatePercent = _flowParams.baselinePoolFlowRatePercent;
        flowImpl = _flowImpl;
        manager = _manager;
        parent = _parent;
        managerRewardPool = _managerRewardPool;

        superToken = ISuperToken(_superToken);
        bonusPool = superToken.createPool(address(this), poolConfig);
        baselinePool = superToken.createPool(address(this), poolConfig);

        // Set the metadata
        metadata = _metadata;

        // if total member units is 0, set 1 member unit to address(this)
        // do this to prevent distribution pool from resetting flow rate to 0
        if (fs.bonusPool.getTotalUnits() == 0) {
            _updateBonusMemberUnits(address(this), 1);
        }
        if (fs.baselinePool.getTotalUnits() == 0) {
            _updateBaselineMemberUnits(address(this), 1);
        }

        emit FlowInitialized(msg.sender, _superToken, _flowImpl, _manager, _managerRewardPool, _parent);
    }

    /**
     * @notice Cast a vote for a specific grant address.
     * @param recipientId The id of the grant recipient.
     * @param bps The basis points of the vote to be split with the recipient.
     * @param tokenId The tokenId owned by the voter.
     * @param totalWeight The voting power of the voter.
     * @dev Requires that the recipient is valid, and the weight is greater than the minimum vote weight.
     * Emits a VoteCast event upon successful execution.
     */
    function _vote(bytes32 recipientId, uint32 bps, uint256 tokenId, uint256 totalWeight) internal {
        // calculate new member units for recipient
        RecipientType recipientType = recipients[recipientId].recipientType;
        address recipientAddress = recipients[recipientId].recipient;
        uint128 currentUnits = fs.bonusPool.getUnits(recipientAddress);

        // double check for overflow before casting
        // and scale back by 1e15 per https://docs.superfluid.finance/docs/protocol/distributions/guides/pools#about-member-units
        // gives someone with 1 vote at least 1e3 units to work with
        uint256 scaledUnits = _scaleAmountByPercentage(totalWeight, bps) / 1e15;
        if (scaledUnits > type(uint128).max) revert OVERFLOW();
        uint128 newUnits = uint128(scaledUnits);

        uint128 memberUnits = currentUnits + newUnits;

        // update votes, track recipient, bps, and total member units assigned
        votes[tokenId].push(VoteAllocation({ recipientId: recipientId, bps: bps, memberUnits: newUnits }));

        // update member units
        _updateBonusMemberUnits(recipientAddress, memberUnits);

        // if recipient is a flow contract, set the flow rate for the child contract
        if (recipientType == RecipientType.FlowContract) {
            _setChildFlowRate(recipientAddress);
        }

        emit VoteCast(recipientId, tokenId, memberUnits, bps, totalWeight);
    }

    /**
     * @notice Clears out units from previous votes allocation for a specific tokenId.
     * @param tokenId The tokenId whose previous votes are to be cleared.
     * @dev This function resets the member units for all recipients that the tokenId has previously voted for.
     * It should be called before setting new votes to ensure accurate vote allocations.
     */
    function _clearPreviousVotes(uint256 tokenId) internal {
        VoteAllocation[] memory allocations = votes[tokenId];
        for (uint256 i = 0; i < allocations.length; i++) {
            bytes32 recipientId = allocations[i].recipientId;

            // if recipient is removed, skip - don't want to update member units because they have been wiped to 0
            // fine because this vote will be deleted in the next step
            if (recipients[recipientId].removed) continue;

            address recipientAddress = recipients[recipientId].recipient;
            uint128 currentUnits = fs.bonusPool.getUnits(recipientAddress);
            uint128 unitsDelta = allocations[i].memberUnits;
            RecipientType recipientType = recipients[recipientId].recipientType;

            // Calculate the new units by subtracting the delta from the current units
            // Update the member units in the pool
            _updateBonusMemberUnits(recipientAddress, currentUnits - unitsDelta);

            /// @notice - Does not update member units for baseline pool
            /// voting is only for the bonus pool, to ensure all approved recipients get a baseline salary

            // after updating member units, set the flow rate for the child contract
            // if recipient is a flow contract, set the flow rate for the child contract
            if (recipientType == RecipientType.FlowContract) {
                _setChildFlowRate(recipientAddress);
            }
        }

        // Clear out the votes for the tokenId
        delete votes[tokenId];
    }

    /**
     * @notice Checks that the recipients and percentAllocations are valid
     * @param recipientIds The recipientIds of the grant recipients.
     * @param percentAllocations The basis points of the vote to be split with the recipients.
     */
    modifier validVotes(bytes32[] memory recipientIds, uint32[] memory percentAllocations) {
        // must have recipientIds
        if (recipientIds.length < 1) {
            revert TOO_FEW_RECIPIENTS();
        }

        // recipientIds & percentAllocations must be equal length
        if (recipientIds.length != percentAllocations.length) {
            revert RECIPIENTS_ALLOCATIONS_MISMATCH(recipientIds.length, percentAllocations.length);
        }

        // ensure recipients are not 0 address and allocations are > 0
        for (uint256 i = 0; i < recipientIds.length; i++) {
            bytes32 recipientId = recipientIds[i];
            if (recipients[recipientId].recipient == address(0)) revert INVALID_RECIPIENT_ID();
            if (recipients[recipientId].removed == true) revert NOT_APPROVED_RECIPIENT();
            if (percentAllocations[i] == 0) revert ALLOCATION_MUST_BE_POSITIVE();
        }

        _;
    }

    /**
     * @notice Cast a vote for a set of grant addresses.
     * @param tokenId The tokenId owned by the voter.
     * @param recipientIds The recipientIds of the grant recipients to vote for.
     * @param percentAllocations The basis points of the vote to be split with the recipients.
     */
    function _setVotesAllocationForTokenId(
        uint256 tokenId,
        bytes32[] memory recipientIds,
        uint32[] memory percentAllocations
    ) internal {
        uint256 weight = tokenVoteWeight;

        uint256 sum = 0;
        // overflow should be impossible in for-loop index
        for (uint256 i = 0; i < percentAllocations.length; i++) {
            sum += percentAllocations[i];
        }
        if (sum != PERCENTAGE_SCALE) revert INVALID_BPS_SUM();

        // update member units for previous votes
        _clearPreviousVotes(tokenId);

        // set new votes
        for (uint256 i = 0; i < recipientIds.length; i++) {
            _vote(recipientIds[i], percentAllocations[i], tokenId, weight);
        }
    }

    /**
     * @notice Modifier to restrict access to only the manager
     */
    modifier onlyManager() {
        if (msg.sender != manager) revert SENDER_NOT_MANAGER();
        _;
    }

    /**
     * @notice Modifier to restrict access to only the owner or the manager
     */
    modifier onlyOwnerOrManager() {
        if (msg.sender != owner() && msg.sender != manager) revert NOT_OWNER_OR_MANAGER();
        _;
    }

    /**
     * @notice Modifier to restrict access to only the owner or the parent
     */
    modifier onlyOwnerOrParent() {
        if (msg.sender != owner() && msg.sender != parent) revert NOT_OWNER_OR_PARENT();
        _;
    }

    /**
     * @notice Modifier to validate the metadata for a recipient
     * @param metadata The metadata to validate
     */
    modifier validMetadata(RecipientMetadata memory metadata) {
        if (bytes(metadata.title).length == 0) revert INVALID_METADATA();
        if (bytes(metadata.description).length == 0) revert INVALID_METADATA();
        if (bytes(metadata.image).length == 0) revert INVALID_METADATA();
        _;
    }

    /**
     * @notice Adds an address to the list of approved recipients
     * @param recipient The address to be added as an approved recipient
     * @param metadata The metadata of the recipient
     * @return bytes32 The recipientId of the newly created recipient
     * @return address The address of the newly created recipient
     */
    function addRecipient(
        address recipient,
        RecipientMetadata memory metadata
    ) external onlyManager nonReentrant validMetadata(metadata) returns (bytes32, address) {
        if (recipient == address(0)) revert ADDRESS_ZERO();
        if (recipientExists[recipient]) revert RECIPIENT_ALREADY_EXISTS();

        bytes32 recipientId = keccak256(abi.encode(recipient, metadata, RecipientType.ExternalAccount));
        if (recipients[recipientId].recipient != address(0)) revert RECIPIENT_ALREADY_EXISTS();

        recipientExists[recipient] = true;

        recipients[recipientId] = FlowRecipient({
            recipientType: RecipientType.ExternalAccount,
            removed: false,
            recipient: recipient,
            metadata: metadata
        });

        activeRecipientCount++;

        _updateBaselineMemberUnits(recipient, BASELINE_MEMBER_UNITS);
        _updateBonusMemberUnits(recipient, 1); // 1 unit for each recipient in case there are no votes yet, everyone will split the bonus salary

        emit RecipientCreated(recipientId, recipients[recipientId], msg.sender);

        return (recipientId, recipient);
    }

    /**
     * @notice Adds a new Flow contract as a recipient
     * @dev This function creates a new Flow contract and adds it as a recipient
     * @param metadata The metadata of the recipient
     * @param flowManager The address of the flow manager for the new contract
     * @return bytes32 The recipientId of the newly created Flow contract
     * @return address The address of the newly created Flow contract
     * @dev Only callable by the manager of the contract
     * @dev Emits a RecipientCreated event if the recipient is successfully added
     */
    function addFlowRecipient(
        RecipientMetadata calldata metadata,
        address flowManager,
        address managerRewardPool
    ) external onlyManager validMetadata(metadata) returns (bytes32, address) {
        if (flowManager == address(0)) revert ADDRESS_ZERO();
        if (managerRewardPool == address(0)) revert ADDRESS_ZERO();

        address recipient = _deployFlowRecipient(metadata, flowManager, managerRewardPool);

        // connect the new child contract to the pool!
        Flow(recipient).connectPool(bonusPool);
        Flow(recipient).connectPool(baselinePool);

        _updateBaselineMemberUnits(recipient, BASELINE_MEMBER_UNITS);
        _updateBonusMemberUnits(recipient, 1); // 1 unit for each recipient in case there are no votes yet, everyone will split the bonus salary

        // functionality equivalent to addItem _itemID in GeneralizedTCR.sol (keccak256(bytes calldata _item))
        bytes32 recipientId = keccak256(abi.encode(recipient, metadata, RecipientType.FlowContract));

        recipients[recipientId] = FlowRecipient({
            recipientType: RecipientType.FlowContract,
            removed: false,
            recipient: recipient,
            metadata: metadata
        });

        activeRecipientCount++;

        emit RecipientCreated(recipientId, recipients[recipientId], msg.sender);
        emit FlowRecipientCreated(recipientId, recipient);

        return (recipientId, recipient);
    }

    /**
     * @notice Deploys a new Flow contract as a recipient
     * @dev This function is virtual to allow for different deployment strategies in derived contracts
     * @param metadata The metadata of the recipient
     * @param flowManager The address of the flow manager for the new contract
     * @param managerRewardPool The address of the manager reward pool for the new contract
     * @return address The address of the newly created Flow contract
     */
    function _deployFlowRecipient(
        RecipientMetadata calldata metadata,
        address flowManager,
        address managerRewardPool
    ) internal virtual returns (address) {}

    /**
     * @notice Removes a recipient for receiving funds
     * @param recipientId The ID of the recipient to be approved
     * @dev Only callable by the manager of the contract
     * @dev Emits a RecipientRemoved event if the recipient is successfully removed
     */
    function removeRecipient(bytes32 recipientId) external onlyManager nonReentrant {
        if (recipients[recipientId].recipient == address(0)) revert INVALID_RECIPIENT_ID();
        if (recipients[recipientId].removed) revert RECIPIENT_ALREADY_REMOVED();

        address recipientAddress = recipients[recipientId].recipient;
        recipientExists[recipientAddress] = false;

        _removeFromPools(recipientAddress);

        emit RecipientRemoved(recipientAddress, recipientId);

        recipients[recipientId].removed = true;
        activeRecipientCount--;
    }

    /**
     * @notice Resets the flow distribution after removing a recipient
     * @dev This function should be called after removing a recipient to ensure proper flow rate distribution
     * @param recipientAddress The address of the removed recipient
     */
    function _removeFromPools(address recipientAddress) internal {
        // Set member units to 0
        _updateBonusMemberUnits(recipientAddress, 0);
        _updateBaselineMemberUnits(recipientAddress, 0);

        // limitation of superfluid means that when total member units decrease, you must call `distributeFlow` again
        _setFlowRate(getTotalFlowRate());
    }

    /**
     * @notice Sets the flow rate for a child Flow contract
     * @param childAddress The address of the child Flow contract
     */
    function _setChildFlowRate(address childAddress) internal {
        if (childAddress == address(0)) revert ADDRESS_ZERO();

        int96 memberFlowRate = getMemberTotalFlowRate(childAddress);

        // Call setFlowRate on the child contract
        // only set if buffer required is less than balance of contract
        if (superToken.getBufferAmountByFlowRate(memberFlowRate) < superToken.balanceOf(childAddress)) {
            IFlow(childAddress).setFlowRate(memberFlowRate);
        }
    }

    /**
     * @notice Connects this contract to a Superfluid pool
     * @param poolAddress The address of the Superfluid pool to connect to
     * @dev Only callable by the owner or parent of the contract
     * @dev Emits a PoolConnected event upon successful connection
     */
    function connectPool(ISuperfluidPool poolAddress) external onlyOwnerOrParent nonReentrant {
        if (address(poolAddress) == address(0)) revert ADDRESS_ZERO();

        bool success = superToken.connectPool(poolAddress);
        if (!success) revert POOL_CONNECTION_FAILED();
    }

    /**
     * @notice Updates the member units in the Superfluid pool
     * @param member The address of the member whose units are being updated
     * @param units The new number of units to be assigned to the member
     * @dev Reverts with UNITS_UPDATE_FAILED if the update fails
     */
    function _updateBonusMemberUnits(address member, uint128 units) internal {
        bool success = superToken.updateMemberUnits(bonusPool, member, units);

        if (!success) revert UNITS_UPDATE_FAILED();
    }

    /**
     * @notice Updates the member units for the baseline Superfluid pool
     * @param member The address of the member whose units are being updated
     * @param units The new number of units to be assigned to the member
     * @dev Reverts with UNITS_UPDATE_FAILED if the update fails
     */
    function _updateBaselineMemberUnits(address member, uint128 units) internal {
        bool success = superToken.updateMemberUnits(baselinePool, member, units);

        if (!success) revert UNITS_UPDATE_FAILED();
    }

    /**
     * @notice Sets the flow rate for the Superfluid pool
     * @param _flowRate The new flow rate to be set
     * @dev Only callable by the owner or parent of the contract
     * @dev Emits a FlowRateUpdated event with the old and new flow rates
     */
    function setFlowRate(int96 _flowRate) external onlyOwnerOrParent nonReentrant {
        _setFlowRate(_flowRate);
    }

    /**
     * @notice Sets the address of the grants implementation contract
     * @param _flowImpl The new address of the grants implementation contract
     */
    function setFlowImpl(address _flowImpl) external onlyOwner nonReentrant {
        if (_flowImpl == address(0)) revert ADDRESS_ZERO();

        flowImpl = _flowImpl;
        emit FlowImplementationSet(_flowImpl);
    }

    /**
     * @notice Sets a new manager for the Flow contract
     * @param _newManager The address of the new manager
     * @dev Only callable by the current owner
     * @dev Emits a ManagerUpdated event with the old and new manager addresses
     */
    function setManager(address _newManager) external onlyOwnerOrManager nonReentrant {
        if (_newManager == address(0)) revert ADDRESS_ZERO();

        address oldManager = manager;
        manager = _newManager;
        emit ManagerUpdated(oldManager, _newManager);
    }

    /**
     * @notice Sets a new manager reward pool for the Flow contract
     * @param _newManagerRewardPool The address of the new manager reward pool
     * @dev Only callable by the current owner or manager
     * @dev Emits a ManagerRewardPoolUpdated event with the old and new manager reward pool addresses
     */
    function setManagerRewardPool(address _newManagerRewardPool) external onlyOwnerOrManager nonReentrant {
        if (_newManagerRewardPool == address(0)) revert ADDRESS_ZERO();

        address oldManagerRewardPool = managerRewardPool;
        managerRewardPool = _newManagerRewardPool;
        emit ManagerRewardPoolUpdated(oldManagerRewardPool, _newManagerRewardPool);
    }

    /**
     * @notice Returns the SuperToken address
     * @return The address of the SuperToken
     */
    function getSuperToken() external view returns (address) {
        return address(superToken);
    }

    /**
     * @notice Internal function to set the flow rate for the Superfluid pool
     * @param _flowRate The new flow rate to be set
     * @dev Emits a FlowRateUpdated event with the old and new flow rates
     */
    function _setFlowRate(int96 _flowRate) internal {
        if (_flowRate < 0) revert FLOW_RATE_NEGATIVE();

        int256 baselineFlowRate256 = int256(_scaleAmountByPercentage(uint96(_flowRate), baselinePoolFlowRatePercent));

        if (baselineFlowRate256 > type(int96).max) revert FLOW_RATE_TOO_HIGH();

        int96 baselineFlowRate = int96(baselineFlowRate256);
        // cannot be negative because _flowRate will always be greater than baselineFlowRate
        int96 bonusFlowRate = _flowRate - baselineFlowRate;

        emit FlowRateUpdated(getTotalFlowRate(), _flowRate, baselineFlowRate, bonusFlowRate);

        superToken.distributeFlow(address(this), bonusPool, bonusFlowRate);
        superToken.distributeFlow(address(this), baselinePool, baselineFlowRate);
    }

    /**
     * @notice Sets the baseline flow rate percentage
     * @param _baselineFlowRatePercent The new baseline flow rate percentage
     * @dev Only callable by the owner or manager of the contract
     * @dev Emits a BaselineFlowRatePercentUpdated event with the old and new percentages
     */
    function setBaselineFlowRatePercent(uint32 _baselineFlowRatePercent) external onlyOwnerOrManager nonReentrant {
        if (_baselineFlowRatePercent > PERCENTAGE_SCALE) revert INVALID_PERCENTAGE();

        emit BaselineFlowRatePercentUpdated(baselinePoolFlowRatePercent, _baselineFlowRatePercent);

        baselinePoolFlowRatePercent = _baselineFlowRatePercent;

        // Update flow rates to reflect the new percentage
        _setFlowRate(getTotalFlowRate());
    }

    /**
     * @notice Multiplies an amount by a scaled percentage
     *  @param amount Amount to get `scaledPercentage` of
     *  @param scaledPercent Percent scaled by PERCENTAGE_SCALE
     *  @return scaledAmount Percent of `amount`.
     */
    function _scaleAmountByPercentage(
        uint256 amount,
        uint256 scaledPercent
    ) internal pure returns (uint256 scaledAmount) {
        // use assembly to bypass checking for overflow & division by 0
        // scaledPercent has been validated to be < PERCENTAGE_SCALE)
        // & PERCENTAGE_SCALE will never be 0
        assembly {
            /* eg (100 * 2*1e4) / (1e6) */
            scaledAmount := div(mul(amount, scaledPercent), PERCENTAGE_SCALE)
        }
    }

    /**
     * @notice Retrieves the flow rate for a specific member in the pool
     * @param memberAddr The address of the member
     * @return flowRate The flow rate for the member
     */
    function getMemberTotalFlowRate(address memberAddr) public view returns (int96 flowRate) {
        flowRate = fs.bonusPool.getMemberFlowRate(memberAddr) + fs.baselinePool.getMemberFlowRate(memberAddr);
    }

    /**
     * @notice Retrieves the total member units for a specific member across both pools
     * @param memberAddr The address of the member
     * @return totalUnits The total units for the member
     */
    function getTotalMemberUnits(address memberAddr) public view returns (uint256 totalUnits) {
        totalUnits = fs.bonusPool.getUnits(memberAddr) + fs.baselinePool.getUnits(memberAddr);
    }

    /**
     * @notice Retrieves the total amount received by a specific member in the pool
     * @param memberAddr The address of the member
     * @return totalAmountReceived The total amount received by the member
     */
    function getTotalReceivedByMember(address memberAddr) external view returns (uint256 totalAmountReceived) {
        totalAmountReceived =
            fs.bonusPool.getTotalAmountReceivedByMember(memberAddr) +
            fs.baselinePool.getTotalAmountReceivedByMember(memberAddr);
    }

    /**
     * @return totalFlowRate The total flow rate of the pools
     */
    function getTotalFlowRate() public view returns (int96 totalFlowRate) {
        totalFlowRate = fs.bonusPool.getTotalFlowRate() + fs.baselinePool.getTotalFlowRate();
    }

    /**
     * @notice Retrieves all vote allocations for a given ERC721 tokenId
     * @param tokenId The tokenId of the account to retrieve votes for
     * @return allocations An array of VoteAllocation structs representing each vote made by the token
     */
    function getVotesForTokenId(uint256 tokenId) external view returns (VoteAllocation[] memory allocations) {
        return votes[tokenId];
    }

    /**
     * @notice Retrieves all vote allocations for multiple ERC721 tokenIds
     * @param tokenIds An array of tokenIds to retrieve votes for
     * @return allocations An array of arrays, where each inner array contains VoteAllocation structs for a tokenId
     */
    function getVotesForTokenIds(
        uint256[] calldata tokenIds
    ) public view returns (VoteAllocation[][] memory allocations) {
        allocations = new VoteAllocation[][](tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            allocations[i] = votes[tokenIds[i]];
        }
        return allocations;
    }

    /**
     * @notice Retrieves the claimable balance from both pools for a member address
     * @param member The address of the member to check the claimable balance for
     * @return claimable The claimable balance from both pools
     */
    function getClaimableBalance(address member) external view returns (uint256) {
        (int256 baselineClaimable, ) = fs.baselinePool.getClaimableNow(member);
        (int256 bonusClaimable, ) = fs.bonusPool.getClaimableNow(member);

        return uint256(baselineClaimable) + uint256(bonusClaimable);
    }

    /**
     * @notice Ensures the caller is authorized to upgrade the contract
     * @param _newImpl The new implementation address
     */
    function _authorizeUpgrade(address _newImpl) internal view override onlyOwner {}
}
