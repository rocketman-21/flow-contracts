// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { GeneralizedTCRTest } from "./GeneralizedTCR.t.sol";
import { IGeneralizedTCR } from "../../src/tcr/interfaces/IGeneralizedTCR.sol";
import { IArbitrable } from "../../src/tcr/interfaces/IArbitrable.sol";
import { IArbitrator } from "../../src/tcr/interfaces/IArbitrator.sol";

contract BasicTCRTest is GeneralizedTCRTest {
    // Test Cases

    /**
     * @dev Tests the submission of an item to the TCR
     * @notice This test performs the following steps:
     * 1. Submits an item to the TCR
     * 2. Retrieves the item information
     * 3. Verifies that the item data matches the submitted data
     * 4. Checks that the item status is set to RegistrationRequested
     * 5. Ensures that the number of requests for the item is 1
     */
    function testItemSubmission() public {
        bytes32 itemID = submitItem(ITEM_DATA, requester);

        (bytes memory data, IGeneralizedTCR.Status status, uint256 numberOfRequests) = generalizedTCR.getItemInfo(
            itemID
        );

        assertEq(data, ITEM_DATA);
        assertEq(uint256(status), uint256(IGeneralizedTCR.Status.RegistrationRequested));
        assertEq(numberOfRequests, 1);
    }

    /**
     * @dev Tests the challenging of an item in the TCR
     * @notice This test performs the following steps:
     * 1. Submits an item to the TCR
     * 2. Challenges the submitted item
     * 3. Retrieves the request information
     * 4. Verifies various aspects of the challenge, including:
     *    - The item is marked as disputed
     *    - The requester and challenger addresses are correct
     *    - The number of rounds is 1
     *    - The request is not yet resolved
     *    - The arbitrator address is correct
     *    - The arbitrator extra data is correct
     *    - The meta evidence ID is 0
     * 5. Retrieves the item information again
     * 6. Verifies that the item status is still RegistrationRequested
     * 7. Ensures that the number of requests for the item is still 1
     */
    function testItemChallenge() public {
        bytes32 itemID = submitItem(ITEM_DATA, requester);
        challengeItem(itemID, challenger);

        (
            bool disputed,
            ,
            ,
            bool resolved,
            address[3] memory parties,
            uint256 numberOfRounds,
            ,
            IArbitrator erc20VotesArbitrator,
            bytes memory arbitratorExtraData,
            uint256 metaEvidenceID
        ) = generalizedTCR.getRequestInfo(itemID, 0);

        assertTrue(disputed, "Item should be disputed after challenge");
        assertEq(parties[uint256(IArbitrable.Party.Requester)], requester, "Requester should be correct");
        assertEq(parties[uint256(IArbitrable.Party.Challenger)], challenger, "Challenger should be correct");
        assertEq(numberOfRounds, 2, "Number of rounds should be 2"); // new round is made after challenge for any appeals that occur post challenge
        assertFalse(resolved, "Request should not be resolved yet");
        assertEq(address(erc20VotesArbitrator), address(arbitrator), "Arbitrator should be correct");
        assertEq(arbitratorExtraData, ARBITRATOR_EXTRA_DATA, "Arbitrator extra data should be correct");
        assertEq(metaEvidenceID, 0, "Meta evidence ID should be 0");

        (bytes memory data, IGeneralizedTCR.Status status, uint256 numberOfRequests) = generalizedTCR.getItemInfo(
            itemID
        );

        assertEq(data, ITEM_DATA, "Item data should match");
        assertEq(
            uint256(status),
            uint256(IGeneralizedTCR.Status.RegistrationRequested),
            "Status should be RegistrationRequested"
        );
        assertEq(numberOfRequests, 1, "Number of requests should be 1");
    }

    /**
     * @dev Tests the registration of an item after the challenge period has passed
     * @notice This test performs the following steps:
     * 1. Submits an item to the TCR
     * 2. Advances time beyond the challenge period
     * 3. Executes the request to finalize the registration
     * 4. Retrieves the item information
     * 5. Verifies that the item data matches the submitted data
     * 6. Checks that the item status is now set to Registered
     * 7. Ensures that the number of requests for the item is still 1
     */
    function testItemRegistrationAfterChallengePeriod() public {
        bytes32 itemID = submitItem(ITEM_DATA, requester);

        advanceTime(CHALLENGE_PERIOD + 1);

        generalizedTCR.executeRequest(itemID);

        (bytes memory data, IGeneralizedTCR.Status status, uint256 numberOfRequests) = generalizedTCR.getItemInfo(
            itemID
        );

        assertEq(data, ITEM_DATA);
        assertEq(uint256(status), uint256(IGeneralizedTCR.Status.Registered));
        assertEq(numberOfRequests, 1);
    }

    /**
     * @dev Tests the basic flow of item submission, challenge, and registration
     * @notice This test performs the following steps:
     * 1. Submits an item to the TCR
     * 2. Verifies the initial state of the item (RegistrationRequested)
     * 3. Challenges the item
     * 4. Verifies the state after challenge (disputed, not resolved)
     * 5. Advances time beyond the challenge period
     * 6. Executes the request to finalize the registration
     * 7. Verifies the final state of the item (Registered)
     */
    function testBasicFlow() public {
        // Submit an item
        bytes32 itemID = submitItem(ITEM_DATA, requester);

        // Check initial state
        (bytes memory data, IGeneralizedTCR.Status status, uint256 numberOfRequests) = generalizedTCR.getItemInfo(
            itemID
        );
        assertEq(data, ITEM_DATA, "Item data should match");
        assertEq(
            uint256(status),
            uint256(IGeneralizedTCR.Status.RegistrationRequested),
            "Status should be RegistrationRequested"
        );
        assertEq(numberOfRequests, 1, "Number of requests should be 1");

        // Challenge the item
        challengeItem(itemID, challenger);

        // Check state after challenge
        (
            bool disputed,
            uint256 disputeID,
            ,
            bool resolved,
            address[3] memory parties,
            uint256 numberOfRounds,
            ,
            ,
            ,

        ) = generalizedTCR.getRequestInfo(itemID, 0);

        assertTrue(disputed, "Item should be disputed after challenge");
        assertEq(parties[uint256(IArbitrable.Party.Requester)], requester, "Requester should be correct");
        assertEq(parties[uint256(IArbitrable.Party.Challenger)], challenger, "Challenger should be correct");
        assertEq(numberOfRounds, 2, "Number of rounds should be 2"); // new round is made after challenge for any appeals that occur post challenge
        assertFalse(resolved, "Request should not be resolved yet");

        voteAndExecute(disputeID);

        // Check if the dispute is resolved
        (, , , bool requestResolved, , , IArbitrable.Party ruling, , , ) = generalizedTCR.getRequestInfo(itemID, 0);
        assertTrue(requestResolved, "Dispute should be resolved");
        assertEq(uint256(ruling), uint256(IArbitrable.Party.Requester), "Ruling should be in favor of the requester");

        advanceTime(CHALLENGE_PERIOD + 1);
        // Start of Selection
        vm.expectRevert(IGeneralizedTCR.REQUEST_MUST_NOT_BE_DISPUTED.selector);
        generalizedTCR.executeRequest(itemID);

        // Check final state
        (data, status, numberOfRequests) = generalizedTCR.getItemInfo(itemID);
        assertEq(data, ITEM_DATA, "Item data should still match");
        assertEq(numberOfRequests, 1, "Number of requests should still be 1");
        assertEq(uint256(status), uint256(IGeneralizedTCR.Status.Registered), "Status should be Registered");
    }
}
