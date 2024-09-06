// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @author Wilson Cusack (https://github.com/wilsoncusack/state-proof-poc)

import {L2NounsVerifierTest} from "./L2NounsVerifier.t.sol";

import {L2NounsVerifier} from "../../src/state-proof/L2NounsVerifier.sol";
import {IStateProof} from "../../src/interfaces/IStateProof.sol";

contract L2NounsOwnershipVerifierTest is L2NounsVerifierTest {

    function test__isOwner() public {
        uint256 tokenId = 256;
        vm.createSelectFork("https://mainnet.base.org", 19354086);
        L2NounsVerifier verifier = new L2NounsVerifier();
        string memory rootPath = vm.projectRoot();
        string memory path = string.concat(rootPath, "/test/proof-data/_owners/", vm.toString(tokenId), ".json");
        
        IStateProof.Parameters memory params = getStateProofParams(path);

        assertTrue(verifier.isOwner(tokenId, 0xb1a32FC9F9D8b2cf86C068Cae13108809547ef71, params));
    }

    function test__isNotOwner() public {
        uint256 tokenId = 256;
        vm.createSelectFork("https://mainnet.base.org", 19354086);
        L2NounsVerifier verifier = new L2NounsVerifier();
        string memory rootPath = vm.projectRoot();
        string memory path = string.concat(rootPath, "/test/proof-data/_owners/", vm.toString(tokenId), ".json");
        
        IStateProof.Parameters memory params = getStateProofParams(path);

        vm.expectRevert(abi.encodeWithSignature("StorageProofVerificationFailed()"));
        verifier.isOwner(tokenId, 0x0000000000000000000000000000000000000000, params);
    }
}
