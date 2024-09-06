// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";
import "forge-std/StdJson.sol";

import {IFlow, INounsFlow} from "../src/interfaces/IFlow.sol";
import {NounsFlow} from "../src/NounsFlow.sol";
import {L2NounsVerifier} from "../src/state-proof/L2NounsVerifier.sol";
import {IStateProof} from "../src/interfaces/IStateProof.sol";

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

import {ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import {SuperTokenV1Library} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import {PoolConfig} from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import {ERC1820RegistryCompiled} from
    "@superfluid-finance/ethereum-contracts/contracts/libs/ERC1820RegistryCompiled.sol";
import {SuperfluidFrameworkDeployer} from
    "@superfluid-finance/ethereum-contracts/contracts/utils/SuperfluidFrameworkDeployer.sol";
import {TestToken} from "@superfluid-finance/ethereum-contracts/contracts/utils/TestToken.sol";
import {SuperToken} from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperToken.sol";
import {FlowStorageV1} from "../src/storage/FlowStorageV1.sol";

contract NounsFlowTest is Test {

    using stdJson for string;

    SuperfluidFrameworkDeployer.Framework internal sf;
    SuperfluidFrameworkDeployer internal deployer;
    SuperToken internal superToken;

    NounsFlow flow;
    address flowImpl;
    address testUSDC;
    IFlow.FlowParams flowParams;

    L2NounsVerifier verifier;

    address manager = address(0x1998);

    FlowStorageV1.RecipientMetadata flowMetadata;
    FlowStorageV1.RecipientMetadata recipientMetadata;

    function deployFlow(address verifierAddress, address superTokenAddress) internal returns (NounsFlow) {
        address flowProxy = address(new ERC1967Proxy(flowImpl, ""));

        vm.prank(address(manager));
        INounsFlow(flowProxy).initialize({
            verifier: verifierAddress,
            superToken: superTokenAddress,
            flowImpl: flowImpl,
            manager: manager,
            parent: address(0),
            flowParams: flowParams,
            metadata: flowMetadata
        });

        _transferTestTokenToFlow(flowProxy, 10_000 * 10**18); //10k usdc a month to start

        // set small flow rate 
        vm.prank(manager);
        IFlow(flowProxy).setFlowRate(385 * 10**13); // 0.00385 tokens per second

        return NounsFlow(flowProxy);
    }

    function _transferTestTokenToFlow(address flowAddress, uint256 amount) internal {
        vm.startPrank(manager);
        
        // Mint underlying tokens
        TestToken(testUSDC).mint(manager, amount);
        
        // Approve SuperToken to spend underlying tokens
        TestToken(testUSDC).approve(address(superToken), amount);
        
        // Upgrade (wrap) the tokens
        ISuperToken(address(superToken)).upgrade(amount);
        
        // Transfer the wrapped tokens to the Flow contract
        ISuperToken(address(superToken)).transfer(flowAddress, amount);
        
        vm.stopPrank();
    }

    function _setUpWithForkBlock(uint256 blockNumber) public virtual {
        vm.createSelectFork("https://mainnet.base.org", blockNumber);
        flowMetadata = FlowStorageV1.RecipientMetadata({
            title: "Test Flow",
            description: "A test flow",
            image: "ipfs://image"
        });

        recipientMetadata = FlowStorageV1.RecipientMetadata({
            title: "Test Recipient",
            description: "A test recipient",
            image: "ipfs://image"
        });

        verifier = new L2NounsVerifier();
        flowImpl = address(new NounsFlow());

        flowParams = IFlow.FlowParams({
            tokenVoteWeight: 1e18 * 1000, // Example token vote weight
            baselinePoolFlowRatePercent: 1000 // 1000 BPS
        });

        vm.etch(ERC1820RegistryCompiled.at, ERC1820RegistryCompiled.bin);

        deployer = new SuperfluidFrameworkDeployer();
        deployer.deployTestFramework();
        sf = deployer.getFramework();
        (TestToken underlyingToken, SuperToken token) =
            deployer.deployWrapperSuperToken("MR Token", "MRx", 18, 1e18 * 1e9, manager);

        superToken = token;
        testUSDC = address(underlyingToken);

        flow = deployFlow(address(verifier), address(superToken));
    }

    function _setupBaseParameters() internal returns (IStateProof.BaseParameters memory) {
        string memory rootPath = vm.projectRoot();
        string memory proofPath = string.concat(rootPath, "/test/proof-data/papercliplabs.json");
        string memory json = vm.readFile(proofPath);

        return IStateProof.BaseParameters({
            beaconRoot: json.readBytes32(".beaconRoot"),
            beaconOracleTimestamp: uint256(json.readBytes32(".beaconOracleTimestamp")),
            executionStateRoot: json.readBytes32(".executionStateRoot"),
            stateRootProof: abi.decode(json.parseRaw(".stateRootProof"), (bytes32[])),
            accountProof: abi.decode(json.parseRaw(".accountProof"), (bytes[]))
        });
    }

    function _setupStorageProofs() internal returns (bytes[][][] memory, bytes[][] memory) {
        string memory rootPath = vm.projectRoot();
        string memory proofPath = string.concat(rootPath, "/test/proof-data/papercliplabs.json");
        string memory json = vm.readFile(proofPath);

        bytes[][][] memory ownershipStorageProofs = new bytes[][][](1);
        ownershipStorageProofs[0] = new bytes[][](1);
        ownershipStorageProofs[0][0] = abi.decode(json.parseRaw(".ownershipStorageProof1"), (bytes[]));

        bytes[][] memory delegateStorageProofs = abi.decode(json.parseRaw(".delegateStorageProofs"), (bytes[][]));

        return (ownershipStorageProofs, delegateStorageProofs);
    }

    function _setupTestParameters() internal returns (
        address[] memory,
        uint256[][] memory,
        uint256[] memory,
        uint32[] memory,
        address
    ) {
        address recipient1 = address(0x1);
        address recipient2 = address(0x2);

        address[] memory owners = new address[](1);
        owners[0] = 0xA2b6590A6dC916fe317Dcab169a18a5B87A5c3d5; // safe
        address delegate = 0x65599970Af18EeA5f4ec0B82f23B018fd15EBd11; // delegate

        uint256[][] memory tokenIds = new uint256[][](1);
        tokenIds[0] = new uint256[](1);
        tokenIds[0][0] = 788;

        uint256[] memory recipientIds = new uint256[](2);
        recipientIds[0] = 0;
        recipientIds[1] = 1;

        vm.startPrank(manager);
        flow.addRecipient(recipient1, recipientMetadata);
        flow.addRecipient(recipient2, recipientMetadata);
        vm.stopPrank();

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
            uint256[] memory recipientIds,
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
        (,bytes[][] memory delegateStorageProofs) = _setupStorageProofs();

        assertTrue(verifier.isDelegate(delegator, delegate, IStateProof.Parameters({
            beaconRoot: baseParams.beaconRoot,
            beaconOracleTimestamp: baseParams.beaconOracleTimestamp,
            executionStateRoot: baseParams.executionStateRoot,
            stateRootProof: baseParams.stateRootProof,
            storageProof: delegateStorageProofs[0],
            accountProof: baseParams.accountProof
        })));
    }

    function test__isOwner788() public {
        _setUpWithForkBlock(19434588);

        uint256 tokenId = 788;
        address owner = 0xA2b6590A6dC916fe317Dcab169a18a5B87A5c3d5;

        IStateProof.BaseParameters memory baseParams = _setupBaseParameters();
        (bytes[][][] memory ownershipStorageProofs,) = _setupStorageProofs();

        assertTrue(verifier.isOwner(tokenId, owner, IStateProof.Parameters({
            beaconRoot: baseParams.beaconRoot,
            beaconOracleTimestamp: baseParams.beaconOracleTimestamp,
            executionStateRoot: baseParams.executionStateRoot,
            stateRootProof: baseParams.stateRootProof,
            storageProof: ownershipStorageProofs[0][0],
            accountProof: baseParams.accountProof
        })));

        // try to mess with timestamp and make a past proof for the future
        baseParams.beaconOracleTimestamp += 1;
        vm.expectRevert();
        verifier.isOwner(tokenId, owner, IStateProof.Parameters({
            beaconRoot: baseParams.beaconRoot,
            beaconOracleTimestamp: baseParams.beaconOracleTimestamp,
            executionStateRoot: baseParams.executionStateRoot,
            stateRootProof: baseParams.stateRootProof,
            storageProof: ownershipStorageProofs[0][0],
            accountProof: baseParams.accountProof
        }));
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

        assertTrue(verifier.isOwner(tokenId, owner, IStateProof.Parameters({
            beaconRoot: baseParams.beaconRoot,
            beaconOracleTimestamp: baseParams.beaconOracleTimestamp,
            executionStateRoot: baseParams.executionStateRoot,
            stateRootProof: baseParams.stateRootProof,
            storageProof: ownershipStorageProof,
            accountProof: baseParams.accountProof
        })));
    }

    function test_castVotes_PAST_PROOF() public {
        // Set up a new fork 5 minutes in the future from the one used in castVotes
        uint256 futureBlock = 19434588 + (5 * 60 / 12); // Assuming 12-second block time
        _setUpWithForkBlock(futureBlock);

        // Get the current block timestamp
        uint256 currentTimestamp = block.timestamp;

        // Set up parameters for castVotes
        (address[] memory owners, uint256[][] memory tokenIds, uint256[] memory recipientIds, uint32[] memory percentAllocations, address delegate) = _setupTestParameters();

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
}