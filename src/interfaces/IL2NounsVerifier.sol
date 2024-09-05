// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {StateVerifier} from "../state-proof/StateVerifier.sol";

interface IL2NounsVerifier {
    function isOwner(
        uint256 tokenId,
        address account,
        StateVerifier.StateProofParameters calldata proofParams
    ) external view returns (bool);

    function canVoteWithToken(
        uint256 tokenId,
        address owner,
        address voter,
        StateVerifier.StateProofParameters calldata ownershipProof,
        StateVerifier.StateProofParameters calldata delegateProof
    ) external view returns (bool);

    function isDelegate(
        address owner,
        address delegate,
        StateVerifier.StateProofParameters calldata proofParams
    ) external view returns (bool);
}

