// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import { stdJson } from "forge-std/StdJson.sol";
import { NounsFlowTest } from "./NounsFlow.t.sol";
import { IFlowEvents, IFlow } from "../../src/interfaces/IFlow.sol";
import { Flow } from "../../src/Flow.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { TestToken } from "@superfluid-finance/ethereum-contracts/contracts/utils/TestToken.sol";
import { console } from "forge-std/console.sol";
import { IStateProof } from "../../src/interfaces/IStateProof.sol";

contract NounsVotingFlowTest is NounsFlowTest {
    using stdJson for string;

    function _setupTestParameters()
        internal
        returns (address[] memory, uint256[][] memory, bytes32[] memory, uint32[] memory, address)
    {
        address recipient1 = address(0x1);
        address recipient2 = address(0x2);

        address[] memory owners = new address[](1);
        owners[0] = 0xA2b6590A6dC916fe317Dcab169a18a5B87A5c3d5; // safe
        address delegate = 0x65599970Af18EeA5f4ec0B82f23B018fd15EBd11; // delegate

        uint256[][] memory tokenIds = new uint256[][](1);
        tokenIds[0] = new uint256[](2);
        tokenIds[0][0] = 788;
        tokenIds[0][1] = 832;

        bytes32[] memory recipientIds = new bytes32[](2);

        vm.startPrank(manager);
        bytes32 recipientId1 = keccak256(abi.encodePacked(recipient1));
        bytes32 recipientId2 = keccak256(abi.encodePacked(recipient2));
        flow.addRecipient(recipientId1, recipient1, recipientMetadata);
        flow.addRecipient(recipientId2, recipient2, recipientMetadata);
        vm.stopPrank();

        recipientIds[0] = recipientId1;
        recipientIds[1] = recipientId2;

        uint32[] memory percentAllocations = new uint32[](2);
        percentAllocations[0] = 1e6 / 2; // 50%
        percentAllocations[1] = 1e6 / 2; // 50%

        return (owners, tokenIds, recipientIds, percentAllocations, delegate);
    }

    function test__castVotes() public {
        _setUpWithForkBlock(19434510);

        // Set up test parameters
        (
            address[] memory owners,
            uint256[][] memory tokenIds,
            bytes32[] memory recipientIds,
            uint32[] memory percentAllocations,
            address delegate
        ) = _setupTestParameters();

        // Fetch ownership proof
        IStateProof.BaseParameters memory baseParams = _setupBaseParameters();
        (bytes[][][] memory ownershipStorageProofs, bytes[][] memory delegateStorageProofs) = _setupStorageProofs();

        // Cast votes
        vm.prank(delegate);
        flow.castVotes(
            owners,
            tokenIds,
            recipientIds,
            percentAllocations,
            baseParams,
            ownershipStorageProofs,
            delegateStorageProofs
        );

        // Add assertions to verify the votes were cast correctly
        // For example, you could check the allocation for each recipient
    }

    function test__isDelegate() public {
        _setUpWithForkBlock(19434588);

        address delegator = 0xA2b6590A6dC916fe317Dcab169a18a5B87A5c3d5;
        address delegate = 0x65599970Af18EeA5f4ec0B82f23B018fd15EBd11;

        IStateProof.BaseParameters memory baseParams = _setupBaseParameters();
        (, bytes[][] memory delegateStorageProofs) = _setupStorageProofs();

        assertTrue(
            verifier.isDelegate(
                delegator,
                delegate,
                IStateProof.Parameters({
                    beaconRoot: baseParams.beaconRoot,
                    beaconOracleTimestamp: baseParams.beaconOracleTimestamp,
                    executionStateRoot: baseParams.executionStateRoot,
                    stateRootProof: baseParams.stateRootProof,
                    storageProof: delegateStorageProofs[0],
                    accountProof: baseParams.accountProof
                })
            )
        );
    }

    function test__isOwner788() public {
        _setUpWithForkBlock(19434588);

        uint256 tokenId = 788;
        address owner = 0xA2b6590A6dC916fe317Dcab169a18a5B87A5c3d5;

        IStateProof.BaseParameters memory baseParams = _setupBaseParameters();
        (bytes[][][] memory ownershipStorageProofs, ) = _setupStorageProofs();

        assertTrue(
            verifier.isOwner(
                tokenId,
                owner,
                IStateProof.Parameters({
                    beaconRoot: baseParams.beaconRoot,
                    beaconOracleTimestamp: baseParams.beaconOracleTimestamp,
                    executionStateRoot: baseParams.executionStateRoot,
                    stateRootProof: baseParams.stateRootProof,
                    storageProof: ownershipStorageProofs[0][0],
                    accountProof: baseParams.accountProof
                })
            )
        );

        // try to mess with timestamp and make a past proof for the future
        baseParams.beaconOracleTimestamp += 1;
        vm.expectRevert();
        verifier.isOwner(
            tokenId,
            owner,
            IStateProof.Parameters({
                beaconRoot: baseParams.beaconRoot,
                beaconOracleTimestamp: baseParams.beaconOracleTimestamp,
                executionStateRoot: baseParams.executionStateRoot,
                stateRootProof: baseParams.stateRootProof,
                storageProof: ownershipStorageProofs[0][0],
                accountProof: baseParams.accountProof
            })
        );
    }

    function test__isOwner832() public {
        _setUpWithForkBlock(19434588);

        uint256 tokenId = 832;
        address owner = 0xA2b6590A6dC916fe317Dcab169a18a5B87A5c3d5;

        string memory rootPath = vm.projectRoot();
        string memory proofPath = string.concat(rootPath, "/test/proof-data/papercliplabs.json");
        string memory json = vm.readFile(proofPath);

        IStateProof.BaseParameters memory baseParams = _setupBaseParameters();

        bytes[] memory ownershipStorageProof = abi.decode(json.parseRaw(".ownershipStorageProof2"), (bytes[]));

        assertTrue(
            verifier.isOwner(
                tokenId,
                owner,
                IStateProof.Parameters({
                    beaconRoot: baseParams.beaconRoot,
                    beaconOracleTimestamp: baseParams.beaconOracleTimestamp,
                    executionStateRoot: baseParams.executionStateRoot,
                    stateRootProof: baseParams.stateRootProof,
                    storageProof: ownershipStorageProof,
                    accountProof: baseParams.accountProof
                })
            )
        );
    }

    function test_castVotes_PAST_PROOF() public {
        // Set up a new fork 5 minutes in the future from the one used in castVotes
        uint256 futureBlock = 19434588 + ((5 * 60) / 12); // Assuming 12-second block time
        _setUpWithForkBlock(futureBlock);

        // Get the current block timestamp
        uint256 currentTimestamp = block.timestamp;

        // Set up parameters for castVotes
        (
            address[] memory owners,
            uint256[][] memory tokenIds,
            bytes32[] memory recipientIds,
            uint32[] memory percentAllocations,

        ) = _setupTestParameters();

        // Set up base parameters with a timestamp more than 5 minutes in the past
        IStateProof.BaseParameters memory baseParams = _setupBaseParameters();
        baseParams.beaconOracleTimestamp = currentTimestamp - 6 minutes;

        (bytes[][][] memory ownershipStorageProofs, bytes[][] memory delegateStorageProofs) = _setupStorageProofs();

        // Expect the PAST_PROOF error
        vm.expectRevert(abi.encodeWithSignature("PAST_PROOF()"));

        // Attempt to cast votes with outdated proof
        flow.castVotes(
            owners,
            tokenIds,
            recipientIds,
            percentAllocations,
            baseParams,
            ownershipStorageProofs,
            delegateStorageProofs
        );

        // Verify that a more recent timestamp you can't just change the timestamp in the proof
        baseParams.beaconOracleTimestamp = currentTimestamp - 5 minutes;
        vm.expectRevert();
        flow.castVotes(
            owners,
            tokenIds,
            recipientIds,
            percentAllocations,
            baseParams,
            ownershipStorageProofs,
            delegateStorageProofs
        );
    }
}
