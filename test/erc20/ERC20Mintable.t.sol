// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { ERC20VotesMintable } from "../../src/ERC20VotesMintable.sol";
import { IERC20VotesMintable } from "../../src/interfaces/IERC20VotesMintable.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { RewardPool } from "../../src/RewardPool.sol";
import { IRewardPool } from "../../src/interfaces/IRewardPool.sol";

import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import { SuperTokenV1Library } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import { PoolConfig } from "@superfluid-finance/ethereum-contracts/contracts/apps/SuperTokenV1Library.sol";
import { ERC1820RegistryCompiled } from "@superfluid-finance/ethereum-contracts/contracts/libs/ERC1820RegistryCompiled.sol";
import { SuperfluidFrameworkDeployer } from "@superfluid-finance/ethereum-contracts/contracts/utils/SuperfluidFrameworkDeployer.sol";
import { TestToken } from "@superfluid-finance/ethereum-contracts/contracts/utils/TestToken.sol";
import { SuperToken } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperToken.sol";

contract ERC20MintableTest is Test {
    SuperfluidFrameworkDeployer.Framework internal sf;
    SuperfluidFrameworkDeployer internal deployer;
    SuperToken internal superToken;

    ERC20VotesMintable public token;
    IRewardPool public rewardPool;

    address public tokenImpl;
    address public owner = address(0x1);
    address public minter = address(0x2);
    address public user = address(0x3);
    address public testUSDC;

    function setUp() public {
        // Deploy Superfluid framework
        vm.etch(ERC1820RegistryCompiled.at, ERC1820RegistryCompiled.bin);
        deployer = new SuperfluidFrameworkDeployer();
        deployer.deployTestFramework();
        sf = deployer.getFramework();

        // Deploy wrapper SuperToken
        (TestToken underlyingToken, SuperToken wrappedToken) = deployer.deployWrapperSuperToken(
            "Test USD Coin",
            "tUSDC",
            18,
            1e27,
            owner
        );

        superToken = wrappedToken;
        testUSDC = address(underlyingToken);

        // Deploy the implementation contract
        tokenImpl = address(new ERC20VotesMintable());

        // Deploy and initialize RewardPool
        address rewardPoolImpl = address(new RewardPool());
        address rewardPoolProxy = address(new ERC1967Proxy(rewardPoolImpl, ""));
        rewardPool = IRewardPool(rewardPoolProxy);

        // Deploy the proxy contract for ERC20VotesMintable
        address tokenProxy = address(new ERC1967Proxy(tokenImpl, ""));

        address flow = address(0x1); //todo update if needed

        // Initialize the RewardPool
        rewardPool.initialize(ISuperToken(address(superToken)), tokenProxy, flow);

        // Initialize the token
        vm.prank(owner);
        IERC20VotesMintable(tokenProxy).initialize(owner, minter, address(rewardPool), "Test Token", "TST");

        // Set the token variable to the proxy address
        token = ERC20VotesMintable(tokenProxy);
    }

    function testDecimals() public view {
        assertEq(token.decimals(), 18);
    }

    function testSetMinter() public {
        address newMinter = address(0x4);

        // Non-owner cannot set minter
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        token.setMinter(newMinter);

        // Owner can set minter
        vm.prank(owner);
        token.setMinter(newMinter);
        assertEq(token.minter(), newMinter);
    }

    function testLockMinter() public {
        // Non-owner cannot lock minter
        vm.prank(user);
        vm.expectRevert("Ownable: caller is not the owner");
        token.lockMinter();

        // Owner can lock minter
        vm.prank(owner);
        token.lockMinter();
        assertTrue(token.isMinterLocked());

        // Cannot set minter after locking
        vm.prank(owner);
        vm.expectRevert(IERC20VotesMintable.MINTER_LOCKED.selector);
        token.setMinter(address(0x5));
    }

    function testMint() public {
        uint256 mintAmount = 1000 * 10 ** 18;

        // Non-minter cannot mint
        vm.prank(user);
        vm.expectRevert(IERC20VotesMintable.NOT_MINTER.selector);
        token.mint(user, mintAmount);

        // Minter can mint
        vm.prank(minter);
        token.mint(user, mintAmount);
        assertEq(token.balanceOf(user), mintAmount);

        // Check total supply
        assertEq(token.totalSupply(), mintAmount);
    }

    function testTransfer() public {
        uint256 mintAmount = 1000 * 10 ** 18;
        uint256 transferAmount = 100 * 10 ** 18;

        // Mint tokens to user
        vm.prank(minter);
        token.mint(user, mintAmount);

        // Transfer tokens
        vm.prank(user);
        token.transfer(address(0x5), transferAmount);

        // Check balances
        assertEq(token.balanceOf(user), mintAmount - transferAmount);
        assertEq(token.balanceOf(address(0x5)), transferAmount);
    }

    function testDelegatesDefault() public {
        uint256 mintAmount = 1000 * 10 ** 18;

        // Mint tokens to user
        vm.prank(minter);
        token.mint(user, mintAmount);

        // Check that the user delegates to themselves by default
        assertEq(token.delegates(user), user);

        // Check voting power
        assertEq(token.getVotes(user), mintAmount);
    }

    function testDelegates() public {
        uint256 mintAmount = 1000 * 10 ** 18;
        address delegatee = address(0x123);

        // Mint tokens to user
        vm.prank(minter);
        token.mint(user, mintAmount);

        // User delegates to another address
        vm.prank(user);
        token.delegate(delegatee);

        // Check that the delegation was successful
        assertEq(token.delegates(user), delegatee);

        // Check voting power has been transferred
        assertEq(token.getVotes(user), 0);
        assertEq(token.getVotes(delegatee), mintAmount);

        // Attempt to delegate to zero address (should fail)
        vm.prank(user);
        vm.expectRevert("ERC20Votes: cannot delegate to zero address");
        token.delegate(address(0));

        // Ensure the delegation hasn't changed
        assertEq(token.delegates(user), delegatee);
    }
}
