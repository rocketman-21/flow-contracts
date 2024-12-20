// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

import { DeployScript } from "./DeployScript.s.sol";
import { ProtocolRewards } from "../src/protocol-rewards/ProtocolRewards.sol";

contract DeployProtocolRewards is DeployScript {
    address private _protocolRewards;

    function deploy() internal override {
        _protocolRewards = address(new ProtocolRewards());
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(filePath, string(abi.encodePacked("ProtocolRewards: ", addressToString(_protocolRewards))));
    }

    function getContractName() internal pure override returns (string memory) {
        return "ProtocolRewards";
    }
}
