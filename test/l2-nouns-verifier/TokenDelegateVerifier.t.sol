// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @author Wilson Cusack (https://github.com/wilsoncusack/state-proof-poc)

import { TokenVerifierTest } from "./TokenVerifier.t.sol";

import { TokenVerifier } from "../../src/state-proof/TokenVerifier.sol";
import { IStateProof } from "../../src/interfaces/IStateProof.sol";

contract L2NounsDelegateVerifier is TokenVerifierTest {
    function test__isOwnDelegateHasDelegatedToSelf() public {
        address account = 0x77D920b4d1163DbC516E7Ce70596225D17819dC5;
        vm.createSelectFork("https://mainnet.base.org", 19354086);
        TokenVerifier verifier = new TokenVerifier(NOUNS_TOKEN_ADDRESS);
        string memory rootPath = vm.projectRoot();

        string memory path = string.concat(rootPath, "/test/proof-data/_delegates/", vm.toString(account), ".json");

        IStateProof.Parameters memory delegationParams = getStateProofParams(path);

        assertTrue(verifier.isDelegate(account, account, delegationParams));
    }

    // TODO try to fix this
    // check that even if they have not explicitly delegated to self, they are still an owner delegate
}
