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
     * @param _flowParams The parameters for the flow contract
     */
    function initialize(address _nounsToken, address _superToken, address _flowImpl, FlowParams memory _flowParams)
        public
        initializer
    {
        if (_nounsToken == address(0)) revert ADDRESS_ZERO();
        if (_flowImpl == address(0)) revert ADDRESS_ZERO();

        // Initialize EIP-712 support
        __EIP712_init("Flow", "1");
        __Ownable_init();
        __ReentrancyGuard_init();

        // Set the voting power info
        erc721Votes = IERC721Checkpointable(_nounsToken);
        tokenVoteWeight = _flowParams.tokenVoteWeight;
        flowImpl = _flowImpl;

        superToken = ISuperToken(_superToken);
        pool = superToken.createPool(address(this), poolConfig);

        // if total member units is 0, set 1 member unit to address(this)
        // do this to prevent distribution pool from resetting flow rate to 0
        if (getTotalUnits() == 0) {
            updateMemberUnits(address(this), 1);
        }

        emit FlowInitialized(msg.sender, _superToken, _flowImpl);
    }

    /**
     * @notice Sets the address of the grants implementation contract
     * @param _flowImpl The new address of the grants implementation contract
     */
    function setFlowImpl(address _flowImpl) public onlyOwner {
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
     * @param recipient The address of the grant recipient.
     * @param bps The basis points of the vote to be split with the recipient.
     * @param tokenId The tokenId owned by the voter.
     * @param totalWeight The voting power of the voter.
     * @dev Requires that the recipient is valid, and the weight is greater than the minimum vote weight.
     * Emits a VoteCast event upon successful execution.
     */
    function _vote(address recipient, uint32 bps, uint256 tokenId, uint256 totalWeight) internal {
        if (recipient == address(0)) revert ADDRESS_ZERO();
        if (approvedRecipients[recipient] == false) revert NOT_APPROVED_RECIPIENT();

        // calculate new member units for recipient
        // make sure to add the current units to the new units
        uint128 currentUnits = pool.getUnits(recipient);

        // double check for overflow before casting
        // and scale back by 1e15 per https://docs.superfluid.finance/docs/protocol/distributions/guides/pools#about-member-units
        // gives someone with 1 vote at least 1e3 units to work with
        uint256 scaledUnits = _scaleAmountByPercentage(totalWeight, bps) / 1e15;
        if (scaledUnits > type(uint128).max) revert OVERFLOW();
        uint128 newUnits = uint128(scaledUnits);

        uint128 memberUnits = currentUnits + newUnits;

        // update votes, track recipient, bps, and total member units assigned
        votes[tokenId].push(VoteAllocation({recipient: recipient, bps: bps, memberUnits: newUnits}));

        // update member units
        updateMemberUnits(recipient, memberUnits);

        emit VoteCast(recipient, tokenId, memberUnits, bps);
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
            address recipient = allocations[i].recipient;
            uint128 currentUnits = pool.getUnits(recipient);
            uint128 unitsDelta = allocations[i].memberUnits;

            // Calculate the new units by subtracting the delta from the current units
            // Update the member units in the pool
            updateMemberUnits(recipient, currentUnits - unitsDelta);
        }

        // Clear out the votes for the tokenId
        delete votes[tokenId];
    }

    /**
     * @notice Cast a vote for a set of grant addresses.
     * @param tokenIds The tokenIds of the grant recipients.
     * @param recipients The addresses of the grant recipients.
     * @param percentAllocations The basis points of the vote to be split with the recipients.
     */
    function setVotesAllocations(uint256[] memory tokenIds, address[] memory recipients, uint32[] memory percentAllocations)
        external
        nonReentrant
    {
        for (uint256 i = 0; i < tokenIds.length; i++) {
            if(erc721Votes.ownerOf(tokenIds[i]) != msg.sender) revert NOT_TOKEN_OWNER();
            _setVotesAllocations(tokenIds[i], recipients, percentAllocations);
        }
    }

    /**
     * @notice Cast a vote for a set of grant addresses.
     * @param tokenId The tokenId owned by the voter.
     * @param recipients The addresses of the grant recipients.
     * @param percentAllocations The basis points of the vote to be split with the recipients.
     */
    function _setVotesAllocations(uint256 tokenId, address[] memory recipients, uint32[] memory percentAllocations)
        internal
    {
        uint256 weight = tokenVoteWeight;

        // _getSum should overflow if sum != PERCENTAGE_SCALE
        if (_getSum(percentAllocations) != PERCENTAGE_SCALE) revert INVALID_BPS_SUM();

        // update member units for previous votes
        _clearPreviousVotes(tokenId);

        // set new votes
        for (uint256 i = 0; i < recipients.length; i++) {
            _vote(recipients[i], percentAllocations[i], tokenId, weight);
        }
    }

    /**
     * @notice Adds an address to the list of approved recipients
     * @param recipient The address to be added as an approved recipient
     */
    function addApprovedRecipient(address recipient) public {
        if (recipient == address(0)) revert ADDRESS_ZERO();

        approvedRecipients[recipient] = true;

        emit GrantRecipientApproved(recipient, msg.sender);
    }

    /**
     * @notice Updates the member units in the Superfluid pool
     * @param member The address of the member whose units are being updated
     * @param units The new number of units to be assigned to the member
     * @dev Reverts with UNITS_UPDATE_FAILED if the update fails
     */
    function updateMemberUnits(address member, uint128 units) internal {
        bool success = superToken.updateMemberUnits(pool, member, units);

        if (!success) revert UNITS_UPDATE_FAILED();
    }

    /**
     * @notice Sets the flow rate for the Superfluid pool
     * @param _flowRate The new flow rate to be set
     * @dev Only callable by the owner of the contract
     * @dev Emits a FlowRateUpdated event with the old and new flow rates
     */
    function setFlowRate(int96 _flowRate) public onlyOwner {
        emit FlowRateUpdated(pool.getTotalFlowRate(), _flowRate);

        superToken.distributeFlow(address(this), pool, _flowRate);
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
        return pool.getUnits(member);
    }

    /**
     * @notice Helper function to claim all tokens for a member from the pool
     * @param member The address of the member
     */
    function claimAllFromPool(address member) public {
        pool.claimAll(member);
    }

    /**
     * @notice Helper function to get the claimable balance for a member at the current time
     * @param member The address of the member
     * @return claimableBalance The claimable balance for the member
     */
    function getClaimableBalanceNow(address member) public view returns (int256 claimableBalance) {
        (claimableBalance,) = pool.getClaimableNow(member);
    }

    /**
     * @notice Retrieves the flow rate for a specific member in the pool
     * @param memberAddr The address of the member
     * @return flowRate The flow rate for the member
     */
    function getMemberFlowRate(address memberAddr) public view returns (int96 flowRate) {
        flowRate = pool.getMemberFlowRate(memberAddr);
    }

    /**
     * @notice Retrieves the total amount received by a specific member in the pool
     * @param memberAddr The address of the member
     * @return totalAmountReceived The total amount received by the member
     */
    function getTotalAmountReceivedByMember(address memberAddr) public view returns (uint256 totalAmountReceived) {
        totalAmountReceived = pool.getTotalAmountReceivedByMember(memberAddr);
    }

    /**
     * @notice Retrieves the total units of the pool
     * @return totalUnits The total units of the pool
     */
    function getTotalUnits() public view returns (uint128 totalUnits) {
        totalUnits = pool.getTotalUnits();
    }

    /**
     * @notice Retrieves the total flow rate of the pool
     * @return totalFlowRate The total flow rate of the pool
     */
    function getTotalFlowRate() public view returns (int96 totalFlowRate) {
        totalFlowRate = pool.getTotalFlowRate();
    }

    /**
     * @notice Ensures the caller is authorized to upgrade the contract
     * @param _newImpl The new implementation address
     */
    function _authorizeUpgrade(address _newImpl) internal view override onlyOwner {}

    /**
     * @notice Get the pool config
     * @return transferabilityForUnitsOwner The transferability for units owner
     * @return distributionFromAnyAddress The distribution from any address
     */
    function getPoolConfig() public view returns (bool transferabilityForUnitsOwner, bool distributionFromAnyAddress) {
        return (poolConfig.transferabilityForUnitsOwner, poolConfig.distributionFromAnyAddress);
    }
}
