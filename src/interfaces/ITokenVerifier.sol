// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {IStateProof} from "./IStateProof.sol";

interface ITokenVerifier {
    function canVoteWithToken(
        uint256 tokenId,
        address owner,
        address voter,
        IStateProof.Parameters calldata ownershipProof,
        IStateProof.Parameters calldata delegateProof
    ) external view returns (bool);
}

