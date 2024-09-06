// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

import {IStateProof} from "./IStateProof.sol";

interface IL2NounsVerifier {
    function isOwner(
        uint256 tokenId,
        address account,
        IStateProof.Parameters calldata proofParams
    ) external view returns (bool);

    function canVoteWithToken(
        uint256 tokenId,
        address owner,
        address voter,
        IStateProof.Parameters calldata ownershipProof,
        IStateProof.Parameters calldata delegateProof
    ) external view returns (bool);

    function isDelegate(
        address owner,
        address delegate,
        IStateProof.Parameters calldata proofParams
    ) external view returns (bool);
}

