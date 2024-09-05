// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @author Wilson Cusack (https://github.com/wilsoncusack/state-proof-poc)

import {Test, console2} from "forge-std/Test.sol";
import "forge-std/StdJson.sol";

import {StateVerifier} from "../../src/state-proof/StateVerifier.sol";
import {L2NounsVerifier} from "../../src/state-proof/L2NounsVerifier.sol";

contract L2NounsVotingVerifier is Test {
    using stdJson for string;

    function test__isOwnDelegateNoNouns() public {
        address account = 0x77D920b4d1163DbC516E7Ce70596225D17819dC5;
        vm.createSelectFork("https://mainnet.base.org", 19354086);
        L2NounsVerifier verifier = new L2NounsVerifier();
        string memory rootPath = vm.projectRoot();
        string memory path = string.concat(rootPath, "/test/proof-data/_delegates/0x77D920b4d1163DbC516E7Ce70596225D17819dC5.json");
        string memory delegateJson = vm.readFile(path);

        StateVerifier.StateProofParameters memory delegationParams = StateVerifier.StateProofParameters({
            beaconRoot: delegateJson.readBytes32(".beaconRoot"),
            beaconOracleTimestamp: uint256(delegateJson.readBytes32(".beaconOracleTimestamp")),
            executionStateRoot: delegateJson.readBytes32(".executionStateRoot"),
            stateRootProof: abi.decode(delegateJson.parseRaw(".stateRootProof"), (bytes32[])),
            storageProof: abi.decode(delegateJson.parseRaw(".storageProof"), (bytes[])),
            accountProof: abi.decode(delegateJson.parseRaw(".accountProof"), (bytes[]))
        });

        assertTrue(verifier.isDelegate(account, account, delegationParams));
        
        // this account owns no nouns - try to vote with wilsons token
        string memory ownershipJson = vm.readFile(string.concat(rootPath, "/test/proof-data/_owners/256.json"));

        StateVerifier.StateProofParameters memory params = StateVerifier.StateProofParameters({
            beaconRoot: ownershipJson.readBytes32(".beaconRoot"),
            beaconOracleTimestamp: uint256(ownershipJson.readBytes32(".beaconOracleTimestamp")),
            executionStateRoot: ownershipJson.readBytes32(".executionStateRoot"),
            stateRootProof: abi.decode(ownershipJson.parseRaw(".stateRootProof"), (bytes32[])),
            storageProof: abi.decode(ownershipJson.parseRaw(".storageProof"), (bytes[])),
            accountProof: abi.decode(ownershipJson.parseRaw(".accountProof"), (bytes[]))
        });
        vm.expectRevert(abi.encodeWithSignature("StorageProofVerificationFailed()"));
        verifier.canVoteWithToken(256, account, account, params, params);
    }
}
