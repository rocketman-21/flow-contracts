// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @author Wilson Cusack (https://github.com/wilsoncusack/state-proof-poc) and rocketman

import { IStateProof } from "../interfaces/IStateProof.sol";
import { StateVerifier } from "./StateVerifier.sol";

contract TokenVerifier {
    address private immutable TOKEN_ADDRESS;

    constructor(address _tokenAddress) {
        require(_tokenAddress != address(0), "Invalid token address");
        TOKEN_ADDRESS = _tokenAddress;
    }

    function isOwner(
        uint256 tokenId,
        address account,
        IStateProof.Parameters calldata proofParams
    ) external view returns (bool) {
        return
            StateVerifier.validateState({
                account: TOKEN_ADDRESS,
                storageKey: abi.encodePacked(_getOwnerKey(tokenId)),
                storageValue: abi.encodePacked(account),
                proofParams: proofParams
            });
    }

    function canVoteWithToken(
        uint256 tokenId,
        address owner,
        address voter,
        IStateProof.Parameters calldata ownershipProof,
        IStateProof.Parameters calldata delegateProof
    ) external view returns (bool) {
        bool isOwnerValid = this.isOwner(tokenId, owner, ownershipProof);
        bool isDelegateValid = this.isDelegate(owner, voter, delegateProof);

        return isOwnerValid && isDelegateValid;
    }

    function isDelegate(
        address owner,
        address delegate,
        IStateProof.Parameters calldata proofParams
    ) external view returns (bool) {
        try this.validateDelegateState(owner, abi.encodePacked(delegate), proofParams) returns (bool result) {
            if (result) return true;
        } catch {}

        /// @notice Handles this case in the `delegates` function of NounsToken
        /**
         * @notice Overrides the standard `Comp.sol` delegates mapping to return
         * the delegator's own address if they haven't delegated.
         * This avoids having to delegate to oneself.
         */
        // function delegates(address delegator) public view returns (address) {
        //     address current = _delegates[delegator];
        //     return current == address(0) ? delegator : current;
        // }
        bool isDelegateSlotEmpty = StateVerifier.validateIsStorageSlotEmpty({
            account: TOKEN_ADDRESS,
            storageKey: abi.encodePacked(_getDelegateKey(owner)),
            proofParams: proofParams
        });
        /// @notice Assumes that the owner of this token is verified to be correct
        /// @notice This is true for NounsToken only
        if (isDelegateSlotEmpty && owner == delegate) return true;

        return false;
    }

    function validateDelegateState(
        address owner,
        bytes memory delegate,
        IStateProof.Parameters calldata proofParams
    ) external view returns (bool) {
        return
            StateVerifier.validateState({
                account: TOKEN_ADDRESS,
                storageKey: abi.encodePacked(_getDelegateKey(owner)),
                storageValue: delegate,
                proofParams: proofParams
            });
    }

    function _getOwnerKey(uint256 tokenId) private pure returns (bytes32) {
        return
            keccak256(
                abi.encode(
                    tokenId,
                    3 // _owner slot
                )
            );
    }

    function _getDelegateKey(address delegator) private pure returns (bytes32) {
        return keccak256(abi.encode(delegator, 11));
    }
}
