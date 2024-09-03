// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.26;

import {FlowStorageV1} from "./storage/FlowStorageV1.sol";
import {IFlow} from "./interfaces/IFlow.sol";
import {IERC721Checkpointable} from "./interfaces/IERC721Checkpointable.sol";

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
import {EIP712Upgradeable} from "@openzeppelin/contracts-upgradeable/utils/cryptography/EIP712Upgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import {ISuperfluidPool} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/gdav1/ISuperfluidPool.sol";
import {SuperTokenV1Library} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";

contract Flow is
    IFlow,
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    ReentrancyGuardUpgradeable,
    EIP712Upgradeable,
    FlowStorageV1
{
    using SuperTokenV1Library for ISuperToken;

    /**
     * @notice Initializes a token's metadata descriptor
     */
    constructor() payable initializer {}

    /**
     * @notice Initializes the Flow contract
     * @param _nounsToken The address of the Nouns token contract
     * @param _superToken The address of the SuperToken to be used for the pool
     * @param _flowImpl The address of the flow implementation contract
     * @param _manager The address of the flow manager
     * @param _parent The address of the parent flow contract (optional)
     * @param _flowParams The parameters for the flow contract
     * @param _metadata The metadata for the flow contract
     */
    function initialize(
        address _nounsToken,
        address _superToken,
        address _flowImpl,
        address _manager,
        address _parent,
        FlowParams memory _flowParams,
        RecipientMetadata memory _metadata
    ) public initializer {
        if (_nounsToken == address(0)) revert ADDRESS_ZERO();
        if (_flowImpl == address(0)) revert ADDRESS_ZERO();
        if (_manager == address(0)) revert ADDRESS_ZERO();
        if (_superToken == address(0)) revert ADDRESS_ZERO();
        if (_flowParams.tokenVoteWeight == 0) revert INVALID_VOTE_WEIGHT();
        if (bytes(_metadata.title).length == 0) revert INVALID_METADATA();
        if (bytes(_metadata.description).length == 0) revert INVALID_METADATA();
        if (bytes(_metadata.image).length == 0) revert INVALID_METADATA();

        // Initialize EIP-712 support
        __EIP712_init("Flow", "1");
        __Ownable_init();
        __ReentrancyGuard_init();

        // Set the voting power info
        erc721Votes = IERC721Checkpointable(_nounsToken);
        tokenVoteWeight = _flowParams.tokenVoteWeight;
        flowImpl = _flowImpl;
        manager = _manager;
        parent = _parent;

        superToken = ISuperToken(_superToken);
        bonusPool = superToken.createPool(address(this), poolConfig);

        // Set the metadata
        metadata = _metadata;

        // if total member units is 0, set 1 member unit to address(this)
        // do this to prevent distribution pool from resetting flow rate to 0
        if (getTotalUnits() == 0) {
            _updateMemberUnits(address(this), 1);
        }

        emit FlowInitialized(msg.sender, _superToken, _flowImpl);
    }

    /**
     * @notice Sets the address of the grants implementation contract
     * @param _flowImpl The new address of the grants implementation contract
     */
    function setFlowImpl(address _flowImpl) public onlyOwner nonReentrant {
        if (_flowImpl == address(0)) revert ADDRESS_ZERO();
        
        flowImpl = _flowImpl;
        emit FlowImplementationSet(_flowImpl);
    }

    /**
     * @notice Retrieves all vote allocations for a given ERC721 tokenId
     * @param tokenId The tokenId of the account to retrieve votes for
     * @return allocations An array of VoteAllocation structs representing each vote made by the token
     */
    function getVotesForTokenId(uint256 tokenId) public view returns (VoteAllocation[] memory allocations) {
        return votes[tokenId];
    }

    /**
     * @notice Retrieves all vote allocations for multiple ERC721 tokenIds
     * @param tokenIds An array of tokenIds to retrieve votes for
     * @return allocations An array of arrays, where each inner array contains VoteAllocation structs for a tokenId
     */
    function getVotesForTokenIds(uint256[] memory tokenIds) public view returns (VoteAllocation[][] memory allocations) {
        allocations = new VoteAllocation[][](tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; i++) {
            allocations[i] = votes[tokenIds[i]];
        }
        return allocations;
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
    function _vote(uint256 recipientId, uint32 bps, uint256 tokenId, uint256 totalWeight) internal {
        // calculate new member units for recipient
        // make sure to add the current units to the new units
        // todo check this
        FlowRecipient memory recipient = recipients[recipientId];
        RecipientType recipientType = recipient.recipientType;
        address recipientAddress = recipient.recipient;
        uint128 currentUnits = bonusPool.getUnits(recipientAddress);

        // double check for overflow before casting
        // and scale back by 1e15 per https://docs.superfluid.finance/docs/protocol/distributions/guides/pools#about-member-units
        // gives someone with 1 vote at least 1e3 units to work with
        uint256 scaledUnits = _scaleAmountByPercentage(totalWeight, bps) / 1e15;
        if (scaledUnits > type(uint128).max) revert OVERFLOW();
        uint128 newUnits = uint128(scaledUnits);

        uint128 memberUnits = currentUnits + newUnits;

        // update votes, track recipient, bps, and total member units assigned
        votes[tokenId].push(VoteAllocation({recipientId: recipientId, bps: bps, memberUnits: newUnits}));

        // update member units
        _updateMemberUnits(recipientAddress, memberUnits);

        // if recipient is a flow contract, set the flow rate for the child contract
        if (recipientType == RecipientType.FlowContract) {
            _setChildFlowRate(recipientAddress);
        }

        emit VoteCast(recipientId, tokenId, memberUnits, bps);
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
            FlowRecipient memory recipient = recipients[allocations[i].recipientId];

            // if recipient is removed, skip - don't want to update member units because they have been wiped to 0
            // fine because this vote will be deleted in the next step
            if (recipient.removed) continue;

            address recipientAddress = recipient.recipient;
            uint128 currentUnits = bonusPool.getUnits(recipientAddress);
            uint128 unitsDelta = allocations[i].memberUnits;
            RecipientType recipientType = recipient.recipientType;

            // Calculate the new units by subtracting the delta from the current units
            // Update the member units in the pool
            _updateMemberUnits(recipientAddress, currentUnits - unitsDelta);

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
     modifier validVotes(uint256[] memory recipientIds, uint32[] memory percentAllocations) {
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
            uint256 recipientId = recipientIds[i];
            if (recipientId >= recipientCount) revert INVALID_RECIPIENT_ID();
            if (recipients[recipientId].removed == true) revert NOT_APPROVED_RECIPIENT();
            if (percentAllocations[i] == 0) revert ALLOCATION_MUST_BE_POSITIVE();
        }

        _;
     }

    /**
     * @notice Cast a vote for a set of grant addresses.
     * @param tokenIds The tokenIds that the voter is using to vote.
     * @param recipientIds The recpientIds of the grant recipients.
     * @param percentAllocations The basis points of the vote to be split with the recipients.
     */
    function castVotes(uint256[] memory tokenIds, uint256[] memory recipientIds, uint32[] memory percentAllocations)
        external
        nonReentrant
        validVotes(recipientIds, percentAllocations)
    {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if (erc721Votes.ownerOf(tokenIds[i]) != msg.sender) revert NOT_TOKEN_OWNER();
            _setVotesAllocationForTokenId(tokenIds[i], recipientIds, percentAllocations);
        }
    }

    /**
     * @notice Cast a vote for a set of grant addresses.
     * @param tokenId The tokenId owned by the voter.
     * @param recipientIds The recipientIds of the grant recipients to vote for.
     * @param percentAllocations The basis points of the vote to be split with the recipients.
     */
    function _setVotesAllocationForTokenId(uint256 tokenId, uint256[] memory recipientIds, uint32[] memory percentAllocations)
        internal
    {
        uint256 weight = tokenVoteWeight;

        // _getSum should overflow if sum != PERCENTAGE_SCALE
        if (_getSum(percentAllocations) != PERCENTAGE_SCALE) revert INVALID_BPS_SUM();

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
     * @notice Increments the recipient counts
     * @dev This function increments both the total recipient count and the active recipient count
     * @dev This should be called whenever a new recipient is added
     */
    function _incrementRecipientCounts() internal {
        recipientCount++;
        activeRecipientCount++;
    }

    /**
     * @notice Adds an address to the list of approved recipients
     * @param recipient The address to be added as an approved recipient
     * @param metadata The ipfs hash of the recipient's metadata
     */
    function addRecipient(address recipient, RecipientMetadata memory metadata) public onlyManager nonReentrant validMetadata(metadata) {
        if (recipient == address(0)) revert ADDRESS_ZERO(); 

        recipients[recipientCount] = FlowRecipient({
            recipientType: RecipientType.ExternalAccount,
            removed: false,
            recipient: recipient,
            metadata: metadata
        });

        _incrementRecipientCounts();

        emit RecipientCreated(recipient, msg.sender);
    }

    /**
     * @notice Adds a new Flow contract as a recipient
     * @dev This function creates a new Flow contract and adds it as a recipient
     * @param metadata The IPFS hash of the recipient's metadata
     * @return address The address of the newly created Flow contract
     * @dev Only callable by the manager of the contract
     * @dev Emits a RecipientCreated event if the recipient is successfully added
     //todo who should own this new contract?
     */
    function addFlowRecipient(RecipientMetadata memory metadata, address flowManager) public onlyManager validMetadata(metadata) returns (address) {
        address recipient = address(new ERC1967Proxy(flowImpl, ""));
        if (recipient == address(0)) revert ADDRESS_ZERO();
        if (flowManager == address(0)) revert ADDRESS_ZERO();

        IFlow(recipient).initialize({
            nounsToken: address(erc721Votes),
            superToken: address(superToken),
            flowImpl: flowImpl,
            // so that a new TCR contract can control this new flow contract
            manager: flowManager,
            parent: address(this),
            flowParams: FlowParams({
                tokenVoteWeight: tokenVoteWeight
            }),
            metadata: metadata
        });

        Ownable2StepUpgradeable(recipient).transferOwnership(owner());

        // connect the new child contract to the pool!
        Flow(recipient).connectPool(bonusPool);

        recipients[recipientCount] = FlowRecipient({
            recipientType: RecipientType.FlowContract,
            removed: false,
            recipient: recipient,
            metadata: metadata
        });

        _incrementRecipientCounts();

        emit RecipientCreated(recipient, msg.sender);
        emit FlowCreated(address(this), recipient);

        return recipient;
    }

    /**
     * @notice Removes a recipient for receiving funds
     * @param recipientId The ID of the recipient to be approved
     * @dev Only callable by the manager of the contract
     * @dev Emits a RecipientRemoved event if the recipient is successfully removed
     */
    function removeRecipient(uint256 recipientId) public onlyManager nonReentrant {
        if (recipientId >= recipientCount) revert INVALID_RECIPIENT_ID();
        if (recipients[recipientId].removed) revert RECIPIENT_ALREADY_REMOVED();

        address recipientAddress = recipients[recipientId].recipient;

        // set member units to 0
        _updateMemberUnits(recipientAddress, 0);

        emit RecipientRemoved(recipientAddress, recipientId);

        recipients[recipientId].removed = true;
        activeRecipientCount--;
    }

    /**
     * @notice Sets the flow rate for a child Flow contract
     * @param childAddress The address of the child Flow contract
     */
    function _setChildFlowRate(address childAddress) internal {
        if (childAddress == address(0)) revert ADDRESS_ZERO();

        int96 memberFlowRate = getMemberFlowRate(childAddress);

        // Call setFlowRate on the child contract
        // only set if buffer required is less than balance of contract
        if(superToken.getBufferAmountByFlowRate(memberFlowRate) < superToken.balanceOf(childAddress)) {
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
    function _updateMemberUnits(address member, uint128 units) internal {
        bool success = superToken.updateMemberUnits(bonusPool, member, units);

        if (!success) revert UNITS_UPDATE_FAILED();
    }

    /**
     * @notice Sets the flow rate for the Superfluid pool
     * @param _flowRate The new flow rate to be set
     * @dev Only callable by the owner or parent of the contract
     * @dev Emits a FlowRateUpdated event with the old and new flow rates
     */
    function setFlowRate(int96 _flowRate) public onlyOwnerOrParent nonReentrant {
        emit FlowRateUpdated(bonusPool.getTotalFlowRate(), _flowRate);

        superToken.distributeFlow(address(this), bonusPool, _flowRate);
    }

    /**
     * @notice Sums array of uint32s
     *  @param numbers Array of uint32s to sum
     *  @return sum Sum of `numbers`.
     */
    function _getSum(uint32[] memory numbers) internal pure returns (uint32 sum) {
        // overflow should be impossible in for-loop index
        uint256 numbersLength = numbers.length;
        for (uint256 i = 0; i < numbersLength;) {
            sum += numbers[i];
            unchecked {
                // overflow should be impossible in for-loop index
                ++i;
            }
        }
    }

    /**
     * @notice Multiplies an amount by a scaled percentage
     *  @param amount Amount to get `scaledPercentage` of
     *  @param scaledPercent Percent scaled by PERCENTAGE_SCALE
     *  @return scaledAmount Percent of `amount`.
     */
    function _scaleAmountByPercentage(uint256 amount, uint256 scaledPercent)
        internal
        pure
        returns (uint256 scaledAmount)
    {
        // use assembly to bypass checking for overflow & division by 0
        // scaledPercent has been validated to be < PERCENTAGE_SCALE)
        // & PERCENTAGE_SCALE will never be 0
        assembly {
            /* eg (100 * 2*1e4) / (1e6) */
            scaledAmount := div(mul(amount, scaledPercent), PERCENTAGE_SCALE)
        }
    }

    /**
     * @notice Helper function to get the total units of a member in the pool
     * @param member The address of the member
     * @return units The total units of the member
     */
    function getPoolMemberUnits(address member) public view returns (uint128 units) {
        return bonusPool.getUnits(member);
    }

    /**
     * @notice Retrieves the net flow rate for a specific account
     * @return netFlowRate The net flow rate for the account
     */
    function getNetFlowRate() public view returns (int96 netFlowRate) {
        return superToken.getNetFlowRate(address(this));
    }

    /**
     * @notice Helper function to get the claimable balance for a member at the current time
     * @param member The address of the member
     * @return claimableBalance The claimable balance for the member
     */
    function getClaimableBalanceNow(address member) public view returns (int256 claimableBalance) {
        (claimableBalance,) = bonusPool.getClaimableNow(member);
    }

    /**
     * @notice Retrieves the flow rate for a specific member in the pool
     * @param memberAddr The address of the member
     * @return flowRate The flow rate for the member
     */
    function getMemberFlowRate(address memberAddr) public view returns (int96 flowRate) {
        flowRate = bonusPool.getMemberFlowRate(memberAddr);
    }

    /**
     * @notice Retrieves the total amount received by a specific member in the pool
     * @param memberAddr The address of the member
     * @return totalAmountReceived The total amount received by the member
     */
    function getTotalAmountReceivedByMember(address memberAddr) public view returns (uint256 totalAmountReceived) {
        totalAmountReceived = bonusPool.getTotalAmountReceivedByMember(memberAddr);
    }

    /**
     * @notice Retrieves the total units of the pool
     * @return totalUnits The total units of the pool
     */
    function getTotalUnits() public view returns (uint128 totalUnits) {
        totalUnits = bonusPool.getTotalUnits();
    }

    /**
     * @notice Retrieves the total flow rate of the pool
     * @return totalFlowRate The total flow rate of the pool
     */
    function getTotalFlowRate() public view returns (int96 totalFlowRate) {
        totalFlowRate = bonusPool.getTotalFlowRate();
    }

    /**
     * @notice Get the pool config
     * @return transferabilityForUnitsOwner The transferability for units owner
     * @return distributionFromAnyAddress The distribution from any address
     */
    function getPoolConfig() public view returns (bool transferabilityForUnitsOwner, bool distributionFromAnyAddress) {
        return (poolConfig.transferabilityForUnitsOwner, poolConfig.distributionFromAnyAddress);
    }

    /**
     * @notice Ensures the caller is authorized to upgrade the contract
     * @param _newImpl The new implementation address
     */
    function _authorizeUpgrade(address _newImpl) internal view override onlyOwner {}
}
