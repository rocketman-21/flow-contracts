// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

/// @author Wilson Cusack (https://github.com/wilsoncusack/state-proof-poc) and rocketman

import {IStateProof} from "../interfaces/IStateProof.sol";
import {StateVerifier} from "./StateVerifier.sol";

contract L2NounsVerifier {
    function isOwner(uint256 tokenId, address account, IStateProof.Parameters calldata proofParams)
        external
        view
        returns (bool)
    {
        return StateVerifier.validateState({
            account: 0x9C8fF314C9Bc7F6e59A9d9225Fb22946427eDC03, // Nouns Token on mainnet
            storageKey: abi.encodePacked(_getOwnerKey(tokenId)),
            storageValue: abi.encodePacked(account),
            proofParams: proofParams
        });
    }

    function canVoteWithToken(uint256 tokenId, address owner, address voter, IStateProof.Parameters calldata ownershipProof, IStateProof.Parameters calldata delegateProof)
        external
        view
        returns (bool)
    {
        bool isOwnerValid = this.isOwner(tokenId, owner, ownershipProof);
        bool isDelegateValid = this.isDelegate(owner, voter, delegateProof);

        return isOwnerValid && isDelegateValid;
    }

    function isDelegate(address owner, address delegate, IStateProof.Parameters calldata proofParams)
        external
        view
        returns (bool)
    {
        try this.validateDelegateState(owner, abi.encodePacked(delegate), proofParams) returns (bool result) {
            if (result) return true;
        } catch {}

        /// TODO try to handle no delegate case
        // try this.validateDelegateState(owner, abi.encodePacked(bytes32(0)), proofParams) returns (bool result) {
        //     if (result) return true;
        // } catch {}
        return false;
    }

    function validateDelegateState(
        address owner,
        bytes memory delegate,
        IStateProof.Parameters calldata proofParams
    ) external view returns (bool) {
        return StateVerifier.validateState({
            account: 0x9C8fF314C9Bc7F6e59A9d9225Fb22946427eDC03, // Nouns Token on mainnet
            storageKey: abi.encodePacked(_getDelegateKey(owner)),
            storageValue: delegate,
            proofParams: proofParams
        });
    }

    function _getOwnerKey(uint256 tokenId) private pure returns (bytes32) {
        return keccak256(
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
