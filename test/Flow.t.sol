// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import {Test} from "forge-std/Test.sol";

import {IFlow} from "../src/interfaces/IFlow.sol";
import {Flow} from "../src/Flow.sol";
import {MockERC721} from "./mocks/MockERC721.sol";

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

contract FlowTest is Test {
    SuperfluidFrameworkDeployer.Framework internal sf;
    SuperfluidFrameworkDeployer internal deployer;
    SuperToken internal superToken;

    Flow flow;
    address flowImpl;
    address testUSDC;
    IFlow.FlowParams flowParams;

    MockERC721 nounsToken;

    address manager = address(0x1998);

    FlowStorageV1.RecipientMetadata flowMetadata;
    FlowStorageV1.RecipientMetadata recipientMetadata;

    function deployFlow(address erc721, address superTokenAddress) internal returns (Flow) {
        address flowProxy = address(new ERC1967Proxy(flowImpl, ""));

        vm.prank(address(manager));
        IFlow(flowProxy).initialize({
            nounsToken: erc721,
            superToken: superTokenAddress,
            flowImpl: flowImpl,
            manager: manager, // Add this line
            parent: address(0),
            flowParams: flowParams,
            metadata: flowMetadata
        });

        _transferTestTokenToFlow(flowProxy);

        return Flow(flowProxy);
    }

    function _transferTestTokenToFlow(address flowAddress) internal {
        uint256 amount = 1e6 * 10**18; 
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

    function deployMock721(string memory name, string memory symbol) public virtual returns(MockERC721) {
        return new MockERC721(name, symbol);
    }

    function setUp() public virtual {
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

        nounsToken = deployMock721("Nouns", "NOUN");
        flowImpl = address(new Flow());

        flowParams = IFlow.FlowParams({
            tokenVoteWeight: 1e18 * 1000 // Example token vote weight
        });

        vm.etch(ERC1820RegistryCompiled.at, ERC1820RegistryCompiled.bin);

        deployer = new SuperfluidFrameworkDeployer();
        deployer.deployTestFramework();
        sf = deployer.getFramework();
        (TestToken underlyingToken, SuperToken token) =
            deployer.deployWrapperSuperToken("MR Token", "MRx", 18, 1e18 * 1e9, manager);

        superToken = token;
        testUSDC = address(underlyingToken);

        flow = deployFlow(address(nounsToken), address(superToken));
    }

}