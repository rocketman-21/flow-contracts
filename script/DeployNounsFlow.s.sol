// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { DeployScript } from "./DeployScript.s.sol";
import { NounsFlow } from "../src/NounsFlow.sol";
import { Flow } from "../src/Flow.sol";
import { IFlow } from "../src/interfaces/IFlow.sol";
import { FlowStorageV1 } from "../src/storage/FlowStorageV1.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { TokenVerifier } from "../src/state-proof/TokenVerifier.sol";

contract DeployNounsFlow is DeployScript {
    address public nounsFlow;
    address public tokenVerifier;
    address public nounsFlowImplementation;

    function deploy() internal override {
        // Deploy NounsFlow implementation
        NounsFlow nounsFlowImpl = new NounsFlow();
        nounsFlowImplementation = address(nounsFlowImpl);

        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");
        address superToken = vm.envAddress("SUPER_TOKEN");
        address manager = vm.envAddress("MANAGER");
        address parent = vm.envAddress("PARENT");
        uint256 tokenVoteWeight = vm.envUint("TOKEN_VOTE_WEIGHT");
        uint32 baselinePoolFlowRatePercent = uint32(vm.envUint("BASELINE_POOL_FLOW_RATE_PERCENT"));

        // Deploy TokenVerifier
        TokenVerifier verifier = new TokenVerifier(tokenAddress);
        tokenVerifier = address(verifier);

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            NounsFlow.initialize.selector,
            tokenVerifier,
            superToken,
            address(nounsFlowImpl),
            manager,
            parent,
            IFlow.FlowParams({
                tokenVoteWeight: tokenVoteWeight,
                baselinePoolFlowRatePercent: baselinePoolFlowRatePercent
            }),
            FlowStorageV1.RecipientMetadata({
                title: "NounsFlow",
                description: "NounsFlow deployment",
                image: "ipfs://QmNounsFlowImageHash",
                tagline: "Nouns Flow Tagline",
                url: "https://nounsflow.example.com"
            })
        );

        // Deploy proxy with implementation and initialization data
        ERC1967Proxy proxy = new ERC1967Proxy(address(nounsFlowImpl), initData);

        // Set the deployed proxy address
        nounsFlow = address(proxy);
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(filePath, string(abi.encodePacked("NounsFlowImpl: ", addressToString(nounsFlowImplementation))));
        vm.writeLine(filePath, string(abi.encodePacked("TokenVerifier: ", addressToString(tokenVerifier))));
        vm.writeLine(filePath, string(abi.encodePacked("NounsFlowProxy: ", addressToString(nounsFlow))));
    }

    function getContractName() internal pure override returns (string memory) {
        return "NounsFlow";
    }
}
