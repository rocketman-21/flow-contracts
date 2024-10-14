// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import { DeployScript } from "./DeployScript.s.sol";
import { BulkPoolWithdraw } from "../src/macros/BulkPoolWithdraw.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract DeployMacros is DeployScript {
    address public bulkPoolWithdraw;
    address public bulkPoolWithdrawImplementation;

    function deploy() internal override {
        address initialOwner = vm.envAddress("INITIAL_OWNER");

        // Deploy BulkPoolWithdraw implementation
        BulkPoolWithdraw bulkPoolWithdrawImpl = new BulkPoolWithdraw();
        bulkPoolWithdrawImplementation = address(bulkPoolWithdrawImpl);
        bulkPoolWithdraw = address(new ERC1967Proxy(address(bulkPoolWithdrawImpl), ""));

        // Initialize BulkPoolWithdraw
        BulkPoolWithdraw(bulkPoolWithdraw).initialize(initialOwner);
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal override {
        vm.writeLine(
            filePath,
            string(abi.encodePacked("BulkPoolWithdrawImpl: ", addressToString(bulkPoolWithdrawImplementation)))
        );
        vm.writeLine(filePath, string(abi.encodePacked("BulkPoolWithdraw: ", addressToString(bulkPoolWithdraw))));
    }

    function getContractName() internal pure override returns (string memory) {
        return "BulkPoolWithdraw";
    }
}
