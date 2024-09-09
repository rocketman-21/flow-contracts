// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.26;

import { DeployScript } from "./DeployScript.s.sol";
import { NounsFlow } from "../src/NounsFlow.sol";
import { Flow } from "../src/Flow.sol";
import { IFlow } from "../src/interfaces/IFlow.sol";
import { FlowStorageV1 } from "../src/storage/FlowStorageV1.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployNounsFlow is DeployScript {
    address public nounsFlow;

    function deploy() internal override {
        address verifier = vm.envAddress("VERIFIER");
        address superToken = vm.envAddress("SUPER_TOKEN");
        address flowImpl = vm.envAddress("FLOW_IMPL");
        address manager = vm.envAddress("MANAGER");
        address parent = vm.envAddress("PARENT");
        uint256 tokenVoteWeight = vm.envUint("TOKEN_VOTE_WEIGHT");
        uint32 baselinePoolFlowRatePercent = uint32(vm.envUint("BASELINE_POOL_FLOW_RATE_PERCENT"));

        // Deploy NounsFlow implementation
        NounsFlow nounsFlowImpl = new NounsFlow();

        // Prepare initialization data
        bytes memory initData = abi.encodeWithSelector(
            NounsFlow.initialize.selector,
            verifier,
            superToken,
            flowImpl,
            manager,
            parent,
            IFlow.FlowParams({
                tokenVoteWeight: tokenVoteWeight,
                baselinePoolFlowRatePercent: baselinePoolFlowRatePercent
            }),
            FlowStorageV1.RecipientMetadata({
                title: "NounsFlow",
                description: "NounsFlow deployment",
                image: "ipfs://QmNounsFlowImageHash"
            })
        );

        // Deploy proxy with implementation and initialization data
        ERC1967Proxy proxy = new ERC1967Proxy(address(nounsFlowImpl), initData);

        // Set the deployed proxy address
        nounsFlow = address(proxy);
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(filePath, string(abi.encodePacked("NounsFlow: ", addressToString(nounsFlow))));
    }

    function getContractName() internal pure override returns (string memory) {
        return "NounsFlow";
    }
}
