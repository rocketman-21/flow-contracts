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
}
