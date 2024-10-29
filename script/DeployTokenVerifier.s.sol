// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.28;

import { DeployScript } from "./DeployScript.s.sol";
import { TokenVerifier } from "../src/state-proof/TokenVerifier.sol";

contract DeployTokenVerifier is DeployScript {
    address public tokenVerifier;

    function deploy() internal override {
        address tokenAddress = vm.envAddress("TOKEN_ADDRESS");

        // Deploy TokenVerifier
        TokenVerifier verifier = new TokenVerifier(tokenAddress);
        tokenVerifier = address(verifier);
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(filePath, string(abi.encodePacked("TokenVerifier: ", addressToString(tokenVerifier))));
    }

    function getContractName() internal pure override returns (string memory) {
        return "TokenVerifier";
    }
}
