// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { FlowTCRTest } from "./FlowTCR.t.sol";
import { IArbitrator } from "../../src/tcr/interfaces/IArbitrator.sol";
import { IArbitrable } from "../../src/tcr/interfaces/IArbitrable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IGeneralizedTCR } from "../../src/tcr/interfaces/IGeneralizedTCR.sol";

contract TCRFundFlowTest is FlowTCRTest {
    // Helper function to get ERC20 balance of a contract or address
    function getERC20Balance(address _token, address _account) internal view returns (uint256) {
        return IERC20(_token).balanceOf(_account);
    }

    /**
     * @notice Test ERC20 transfer flow during item lifecycle where challenger wins
     * @dev This test covers the following steps:
     * 1. Submit an item
     * 2. Challenge the item
     * 3. Vote and execute the ruling in favor of the challenger
     * 4. Verify final balances
     */
    function testERC20TransfersDuringItemChallengerWinsLifecycle() public {
        uint256 arbitratorCost = arbitrator.arbitrationCost(bytes(""));

        // Record initial balances
        uint256[4] memory initialBalances = getRelevantBalances();

        // Submit an item
        bytes32 itemID = submitItem(ITEM_DATA, requester);

        // Verify balances after submission
        assertBalanceChange(requester, initialBalances[0], -int256(SUBMISSION_BASE_DEPOSIT + arbitratorCost));
        assertBalanceChange(address(flowTCR), initialBalances[2], int256(SUBMISSION_BASE_DEPOSIT + arbitratorCost));

        // Challenge the item
        challengeItem(itemID, challenger);

        // Verify balances after challenge
        assertBalanceChange(
            challenger,
            initialBalances[1],
            -int256(SUBMISSION_CHALLENGE_BASE_DEPOSIT + arbitratorCost)
        );
        assertBalanceChange(
            address(flowTCR),
            initialBalances[2],
            int256(SUBMISSION_BASE_DEPOSIT + SUBMISSION_CHALLENGE_BASE_DEPOSIT + arbitratorCost)
        );

        // Get dispute ID and execute voting in favor of the challenger
        (, uint256 disputeID, , , , , , , , ) = flowTCR.getRequestInfo(itemID, 0);
        voteAndExecute(disputeID, IArbitrable.Party.Challenger);

        // Verify final balances
        assertBalanceChange(requester, initialBalances[0], -int256(SUBMISSION_BASE_DEPOSIT + arbitratorCost));
        assertBalanceChange(challenger, initialBalances[1], int256(SUBMISSION_BASE_DEPOSIT));
        assertBalanceChange(address(flowTCR), initialBalances[2], 0);
        assertBalanceChange(address(arbitrator), initialBalances[3], int256(arbitratorCost));
    }

    /**
     * @notice Test ERC20 transfer flow during item lifecycle where requester wins
     * @dev This test covers the following steps:
     * 1. Submit an item
     * 2. Challenge the item
     * 3. Vote and execute the ruling in favor of the requester
     * 4. Verify final balances
     */
    function testERC20TransfersDuringItemRequesterWinsLifecycle() public {
        uint256 arbitratorCost = arbitrator.arbitrationCost(bytes(""));

        // Record initial balances
        uint256[4] memory initialBalances = getRelevantBalances();

        // Submit an item
        bytes32 itemID = submitItem(ITEM_DATA, requester);

        // Verify balances after submission
        assertBalanceChange(requester, initialBalances[0], -int256(SUBMISSION_BASE_DEPOSIT + arbitratorCost));
        assertBalanceChange(address(flowTCR), initialBalances[2], int256(SUBMISSION_BASE_DEPOSIT + arbitratorCost));

        // Challenge the item
        challengeItem(itemID, challenger);

        // Verify balances after challenge
        assertBalanceChange(
            challenger,
            initialBalances[1],
            -int256(SUBMISSION_CHALLENGE_BASE_DEPOSIT + arbitratorCost)
        );
        assertBalanceChange(
            address(flowTCR),
            initialBalances[2],
            int256(SUBMISSION_BASE_DEPOSIT + SUBMISSION_CHALLENGE_BASE_DEPOSIT + arbitratorCost)
        );

        // Get dispute ID and execute voting
        (, uint256 disputeID, , , , , , , , ) = flowTCR.getRequestInfo(itemID, 0);
        voteAndExecute(disputeID, IArbitrable.Party.Requester);

        // Verify final balances
        assertBalanceChange(requester, initialBalances[0], int256(SUBMISSION_CHALLENGE_BASE_DEPOSIT));
        assertBalanceChange(
            challenger,
            initialBalances[1],
            -int256(SUBMISSION_CHALLENGE_BASE_DEPOSIT + arbitratorCost)
        );
        assertBalanceChange(address(flowTCR), initialBalances[2], 0);
        assertBalanceChange(address(arbitrator), initialBalances[3], int256(arbitratorCost));
    }

    /**
     * @notice Get balances of relevant addresses
     * @return balances Array of balances in the order: requester, challenger, generalizedTCR, arbitrator
     */
    function getRelevantBalances() internal view returns (uint256[4] memory balances) {
        balances[0] = erc20Token.balanceOf(requester);
        balances[1] = erc20Token.balanceOf(challenger);
        balances[2] = erc20Token.balanceOf(address(flowTCR));
        balances[3] = erc20Token.balanceOf(address(arbitrator));
    }

    /**
     * @notice Assert the change in balance of an address
     * @param account The address to check
     * @param initialBalance The initial balance of the account
     * @param expectedChange The expected change in balance (can be negative)
     */
    function assertBalanceChange(address account, uint256 initialBalance, int256 expectedChange) internal view {
        int256 actualChange = int256(erc20Token.balanceOf(account)) - int256(initialBalance);
        assertEq(
            actualChange,
            expectedChange,
            string(abi.encodePacked("Unexpected balance change for ", Strings.toHexString(uint160(account), 20)))
        );
    }

    function testSuccessfulItemAdditionWithoutChallenge() public {
        // 1. Setup initial balances
        uint256[4] memory initialBalances = getRelevantBalances();
        uint256 arbitratorCost = arbitrator.arbitrationCost(bytes(""));

        // 2. Approve GeneralizedTCR to spend tokens
        vm.prank(requester);
        erc20Token.approve(address(flowTCR), SUBMISSION_BASE_DEPOSIT + arbitratorCost);

        // 4. Call addItem function
        bytes32 itemID = submitItem(ITEM_DATA, requester);

        // 5. Verify GeneralizedTCR balance increase
        assertEq(
            erc20Token.balanceOf(address(flowTCR)),
            initialBalances[2] + SUBMISSION_BASE_DEPOSIT + arbitratorCost,
            "GeneralizedTCR balance should increase by submission base deposit and arbitration cost"
        );

        // 6. Call executeRequest
        vm.warp(block.timestamp + flowTCR.challengePeriodDuration() + 1);
        flowTCR.executeRequest(itemID);

        // 7. Check requester's balance restoration
        assertEq(
            erc20Token.balanceOf(requester),
            initialBalances[0],
            "Requester balance should be restored after execution"
        );

        // 8. Ensure GeneralizedTCR balance decrease
        assertEq(
            erc20Token.balanceOf(address(flowTCR)),
            initialBalances[2],
            "GeneralizedTCR balance should return to initial state"
        );

        // 9. Verify no arbitrator costs deducted
        assertEq(
            erc20Token.balanceOf(address(arbitrator)),
            initialBalances[3],
            "Arbitrator balance should remain unchanged"
        );

        // 10. Assert final balances
        assertEq(
            erc20Token.balanceOf(requester),
            initialBalances[0],
            "Requester final balance should match initial balance"
        );
        assertEq(
            erc20Token.balanceOf(challenger),
            initialBalances[1],
            "Challenger final balance should remain unchanged"
        );
        assertEq(
            erc20Token.balanceOf(address(flowTCR)),
            initialBalances[2],
            "GeneralizedTCR final balance should match initial balance"
        );
        assertEq(
            erc20Token.balanceOf(address(arbitrator)),
            initialBalances[3],
            "Arbitrator final balance should remain unchanged"
        );
    }

    function testDisputeTieRefund() public {
        uint256[] memory initialBalances = new uint256[](4);
        initialBalances[0] = erc20Token.balanceOf(requester);
        initialBalances[1] = erc20Token.balanceOf(challenger);
        initialBalances[2] = erc20Token.balanceOf(address(flowTCR));
        initialBalances[3] = erc20Token.balanceOf(address(arbitrator));

        // Initial setup
        bytes32 itemID = submitItem(ITEM_DATA, requester);

        uint256 arbitratorCost = arbitrator.arbitrationCost(bytes(""));

        // Challenge the item
        challengeItem(itemID, challenger);

        // Get the dispute ID
        (, uint256 disputeID, , , , , , , , ) = flowTCR.getRequestInfo(itemID, 0);

        // Advance time to voting period
        advanceTime(VOTING_DELAY + 2);

        // Commit votes for a tie
        bytes32 requesterSecretHash = keccak256(abi.encode(uint256(1), "For registration", bytes32("salt")));
        vm.prank(requester);
        arbitrator.commitVote(disputeID, requesterSecretHash);

        bytes32 challengerSecretHash = keccak256(abi.encode(uint256(2), "Against registration", bytes32("salt2")));
        vm.prank(challenger);
        arbitrator.commitVote(disputeID, challengerSecretHash);

        // Advance time to reveal period
        advanceTime(VOTING_PERIOD);

        // Reveal votes
        vm.prank(requester);
        arbitrator.revealVote(disputeID, 1, "For registration", bytes32("salt"));

        vm.prank(challenger);
        arbitrator.revealVote(disputeID, 2, "Against registration", bytes32("salt2"));

        // Advance time to end of reveal and appeal periods
        advanceTime(REVEAL_PERIOD + APPEAL_PERIOD);

        // Execute the ruling
        arbitrator.executeRuling(disputeID);

        // Check if both parties got their deposits back
        assertEq(
            erc20Token.balanceOf(requester),
            initialBalances[0] - arbitratorCost / 2,
            "Requester should get their deposit back minus half of the arbitration cost"
        );
        assertEq(
            erc20Token.balanceOf(challenger),
            initialBalances[1] - arbitratorCost / 2,
            "Challenger should get their deposit back minus half of the arbitration cost"
        );

        assertEq(
            erc20Token.balanceOf(address(flowTCR)),
            initialBalances[2],
            "GeneralizedTCR balance should remain unchanged"
        );

        // Verify arbitrator received payment
        assertEq(
            erc20Token.balanceOf(address(arbitrator)),
            initialBalances[3] + arbitratorCost,
            "Arbitrator should receive payment"
        );

        // Verify the item status
        (, IGeneralizedTCR.Status status, ) = flowTCR.getItemInfo(itemID);
        assertEq(uint256(status), uint256(IGeneralizedTCR.Status.Absent), "Item should remain absent after a tie");
    }
}
