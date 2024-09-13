// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/// @author Wilson Cusack (https://github.com/wilsoncusack/state-proof-poc)

import { TokenVerifierTest } from "./TokenVerifier.t.sol";
import { stdJson } from "forge-std/StdJson.sol";

import { StateVerifier } from "../../src/state-proof/StateVerifier.sol";
import { TokenVerifier } from "../../src/state-proof/TokenVerifier.sol";
import { IStateProof } from "../../src/interfaces/IStateProof.sol";

contract L2NounsVotingVerifier is TokenVerifierTest {
    using stdJson for string;

    function test__isOwnDelegateNoNouns() public {
        uint256 tokenId = 256;
        address account = 0x77D920b4d1163DbC516E7Ce70596225D17819dC5;

        vm.createSelectFork("https://mainnet.base.org", 19354086);
        TokenVerifier verifier = new TokenVerifier(NOUNS_TOKEN_ADDRESS);

        string memory rootPath = vm.projectRoot();
        string memory delegatePath = string.concat(
            rootPath,
            "/test/proof-data/_delegates/",
            vm.toString(account),
            ".json"
        );

        IStateProof.Parameters memory delegationParams = getStateProofParams(delegatePath);

        assertTrue(verifier.isDelegate(account, account, delegationParams));

        // this account owns no nouns - try to vote with wilsons token
        string memory ownershipPath = string.concat(
            rootPath,
            "/test/proof-data/_owners/",
            vm.toString(tokenId),
            ".json"
        );
        IStateProof.Parameters memory params = getStateProofParams(ownershipPath);

        vm.expectRevert(abi.encodeWithSignature("StorageProofVerificationFailed()"));
        verifier.canVoteWithToken(tokenId, account, account, params, params);
    }

    function test__isDelegatedNouns() public {
        address delegate = 0xE30AcDdC6782d82C0CBE00349c27CB4E78C51510;
        address vaultNoun40 = 0xa555d1Ee16780B2d414eD97f4f169c0740099615;
        uint256 tokenId = 40;

        vm.createSelectFork("https://mainnet.base.org", 19382037);
        TokenVerifier verifier = new TokenVerifier(NOUNS_TOKEN_ADDRESS);

        string memory rootPath = vm.projectRoot();
        string memory delegatePath = string.concat(
            rootPath,
            "/test/proof-data/_delegates/",
            vm.toString(vaultNoun40),
            ".json"
        );
        string memory ownershipPath = string.concat(
            rootPath,
            "/test/proof-data/_owners/",
            vm.toString(tokenId),
            ".json"
        );

        IStateProof.Parameters memory delegateProof = getStateProofParams(delegatePath);
        IStateProof.Parameters memory ownershipProof = getStateProofParams(ownershipPath);

        assertTrue(verifier.isDelegate(vaultNoun40, delegate, delegateProof));
        assertFalse(verifier.isDelegate(vaultNoun40, vaultNoun40, delegateProof));
        assertTrue(verifier.isOwner(tokenId, vaultNoun40, ownershipProof));
        assertTrue(verifier.canVoteWithToken(tokenId, vaultNoun40, delegate, ownershipProof, delegateProof));

        // can't vote with your own token that is delegated out
        assertFalse(verifier.canVoteWithToken(tokenId, vaultNoun40, vaultNoun40, ownershipProof, delegateProof));
    }

    function test__proofVerificationWithSpecificBlock() public {
        uint256 blockNumber = 19727628;
        address delegator = 0x6cC34D9Fb4AE289256fc1896308D387Aee2bCc52;
        uint256 tokenId = 1;

        vm.createSelectFork("https://mainnet.base.org", blockNumber);
        TokenVerifier verifier = new TokenVerifier(0xDA7C313e392e75C6179f5F9Cd8952075ac3E1EC5);

        string memory rootPath = vm.projectRoot();
        string memory proofPath = string.concat(
            rootPath,
            "/test/proof-data/proofs[",
            vm.toString(delegator),
            "][",
            vm.toString(tokenId),
            "].json"
        );

        string memory json = vm.readFile(proofPath);

        IStateProof.Parameters memory ownershipProof = IStateProof.Parameters({
            beaconRoot: json.readBytes32(".beaconRoot"),
            beaconOracleTimestamp: uint256(json.readBytes32(".beaconOracleTimestamp")),
            executionStateRoot: json.readBytes32(".executionStateRoot"),
            stateRootProof: abi.decode(json.parseRaw(".stateRootProof"), (bytes32[])),
            storageProof: abi.decode(json.parseRaw(".ownershipStorageProof"), (bytes[])),
            accountProof: abi.decode(json.parseRaw(".accountProof"), (bytes[]))
        });
        IStateProof.Parameters memory delegateProof = IStateProof.Parameters({
            beaconRoot: json.readBytes32(".beaconRoot"),
            beaconOracleTimestamp: uint256(json.readBytes32(".beaconOracleTimestamp")),
            executionStateRoot: json.readBytes32(".executionStateRoot"),
            stateRootProof: abi.decode(json.parseRaw(".stateRootProof"), (bytes32[])),
            storageProof: abi.decode(json.parseRaw(".delegateStorageProofs[0]"), (bytes[])),
            accountProof: abi.decode(json.parseRaw(".accountProof"), (bytes[]))
        });

        // Verify ownership
        assertTrue(verifier.isOwner(tokenId, delegator, ownershipProof));

        // // Verify delegation (assuming self-delegation in this case)
        assertTrue(verifier.isDelegate(delegator, delegator, delegateProof));

        // // Verify ability to vote
        // assertTrue(verifier.canVoteWithToken(tokenId, delegator, delegator, ownershipProof, delegateProof));
    }
}
