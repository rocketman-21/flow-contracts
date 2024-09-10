// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import { DeployScript } from "./DeployScript.s.sol";
import { NounsToken } from "../src/base/nouns-token/NounsToken.sol";
import { INounsDescriptorMinimal } from "../src/base/nouns-token/interfaces/INounsDescriptorMinimal.sol";
import { INounsSeeder } from "../src/base/nouns-token/interfaces/INounsSeeder.sol";
import { IProxyRegistry } from "../src/base/nouns-token/external/opensea/IProxyRegistry.sol";

contract DeployNounsToken is DeployScript {
    address public nounsToken;

    function deploy() internal override {
        address noundersDAO = vm.envAddress("NOUNDERS_DAO");
        address minter = vm.envAddress("MINTER");
        address descriptor = vm.envAddress("DESCRIPTOR");
        address seeder = vm.envAddress("SEEDER");
        address proxyRegistry = vm.envAddress("PROXY_REGISTRY");

        nounsToken = address(new NounsToken(
            noundersDAO,
            minter,
            INounsDescriptorMinimal(descriptor),
            INounsSeeder(seeder),
            IProxyRegistry(proxyRegistry)
        ));
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(filePath, string(abi.encodePacked("NounsToken: ", addressToString(nounsToken))));
    }

    function getContractName() internal pure override returns (string memory) {
        return "NounsToken";
    }
}
