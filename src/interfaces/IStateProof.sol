// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface IStateProof {
    struct Parameters {
        bytes32 beaconRoot;
        uint256 beaconOracleTimestamp;
        bytes32 executionStateRoot;
        bytes32[] stateRootProof;
        bytes[] accountProof;
        bytes[] storageProof;
    }

    struct BaseParameters {
        bytes32 beaconRoot;
        uint256 beaconOracleTimestamp;
        bytes32 executionStateRoot;
        bytes32[] stateRootProof;
        bytes[] accountProof;
    }
}
