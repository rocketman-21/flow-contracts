// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { GeneralizedTCRTest } from "./GeneralizedTCR.t.sol";
import { IArbitrator } from "../../src/tcr/interfaces/IArbitrator.sol";
import { IArbitrable } from "../../src/tcr/interfaces/IArbitrable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract FundFlowTest is GeneralizedTCRTest {
    // Helper function to get ERC20 balance of a contract or address
    function getERC20Balance(address _token, address _account) internal view returns (uint256) {
        return IERC20(_token).balanceOf(_account);
    }

    // Test ERC20 transfer flow during item lifecycle
    function testERC20TransfersDuringItemLifecycle() public {
        uint arbitratorCost = arbitrator.arbitrationCost(bytes(""));
        // Initial balances
        uint256 initialRequesterBalance = erc20Token.balanceOf(requester);
        uint256 initialChallengerBalance = erc20Token.balanceOf(challenger);
        uint256 initialGeneralizedTCRBalance = erc20Token.balanceOf(address(generalizedTCR));
        uint256 initialArbitratorBalance = erc20Token.balanceOf(address(arbitrator));

        // Submit an item
        bytes32 itemID = submitItem(ITEM_DATA, requester);

        // After submission, requester should have decreased by SUBMISSION_BASE_DEPOSIT
        assertEq(
            erc20Token.balanceOf(requester),
            initialRequesterBalance - SUBMISSION_BASE_DEPOSIT - arbitratorCost,
            "Requester balance should decrease by submission base deposit"
        );
        // GeneralizedTCR should have increased by SUBMISSION_BASE_DEPOSIT
        assertEq(
            erc20Token.balanceOf(address(generalizedTCR)),
            initialGeneralizedTCRBalance + SUBMISSION_BASE_DEPOSIT + arbitratorCost,
            "GeneralizedTCR balance should increase by submission base deposit"
        );

        // Challenge the item
        challengeItem(itemID, challenger);

        // Check state after challenge
        (, uint256 disputeID, , , , , , , , ) = generalizedTCR.getRequestInfo(itemID, 0);

        // After challenge, challenger should have decreased by SUBMISSION_CHALLENGE_BASE_DEPOSIT
        assertEq(
            erc20Token.balanceOf(challenger),
            initialChallengerBalance - SUBMISSION_CHALLENGE_BASE_DEPOSIT - arbitratorCost,
            "Challenger balance should decrease by challenge base deposit"
        );
        // GeneralizedTCR should have increased by SUBMISSION_CHALLENGE_BASE_DEPOSIT
        assertEq(
            erc20Token.balanceOf(address(generalizedTCR)),
            initialGeneralizedTCRBalance + SUBMISSION_BASE_DEPOSIT + SUBMISSION_CHALLENGE_BASE_DEPOSIT + arbitratorCost, // arbitratorCost is spent by arbitrator
            "GeneralizedTCR balance should increase by submission and challenge base deposits"
        );

        voteAndExecute(disputeID);

        // After execution, deposits should be returned to requester
        assertEq(
            erc20Token.balanceOf(requester),
            initialRequesterBalance + SUBMISSION_CHALLENGE_BASE_DEPOSIT,
            "Requester balance should be restored after execution"
        );
        // GeneralizedTCR should have refunded the deposit
        assertEq(
            erc20Token.balanceOf(address(generalizedTCR)),
            initialGeneralizedTCRBalance,
            "GeneralizedTCR balance should have only challenge deposit remaining"
        );

        // Final balances
        uint256 finalRequesterBalance = erc20Token.balanceOf(requester);
        uint256 finalChallengerBalance = erc20Token.balanceOf(challenger);
        uint256 finalGeneralizedTCRBalance = erc20Token.balanceOf(address(generalizedTCR));
        uint256 finalArbitratorBalance = erc20Token.balanceOf(address(arbitrator));

        // Assertions to ensure no unexpected transfers
        assertEq(
            finalRequesterBalance,
            initialRequesterBalance + SUBMISSION_CHALLENGE_BASE_DEPOSIT,
            "Requester balance should gain the challenge deposit after refund"
        );
        assertEq(
            finalChallengerBalance,
            initialChallengerBalance - SUBMISSION_CHALLENGE_BASE_DEPOSIT - arbitratorCost,
            "Challenger balance should lose the challenge deposit and arbitration cost after execution"
        );
        assertEq(
            finalGeneralizedTCRBalance,
            initialGeneralizedTCRBalance,
            "GeneralizedTCR should not hold anything after execution"
        );
        assertEq(
            finalArbitratorBalance,
            initialArbitratorBalance + arbitratorCost,
            "Arbitrator balance should gain the arbitration cost"
        );
    }

    function testSuccessfulItemAdditionWithoutChallenge() public {
        // 1. Setup initial balances
        uint256 initialRequesterBalance = erc20Token.balanceOf(requester);
        uint256 initialChallengerBalance = erc20Token.balanceOf(challenger);
        uint256 initialGeneralizedTCRBalance = erc20Token.balanceOf(address(generalizedTCR));
        uint256 initialArbitratorBalance = erc20Token.balanceOf(address(arbitrator));
        uint256 arbitratorCost = arbitrator.arbitrationCost(bytes(""));

        // 2. Approve GeneralizedTCR to spend tokens
        vm.prank(requester);
        erc20Token.approve(address(generalizedTCR), SUBMISSION_BASE_DEPOSIT + arbitratorCost);

        // 3. Record initial balances
        uint256 requesterBalanceBefore = erc20Token.balanceOf(requester);
        uint256 generalizedTCRBalanceBefore = erc20Token.balanceOf(address(generalizedTCR));
        uint256 arbitratorBalanceBefore = erc20Token.balanceOf(address(arbitrator));

        // 4. Call addItem function
        bytes32 itemID = submitItem(ITEM_DATA, requester);

        // 5. Verify GeneralizedTCR balance increase
        assertEq(
            erc20Token.balanceOf(address(generalizedTCR)),
            generalizedTCRBalanceBefore + SUBMISSION_BASE_DEPOSIT + arbitratorCost,
            "GeneralizedTCR balance should increase by submission base deposit and arbitration cost"
        );

        // 6. Call executeRequest
        vm.warp(block.timestamp + generalizedTCR.challengePeriodDuration() + 1);
        generalizedTCR.executeRequest(itemID);

        // 7. Check requester's balance restoration
        assertEq(
            erc20Token.balanceOf(requester),
            requesterBalanceBefore,
            "Requester balance should be restored after execution"
        );

        // 8. Ensure GeneralizedTCR balance decrease
        assertEq(
            erc20Token.balanceOf(address(generalizedTCR)),
            generalizedTCRBalanceBefore,
            "GeneralizedTCR balance should return to initial state"
        );

        // 9. Verify no arbitrator costs deducted
        assertEq(
            erc20Token.balanceOf(address(arbitrator)),
            arbitratorBalanceBefore,
            "Arbitrator balance should remain unchanged"
        );

        // 10. Assert final balances
        assertEq(
            erc20Token.balanceOf(requester),
            initialRequesterBalance,
            "Requester final balance should match initial balance"
        );
        assertEq(
            erc20Token.balanceOf(challenger),
            initialChallengerBalance,
            "Challenger final balance should remain unchanged"
        );
        assertEq(
            erc20Token.balanceOf(address(generalizedTCR)),
            initialGeneralizedTCRBalance,
            "GeneralizedTCR final balance should match initial balance"
        );
        assertEq(
            erc20Token.balanceOf(address(arbitrator)),
            initialArbitratorBalance,
            "Arbitrator final balance should remain unchanged"
        );
    }
}
