// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { ERC20Mintable } from "../../src/ERC20Mintable.sol";
import { IERC20Mintable } from "../../src/interfaces/IERC20Mintable.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract ERC20MintableTest is Test {
    ERC20Mintable public token;
    address public tokenImpl;
    address public owner = address(0x1);
    address public minter = address(0x2);

    function setUp() public {
        // Deploy the implementation contract
        tokenImpl = address(new ERC20Mintable());

        // Deploy the proxy contract
        address tokenProxy = address(new ERC1967Proxy(tokenImpl, ""));

        // Initialize the token
        vm.prank(owner);
        IERC20Mintable(tokenProxy).initialize(owner, minter, "Test Token", "TST");

        // Set the token variable to the proxy address
        token = ERC20Mintable(tokenProxy);
    }

    function _mintTokens(address to, uint256 amount) internal {
        vm.prank(minter);
        token.mint(to, amount);
    }

    // Add your test functions here
}
