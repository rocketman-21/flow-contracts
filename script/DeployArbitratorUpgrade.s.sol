// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { DeployScript } from "./DeployScript.s.sol";
import { ERC20VotesArbitrator } from "../src/tcr/ERC20VotesArbitrator.sol";

contract DeployArbitratorUpgrade is DeployScript {
    address public arbitratorImplementation;

    function deploy() internal override {
        // Deploy new ERC20VotesArbitrator implementation
        ERC20VotesArbitrator arbitratorImpl = new ERC20VotesArbitrator();
        arbitratorImplementation = address(arbitratorImpl);
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(
            filePath,
            string(abi.encodePacked("New ArbitratorImpl: ", addressToString(arbitratorImplementation)))
        );
    }

    function getContractName() internal pure override returns (string memory) {
        return "ERC20VotesArbitrator.Upgrade";
    }
}
