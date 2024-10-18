// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { Test, console2 } from "forge-std/Test.sol";
import "forge-std/StdJson.sol";

import { StateVerifier } from "../../src/state-proof/StateVerifier.sol";
import { TokenVerifier } from "../../src/state-proof/TokenVerifier.sol";
import { IStateProof } from "../../src/interfaces/IStateProof.sol";

contract TokenVerifierTest is Test {
    using stdJson for string;

    address NOUNS_TOKEN_ADDRESS = 0x9C8fF314C9Bc7F6e59A9d9225Fb22946427eDC03;

    function getStateProofParams(string memory path) internal view returns (IStateProof.Parameters memory) {
        string memory json = vm.readFile(path);
        return
            IStateProof.Parameters({
                beaconRoot: json.readBytes32(".beaconRoot"),
                beaconOracleTimestamp: uint256(json.readBytes32(".beaconOracleTimestamp")),
                executionStateRoot: json.readBytes32(".executionStateRoot"),
                stateRootProof: abi.decode(json.parseRaw(".stateRootProof"), (bytes32[])),
                storageProof: abi.decode(json.parseRaw(".storageProof"), (bytes[])),
                accountProof: abi.decode(json.parseRaw(".accountProof"), (bytes[]))
            });
    }
}
