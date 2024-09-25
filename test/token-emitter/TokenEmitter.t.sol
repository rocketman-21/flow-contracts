// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { TokenEmitter } from "../../src/TokenEmitter.sol";
import { ERC20VotesMintable } from "../../src/ERC20VotesMintable.sol";
import { ITokenEmitter } from "../../src/interfaces/ITokenEmitter.sol";
import { ProtocolRewards } from "../../src/protocol-rewards/ProtocolRewards.sol";
import { IWETH } from "../../src/interfaces/IWETH.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { RewardPool } from "../../src/RewardPool.sol";
import { BondingSCurve } from "../../src/bonding-curve/BondingSCurve.sol";
import { MockWETH } from "../mocks/MockWETH.sol";

import { ISuperToken } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol";
import { ERC1820RegistryCompiled } from "@superfluid-finance/ethereum-contracts/contracts/libs/ERC1820RegistryCompiled.sol";
import { SuperfluidFrameworkDeployer } from "@superfluid-finance/ethereum-contracts/contracts/utils/SuperfluidFrameworkDeployer.sol";
import { TestToken } from "@superfluid-finance/ethereum-contracts/contracts/utils/TestToken.sol";
import { SuperToken } from "@superfluid-finance/ethereum-contracts/contracts/superfluid/SuperToken.sol";

