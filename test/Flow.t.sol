// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {IFlow} from "../src/interfaces/IFlow.sol";
import {Flow} from "../src/Flow.sol";

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

contract FlowTest is Test {
    SuperfluidFrameworkDeployer.Framework internal sf;
    SuperfluidFrameworkDeployer internal deployer;
    SuperToken internal superToken;

    address flow;
    address flowImpl;

    address erc721Votes;

    address manager = address(0x1998);

    function setUp() public virtual {
        flowImpl = address(new Flow());
        flow = address(new ERC1967Proxy(flowImpl, ""));

        flow = address(new ERC1967Proxy(flowImpl, ""));
        address votingPowerAddress = address(0x1);
        address initialOwner = address(this); // This contract is the initial owner

        IFlow.FlowParams memory params = IFlow.FlowParams({
            tokenVoteWeight: 1e18, // Example token vote weight
            quorumVotesBPS: 5000, // Example quorum votes in basis points (50%)
            minVotingPowerToVote: 1e18, // Minimum voting power required to vote
            minVotingPowerToCreate: 100 * 1e18 // Minimum voting power required to create a grant
        });

        vm.etch(ERC1820RegistryCompiled.at, ERC1820RegistryCompiled.bin);

        deployer = new SuperfluidFrameworkDeployer();
        deployer.deployTestFramework();
        sf = deployer.getFramework();
        (TestToken underlyingToken, SuperToken token) =
            deployer.deployWrapperSuperToken("MR Token", "MRx", 18, 10000000, manager);

        superToken = token;

        vm.prank(address(manager));
        IFlow(flow).initialize({
            nounsToken: votingPowerAddress,
            superToken: address(superToken),
            flowImpl: flowImpl,
            flowParams: params
        });
    }

    function test_initialize() public {
        assertEq(address(Flow(flow).erc721Votes()), address(0x1));
        assertEq(Flow(flow).minVotingPowerToVote(), 1e18);
        assertEq(Flow(flow).minVotingPowerToCreate(), 100 * 1e18);
        assertEq(Flow(flow).quorumVotesBPS(), 5000);
        assertEq(Flow(flow).tokenVoteWeight(), 1e18);
    }
}
