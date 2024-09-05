// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @author Wilson Cusack (https://github.com/wilsoncusack/state-proof-poc)

import {L2NounsVerifierTest} from "./L2NounsVerifier.t.sol";

import {StateVerifier} from "../../src/state-proof/StateVerifier.sol";
import {L2NounsVerifier} from "../../src/state-proof/L2NounsVerifier.sol";

contract L2NounsVotingVerifier is L2NounsVerifierTest {

    function test__isOwnDelegateNoNouns() public {
        uint256 tokenId = 256;
        address account = 0x77D920b4d1163DbC516E7Ce70596225D17819dC5;

        vm.createSelectFork("https://mainnet.base.org", 19354086);
        L2NounsVerifier verifier = new L2NounsVerifier();

        string memory rootPath = vm.projectRoot();
        string memory delegatePath = string.concat(rootPath, "/test/proof-data/_delegates/", vm.toString(account), ".json");
        
        StateVerifier.StateProofParameters memory delegationParams = getStateProofParams(delegatePath);

        assertTrue(verifier.isDelegate(account, account, delegationParams));
        
        // this account owns no nouns - try to vote with wilsons token
        string memory ownershipPath = string.concat(rootPath, "/test/proof-data/_owners/", vm.toString(tokenId), ".json");
        StateVerifier.StateProofParameters memory params = getStateProofParams(ownershipPath);

        vm.expectRevert(abi.encodeWithSignature("StorageProofVerificationFailed()"));
        verifier.canVoteWithToken(tokenId, account, account, params, params);
    }

    function test__isDelegatedNouns() public {
        address delegate = 0xE30AcDdC6782d82C0CBE00349c27CB4E78C51510;
        address vaultNoun40 = 0xa555d1Ee16780B2d414eD97f4f169c0740099615;
        uint256 tokenId = 40;

        vm.createSelectFork("https://mainnet.base.org", 19382037);
        L2NounsVerifier verifier = new L2NounsVerifier();

        string memory rootPath = vm.projectRoot();
        string memory delegatePath = string.concat(rootPath, "/test/proof-data/_delegates/", vm.toString(vaultNoun40), ".json");
        string memory ownershipPath = string.concat(rootPath, "/test/proof-data/_owners/", vm.toString(tokenId), ".json");

        StateVerifier.StateProofParameters memory delegateProof = getStateProofParams(delegatePath);
        StateVerifier.StateProofParameters memory ownershipProof = getStateProofParams(ownershipPath);

        assertTrue(verifier.isDelegate(vaultNoun40, delegate, delegateProof));
        assertFalse(verifier.isDelegate(vaultNoun40, vaultNoun40, delegateProof));
        assertTrue(verifier.isOwner(tokenId, vaultNoun40, ownershipProof));
        assertTrue(verifier.canVoteWithToken(tokenId, vaultNoun40, delegate, ownershipProof, delegateProof));

        // can't vote with your own token that is delegated out
        assertFalse(verifier.canVoteWithToken(tokenId, vaultNoun40, vaultNoun40, ownershipProof, delegateProof));
    }
}
