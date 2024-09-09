// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.23;

import { console2 } from "forge-std/console2.sol";
import { Script } from "forge-std/Script.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { NounsToken } from "../src/base/nouns-token/NounsToken.sol";
import { INounsDescriptorMinimal } from "../src/base/nouns-token/interfaces/INounsDescriptorMinimal.sol";
import { INounsSeeder } from "../src/base/nouns-token/interfaces/INounsSeeder.sol";
import { IProxyRegistry } from "../src/base/nouns-token/external/opensea/IProxyRegistry.sol";

contract DeployNounsToken is Script {
    using Strings for uint256;

    address nounsToken;

    function run() public {
        uint256 chainID = vm.envUint("CHAIN_ID");
        uint256 key = vm.envUint("PRIVATE_KEY");
        address noundersDAO = vm.envAddress("NOUNDERS_DAO");
        address minter = vm.envAddress("MINTER");
        address descriptor = vm.envAddress("DESCRIPTOR");
        address seeder = vm.envAddress("SEEDER");
        address proxyRegistry = vm.envAddress("PROXY_REGISTRY");

        address deployerAddress = vm.addr(key);

        vm.startBroadcast(deployerAddress);

        nounsToken = address(new NounsToken(
            noundersDAO,
            minter,
            INounsDescriptorMinimal(descriptor),
            INounsSeeder(seeder),
            IProxyRegistry(proxyRegistry)
        ));

        vm.stopBroadcast();

        writeDeploymentDetailsToFile(chainID);
    }

    function writeDeploymentDetailsToFile(uint256 chainID) private {
        string memory filePath = string(abi.encodePacked("deploys/nounsToken.", chainID.toString(), ".txt"));

        vm.writeFile(filePath, "");
        vm.writeLine(filePath, string(abi.encodePacked("NounsToken: ", addressToString(nounsToken))));
    }

    function addressToString(address _addr) private pure returns (string memory) {
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

    function char(bytes1 b) private pure returns (bytes1 c) {
        if (uint8(b) < 10) return bytes1(uint8(b) + 0x30);
        else return bytes1(uint8(b) + 0x57);
    }
}
