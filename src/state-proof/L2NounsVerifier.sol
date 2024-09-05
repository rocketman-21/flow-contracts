// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @author Wilson Cusack (https://github.com/wilsoncusack/state-proof-poc)

import {StateVerifier} from "./StateVerifier.sol";
import {ERC721Checkpointable} from "../base/ERC721Checkpointable.sol";

contract L2NounsVerifier {
    function isOwner(uint256 tokenId, address account, StateVerifier.StateProofParameters calldata proofParams)
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

    function isOwnDelegate(address owner, StateVerifier.StateProofParameters calldata proofParams)
        external
        view
        returns (bool)
    {
        try this.validateDelegateState(owner, abi.encodePacked(owner), proofParams) returns (bool result) {
            if (result) return true;
        } catch {}

        // try this.validateDelegateState(owner, abi.encodePacked(bytes32(0)), proofParams) returns (bool result) {
        //     if (result) return true;
        // } catch {}

        return false;
    }

    function validateDelegateState(
        address owner,
        bytes memory storageValue,
        StateVerifier.StateProofParameters calldata proofParams
    ) external view returns (bool) {
        return StateVerifier.validateState({
            account: 0x9C8fF314C9Bc7F6e59A9d9225Fb22946427eDC03, // Nouns Token on mainnet
            storageKey: abi.encodePacked(_getDelegateKey(owner)),
            storageValue: storageValue,
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
        // Note: Replace X with the correct slot number for _delegates mapping
        // shows 10 with forge inspect, might be 11th slot though?
        return keccak256(abi.encode(delegator, 11));
    }
}
