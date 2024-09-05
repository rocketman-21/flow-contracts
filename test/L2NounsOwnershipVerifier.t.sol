// SPDX-License-Identifier: MIT
pragma solidity ^0.8.23;

/// @author Wilson Cusack (https://github.com/wilsoncusack/state-proof-poc)

import {Test, console2} from "forge-std/Test.sol";
import "forge-std/StdJson.sol";

import {StateVerifier} from "../src/state-proof/StateVerifier.sol";
import {L2NounsVerifier} from "../src/state-proof/L2NounsVerifier.sol";

contract L2NounsOwnershipVerifierTest is Test {
    using stdJson for string;

    function test__isOwner() public {
        vm.createSelectFork("https://mainnet.base.org", 19354086);
        L2NounsVerifier verifier = new L2NounsVerifier();
        string memory rootPath = vm.projectRoot();
        string memory path = string.concat(rootPath, "/test/proof-data/_owners/256.json");
        string memory json = vm.readFile(path);

        StateVerifier.StateProofParameters memory params = StateVerifier.StateProofParameters({
            beaconRoot: json.readBytes32(".beaconRoot"),
            beaconOracleTimestamp: uint256(json.readBytes32(".beaconOracleTimestamp")),
            executionStateRoot: json.readBytes32(".executionStateRoot"),
            stateRootProof: abi.decode(json.parseRaw(".stateRootProof"), (bytes32[])),
            storageProof: abi.decode(json.parseRaw(".storageProof"), (bytes[])),
            accountProof: abi.decode(json.parseRaw(".accountProof"), (bytes[]))
        });
        assertTrue(verifier.isOwner(256, 0xb1a32FC9F9D8b2cf86C068Cae13108809547ef71, params));
    }

    function test__isNotOwner() public {
        vm.createSelectFork("https://mainnet.base.org", 19354086);
        L2NounsVerifier verifier = new L2NounsVerifier();
        string memory rootPath = vm.projectRoot();
        string memory path = string.concat(rootPath, "/test/proof-data/_owners/256.json");
        string memory json = vm.readFile(path);

        StateVerifier.StateProofParameters memory params = StateVerifier.StateProofParameters({
            beaconRoot: json.readBytes32(".beaconRoot"),
            beaconOracleTimestamp: uint256(json.readBytes32(".beaconOracleTimestamp")),
            executionStateRoot: json.readBytes32(".executionStateRoot"),
            stateRootProof: abi.decode(json.parseRaw(".stateRootProof"), (bytes32[])),
            storageProof: abi.decode(json.parseRaw(".storageProof"), (bytes[])),
            accountProof: abi.decode(json.parseRaw(".accountProof"), (bytes[]))
        });

        vm.expectRevert(abi.encodeWithSignature("StorageProofVerificationFailed()"));
        verifier.isOwner(256, 0x0000000000000000000000000000000000000000, params);
    }
}