contract TokenEmitterTest is Test {
    // Superfluid
    SuperfluidFrameworkDeployer.Framework internal sf;
    SuperfluidFrameworkDeployer internal deployer;
    SuperToken internal superToken;
    TestToken internal underlyingToken;

    // Contracts
    TokenEmitter public tokenEmitter;
    ERC20VotesMintable public erc20;
    ProtocolRewards public protocolRewards;
    MockWETH public weth;
    RewardPool public rewardPool;

    // Addresses
    address public owner;
    address public user1;
    address public user2;
    address public protocolFeeRecipient;

    // Test Parameters
    int256 public constant CURVE_STEEPNESS = int256(1e18) / 100;
    int256 public constant BASE_PRICE = int256(1e18) / 3000;
    int256 public constant MAX_PRICE_INCREASE = int256(1e18) / 300;
    int256 public constant SUPPLY_OFFSET = int256(1e18) * 1000;

    function setUp() public {
        owner = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        protocolFeeRecipient = makeAddr("protocolFeeRecipient");

        // Setup Superfluid
        vm.etch(ERC1820RegistryCompiled.at, ERC1820RegistryCompiled.bin);
        deployer = new SuperfluidFrameworkDeployer();
        deployer.deployTestFramework();
        sf = deployer.getFramework();
        (underlyingToken, superToken) = deployer.deployWrapperSuperToken("Super Test Token", "STT", 18, 1e27, owner);

        // Deploy implementation contracts
        protocolRewards = new ProtocolRewards();
        TokenEmitter tokenEmitterImpl = new TokenEmitter(address(protocolRewards), protocolFeeRecipient);

        // Deploy RewardPool
        RewardPool rewardPoolImpl = new RewardPool();
        ERC1967Proxy rewardPoolProxy = new ERC1967Proxy(address(rewardPoolImpl), "");
        rewardPool = RewardPool(address(rewardPoolProxy));

        // Deploy ERC20 token
        ERC20VotesMintable erc20Impl = new ERC20VotesMintable();
        ERC1967Proxy erc20Proxy = new ERC1967Proxy(address(erc20Impl), "");
        erc20 = ERC20VotesMintable(address(erc20Proxy));

        // Deploy WETH mock
        weth = new MockWETH();

        // Deploy TokenEmitter proxy
        ERC1967Proxy proxy = new ERC1967Proxy(address(tokenEmitterImpl), "");
        tokenEmitter = TokenEmitter(address(proxy));

        // Initialize RewardPool
        rewardPool.initialize(ISuperToken(address(superToken)), address(erc20), address(tokenEmitter));

        // Initialize ERC20VotesMintable
        erc20.initialize(owner, address(tokenEmitter), address(rewardPool), "Test Token", "TST");

        // Initialize TokenEmitter
        tokenEmitter.initialize(
            owner,
            address(erc20),
            address(weth),
            CURVE_STEEPNESS,
            BASE_PRICE,
            MAX_PRICE_INCREASE,
            SUPPLY_OFFSET
        );

        // Set minter for ERC20
        erc20.setMinter(address(tokenEmitter));

        // Fund users with ETH
        vm.deal(user1, 100 ether);
        vm.deal(user2, 100 ether);
    }

    function testInitialization() public view {
        assertEq(address(tokenEmitter.erc20()), address(erc20), "ERC20 not set correctly");
        assertEq(address(tokenEmitter.WETH()), address(weth), "WETH not set correctly");
        assertEq(address(erc20.rewardPool()), address(rewardPool), "RewardPool not set correctly in ERC20");
        assertEq(address(rewardPool.superToken()), address(superToken), "SuperToken not set correctly in RewardPool");
        assertEq(rewardPool.manager(), address(erc20), "Manager not set correctly in RewardPool");
        assertEq(rewardPool.funder(), address(tokenEmitter), "Funder not set correctly in RewardPool");
        assertEq(tokenEmitter.curveSteepness(), CURVE_STEEPNESS, "Curve steepness not set correctly");
        assertEq(tokenEmitter.basePrice(), BASE_PRICE, "Base price not set correctly");
        assertEq(tokenEmitter.maxPriceIncrease(), MAX_PRICE_INCREASE, "Max price increase not set correctly");
        assertEq(tokenEmitter.supplyOffset(), SUPPLY_OFFSET);
    }

    function testBuyToken() public {
        uint256 amountToBuy = 500 * 1e18;
        address user = user1;

        // Start pranking as `user`
        vm.startPrank(user);

        // Get the quote for buying tokens
        int256 costInt = tokenEmitter.buyTokenQuoteWithRewards(amountToBuy);
        uint256 totalPayment = uint256(costInt);
        int256 costWithoutRewardsInt = tokenEmitter.buyTokenQuote(amountToBuy);
        uint256 costWithoutRewards = uint256(costWithoutRewardsInt);
        uint256 protocolRewardsFee = totalPayment - costWithoutRewards;

        // Set maxCost higher than totalPayment to allow for some slippage
        uint256 maxCost = totalPayment + 1 ether;

        // Record initial balances
        uint256 userInitialEthBalance = user.balance;
        uint256 contractInitialEthBalance = address(tokenEmitter).balance;
        uint256 userInitialTokenBalance = erc20.balanceOf(user);

        // Call buyToken
        ITokenEmitter.ProtocolRewardAddresses memory rewardAddresses = ITokenEmitter.ProtocolRewardAddresses({
            builder: address(0),
            purchaseReferral: address(0)
        });

        // Send excess ETH to test overpayment refund
        uint256 sentValue = totalPayment + 0.5 ether;

        vm.expectEmit(true, true, true, true);
        emit ITokenEmitter.TokensBought(user, user, amountToBuy, costWithoutRewards, protocolRewardsFee);

        tokenEmitter.buyToken{ value: sentValue }(user, amountToBuy, maxCost, rewardAddresses);

        // Stop pranking
        vm.stopPrank();

        // Check balances after purchase
        uint256 userFinalEthBalance = user.balance;
        uint256 contractFinalEthBalance = address(tokenEmitter).balance;
        uint256 userFinalTokenBalance = erc20.balanceOf(user);

        // User ETH balance should decrease by totalPayment
        assertEq(userInitialEthBalance - userFinalEthBalance, totalPayment, "Incorrect ETH deducted");

        // Contract ETH balance should increase by totalPayment (including rewards)
        assertEq(
            contractFinalEthBalance - contractInitialEthBalance,
            uint(costWithoutRewardsInt),
            "Incorrect ETH received by contract"
        );

        // User token balance should increase by amountToBuy
        assertEq(userFinalTokenBalance - userInitialTokenBalance, amountToBuy, "Incorrect tokens minted");

        // Overpayment should be refunded
        assertEq(
            sentValue - (userInitialEthBalance - userFinalEthBalance),
            sentValue - totalPayment,
            "Overpayment not refunded"
        );
    }

    function testSellToken() public {
        uint256 amountToSell = 300 * 1e18;
        address user = user1;

        // Mint tokens to user
        vm.prank(address(tokenEmitter));
        erc20.mint(user, amountToSell);

        // Fund the contract with ETH to simulate prior buys
        vm.deal(address(tokenEmitter), 100 ether);

        // Get the quote for selling tokens
        int256 paymentInt = tokenEmitter.sellTokenQuote(amountToSell);
        uint256 payment = uint256(paymentInt);

        // Set minPayment to a value less than or equal to payment
        uint256 minPayment = payment - 1 ether;

        // Record initial balances
        uint256 userInitialEthBalance = user.balance;
        uint256 contractInitialEthBalance = address(tokenEmitter).balance;
        uint256 userInitialTokenBalance = erc20.balanceOf(user);

        vm.startPrank(user);
        vm.expectEmit(true, true, true, true);
        emit ITokenEmitter.TokensSold(user, amountToSell, payment);

        // Call sellToken
        tokenEmitter.sellToken(amountToSell, minPayment);

        vm.stopPrank();

        // Check balances after sale
        uint256 userFinalEthBalance = user.balance;
        uint256 contractFinalEthBalance = address(tokenEmitter).balance;
        uint256 userFinalTokenBalance = erc20.balanceOf(user);

        // User ETH balance should increase by payment
        assertApproxEqAbs(userFinalEthBalance - userInitialEthBalance, payment, 1e14, "Incorrect ETH received");

        // Contract ETH balance should decrease by payment
        assertEq(contractInitialEthBalance - contractFinalEthBalance, payment, "Incorrect ETH deducted from contract");

        // User token balance should decrease by amountToSell
        assertEq(userInitialTokenBalance - userFinalTokenBalance, amountToSell, "Incorrect tokens burned");
    }

    function testBuyTokenSlippageProtection() public {
        uint256 amountToBuy = 1000 * 1e18;
        address user = user1;
        vm.prank(user);

        // Get the quote for buying tokens
        int256 costInt = tokenEmitter.buyTokenQuote(amountToBuy);
        uint256 cost = uint256(costInt);
        uint256 protocolRewardsFee = tokenEmitter.computeTotalReward(cost);

        uint256 totalPayment = cost + protocolRewardsFee;

        // Set maxCost less than required total payment to trigger slippage protection
        uint256 maxCost = totalPayment - 1 ether;

        // Prepare reward addresses
        ITokenEmitter.ProtocolRewardAddresses memory rewardAddresses = ITokenEmitter.ProtocolRewardAddresses({
            builder: address(0),
            purchaseReferral: address(0)
        });

        // Attempt to buy tokens with insufficient maxCost
        vm.expectRevert(ITokenEmitter.SLIPPAGE_EXCEEDED.selector);
        tokenEmitter.buyToken{ value: totalPayment }(user, amountToBuy, maxCost, rewardAddresses);
    }

    function testSellTokenSlippageProtection() public {
        uint256 amountToSell = 100 * 1e18;
        address user = user1;

        // Mint tokens to user
        vm.prank(address(tokenEmitter));
        erc20.mint(user, amountToSell);

        // Fund the contract with ETH to simulate prior buys
        vm.deal(address(tokenEmitter), 50 ether);

        // Get the quote for selling tokens
        int256 paymentInt = tokenEmitter.sellTokenQuote(amountToSell);
        uint256 payment = uint256(paymentInt);

        // Set minPayment higher than actual payment to trigger slippage protection
        uint256 minPayment = payment + 1 ether;

        vm.prank(user);
        vm.expectRevert(ITokenEmitter.SLIPPAGE_EXCEEDED.selector);
        tokenEmitter.sellToken(amountToSell, minPayment);
    }

    function testBuyTokenInsufficientFunds() public {
        uint256 amountToBuy = 200 * 1e18;
        address user = user1;
        vm.prank(user);

        // Get the quote for buying tokens
        int256 costInt = tokenEmitter.buyTokenQuote(amountToBuy);
        uint256 cost = uint256(costInt);
        uint256 protocolRewardsFee = tokenEmitter.computeTotalReward(cost);

        uint256 totalPayment = cost + protocolRewardsFee;

        // Prepare reward addresses
        ITokenEmitter.ProtocolRewardAddresses memory rewardAddresses = ITokenEmitter.ProtocolRewardAddresses({
            builder: address(0),
            purchaseReferral: address(0)
        });

        // Attempt to buy tokens by sending less ETH than required
        vm.expectRevert(ITokenEmitter.INSUFFICIENT_FUNDS.selector);
        tokenEmitter.buyToken{ value: totalPayment - 0.5 ether }(user, amountToBuy, totalPayment, rewardAddresses);
    }

    function testSellTokenInsufficientContractBalance() public {
        uint256 amountToSell = 100 * 1e18;
        address user = user1;

        // Mint tokens to user
        vm.prank(address(tokenEmitter));
        erc20.mint(user, amountToSell);

        // Ensure contract has no ETH
        vm.deal(address(tokenEmitter), 0);

        // Attempt to sell tokens
        vm.prank(user);
        vm.expectRevert(ITokenEmitter.INSUFFICIENT_CONTRACT_BALANCE.selector);
        tokenEmitter.sellToken(amountToSell, 0);
    }

    function testOnlyOwnerCanSetMinter() public {
        // Attempt to set minter from non-owner account
        vm.prank(user1);
        vm.expectRevert("Ownable: caller is not the owner");
        erc20.setMinter(user1);

        // Set minter from owner account
        erc20.setMinter(user1);
        assertEq(erc20.minter(), user1, "Minter not set correctly");
    }

    function testBuyTokenWithZeroAmount() public {
        // Attempt to buy zero tokens
        uint256 amountToBuy = 0;
        address user = user1;
        vm.prank(user);

        // Prepare reward addresses
        ITokenEmitter.ProtocolRewardAddresses memory rewardAddresses = ITokenEmitter.ProtocolRewardAddresses({
            builder: address(0),
            purchaseReferral: address(0)
        });
        // Expect revert with INVALID_AMOUNT error
        vm.expectRevert(BondingSCurve.INVALID_AMOUNT.selector);
        tokenEmitter.buyToken{ value: 0 }(user, amountToBuy, 0, rewardAddresses);

        // Verify that no tokens were minted
        assertEq(erc20.balanceOf(user), 0, "Tokens should not be minted");
    }

    function testSellTokenWithZeroAmount() public {
        // Attempt to sell zero tokens
        uint256 amountToSell = 0;
        address user = user1;

        vm.prank(user);
        // Expect revert with INVALID_AMOUNT error
        vm.expectRevert(BondingSCurve.INVALID_AMOUNT.selector);
        tokenEmitter.sellToken(amountToSell, 0);

        // Verify that no tokens were burned (balance remains zero)
        assertEq(erc20.balanceOf(user), 0, "Tokens should not be burned");
    }

    function testBuyTokenMaxAmount() public {
        uint256 amountToBuy = type(uint256).max / 1e18;
        address user = user1;
        vm.prank(user);

        // Get the quote for buying tokens
        vm.expectRevert();
        tokenEmitter.buyTokenQuote(amountToBuy);
        // Expect the function to revert due to overflow or invalid computation
    }

    function testSupplyOffsetEffect() public view {
        uint256 initialSupply = erc20.totalSupply();
        uint256 amountToBuy = 500 * 1e18;

        // Buy tokens to reach supply offset
        uint256 tokensToReachOffset = uint256(SUPPLY_OFFSET) - initialSupply;

        // Buy tokens before supply offset
        int256 costBeforeOffset = tokenEmitter.buyTokenQuote(tokensToReachOffset - amountToBuy);
        int256 costAtOffset = tokenEmitter.buyTokenQuote(tokensToReachOffset);

        // Assert that the cost increases as we approach the supply offset
        assertTrue(costAtOffset > costBeforeOffset, "Cost should increase approaching supply offset");
    }

    function testPriceContinuity() public view {
        uint256 steps = 100;
        uint256 maxAmount = 10000 * 1e18;

        int256 previousCost = 0;

        for (uint256 i = 1; i <= steps; i++) {
            uint256 amountToBuy = (maxAmount / steps) * i;
            int256 cost = tokenEmitter.buyTokenQuote(amountToBuy);

            // Ensure cost increases continuously
            assertTrue(cost > previousCost, "Cost should increase continuously");
            previousCost = cost;
        }
    }

    function testBuyTokenEventEmission() public {
        uint256 amountToBuy = 100 * 1e18;
        address user = user1;
        vm.startPrank(user);

        int256 costInt = tokenEmitter.buyTokenQuote(amountToBuy);
        uint256 cost = uint256(costInt);
        uint256 protocolRewardsFee = tokenEmitter.computeTotalReward(cost);
        uint256 totalPayment = cost + protocolRewardsFee;

        ITokenEmitter.ProtocolRewardAddresses memory rewardAddresses = ITokenEmitter.ProtocolRewardAddresses({
            builder: address(0),
            purchaseReferral: address(0)
        });

        // Expect the TokensBought event
        vm.expectEmit(true, true, true, true);
        emit ITokenEmitter.TokensBought(user, user, amountToBuy, cost, protocolRewardsFee);

        tokenEmitter.buyToken{ value: totalPayment }(user, amountToBuy, totalPayment, rewardAddresses);
    }
}
