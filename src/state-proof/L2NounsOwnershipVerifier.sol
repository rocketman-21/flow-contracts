// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @author Wilson Cusack (https://github.com/wilsoncusack/state-proof-poc)

import {StateVerifier} from "./StateVerifier.sol";

contract L2NounsOwnershipVerifier {
    function isOwner(uint256 tokenId, address account, StateVerifier.StateProofParameters calldata proofParams)
        external
        view
        returns (bool)
    {
        return StateVerifier.validateState({
            account: 0x9C8fF314C9Bc7F6e59A9d9225Fb22946427eDC03, // Nouns Token on mainnet
            storageKey: abi.encodePacked(_getKey(tokenId)),
            storageValue: abi.encodePacked(account),
            proofParams: proofParams
        });
    }

    function _getKey(uint256 tokenId) private pure returns (bytes32) {
        return keccak256(
            abi.encode(
                tokenId,
                3 // _owner slot
            )
        );
    }
}
