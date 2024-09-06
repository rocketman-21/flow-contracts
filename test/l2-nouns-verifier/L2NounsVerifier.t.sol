// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {Test, console2} from "forge-std/Test.sol";
import "forge-std/StdJson.sol";

import {StateVerifier} from "../../src/state-proof/StateVerifier.sol";
import {L2NounsVerifier} from "../../src/state-proof/L2NounsVerifier.sol";
import {IStateProof} from "../../src/interfaces/IStateProof.sol";

contract L2NounsVerifierTest is Test {
    using stdJson for string;

    function getStateProofParams(string memory path) internal returns (IStateProof.Parameters memory) {
        string memory json = vm.readFile(path);
        return IStateProof.Parameters({
            beaconRoot: json.readBytes32(".beaconRoot"),
            beaconOracleTimestamp: uint256(json.readBytes32(".beaconOracleTimestamp")),
            executionStateRoot: json.readBytes32(".executionStateRoot"),
            stateRootProof: abi.decode(json.parseRaw(".stateRootProof"), (bytes32[])),
            storageProof: abi.decode(json.parseRaw(".storageProof"), (bytes[])),
            accountProof: abi.decode(json.parseRaw(".accountProof"), (bytes[]))
        });
    }

    // Add more helper functions or setup as needed
}
