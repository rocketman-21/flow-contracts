// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import { console2 } from "forge-std/console2.sol";
import { Script } from "forge-std/Script.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";

abstract contract DeployScript is Script {
    using Strings for uint256;

    uint256 public chainID;
    uint256 public deployerKey;
    address public deployerAddress;

    function setUp() public virtual {
        chainID = vm.envUint("CHAIN_ID");
        deployerKey = vm.envUint("PRIVATE_KEY");
        deployerAddress = vm.addr(deployerKey);
    }

    function run() public virtual {
        vm.startBroadcast(deployerAddress);

        deploy();

        vm.stopBroadcast();

        writeDeploymentDetailsToFile();
    }

    function deploy() internal virtual;

    function writeDeploymentDetailsToFile() internal virtual {
        string memory filePath = string(abi.encodePacked("deploys/", getContractName(), ".", chainID.toString(), ".txt"));
        vm.writeFile(filePath, "");
        writeAdditionalDeploymentDetails(filePath);
    }

    function writeAdditionalDeploymentDetails(string memory filePath) internal virtual;

    function getContractName() internal virtual returns (string memory);

    function addressToString(address _addr) internal pure returns (string memory) {
        bytes memory s = new bytes(40);
        for (uint256 i = 0; i < 20; i++) {
            bytes1 b = bytes1(uint8(uint256(uint160(_addr)) / (2 ** (8 * (19 - i)))));
            bytes1 hi = bytes1(uint8(b) / 16);
            bytes1 lo = bytes1(uint8(b) - 16 * uint8(hi));
            s[2 * i] = char(hi);
            s[2 * i + 1] = char(lo);
        }
        return string(abi.encodePacked("0x", string(s)));
    }

    function char(bytes1 b) internal pure returns (bytes1 c) {
        if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
        else return bytes1(uint8(b) + 0x57);
    }
}
