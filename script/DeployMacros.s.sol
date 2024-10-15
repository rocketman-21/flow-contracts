// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import { DeployScript } from "./DeployScript.s.sol";
import { BulkPoolWithdraw } from "../src/macros/BulkPoolWithdraw.sol";

contract DeployMacros is DeployScript {
    address public bulkPoolWithdraw;

    function deploy() internal override {
        bulkPoolWithdraw = address(new BulkPoolWithdraw());
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(filePath, string(abi.encodePacked("BulkPoolWithdraw: ", addressToString(bulkPoolWithdraw))));
    }

    function getContractName() internal pure override returns (string memory) {
        return "BulkPoolWithdraw";
    }
}
