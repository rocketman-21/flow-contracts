// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.27;

import { ISuperfluid, BatchOperation, IGeneralDistributionAgreementV1, ISuperToken, ISuperfluidPool } from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperfluid.sol";

import { IUserDefinedMacro } from "@superfluid-finance/ethereum-contracts/contracts/utils/MacroForwarder.sol";

contract BulkPoolWithdraw is IUserDefinedMacro {
    /**
     * @notice Reverts if the address is zero
     */
    error ADDRESS_ZERO();

    constructor() payable {}

    function getParams(address[] memory poolAddresses) public pure returns (bytes memory) {
        return abi.encode(poolAddresses);
    }

    /**
     * @dev A post-check function which is called after execution.
     * It allows to do arbitrary checks based on the state after execution,
     * and to revert if the result is not as expected.
     * Can be an empty implementation if no check is needed.
     * @param  host       The host contract set for the executing MacroForwarder.
     * @param  params     The encoded parameters as provided to `MacroForwarder.runMacro()`
     * @param  msgSender  The msg.sender of the call to the MacroForwarder.
     */
    function postCheck(ISuperfluid host, bytes memory params, address msgSender) external view override {}

    /**
     * @notice Bulk withdraws from baseline and bonus pool for UX
     * @dev Call this via the macrofowarder contract to bulk withdraw from both pools and maintain
     * claimable balance consistency onchain
     * @dev Build batch operations according to the parameters provided.
     * It's up to the macro contract to map the provided params (can also be empty) to any
     * valid list of operations.
     * @param  host       The executing host contract.
     * @param  params     The encoded form of the parameters.
     * @param  msgSender  The msg.sender of the call to the MacroForwarder.
     * @return operations The batch operations built.
     */
    function buildBatchOperations(
        ISuperfluid host,
        bytes memory params,
        address msgSender
    ) external view returns (ISuperfluid.Operation[] memory operations) {
        // Parse params
        address[] memory poolAddresses = abi.decode(params, (address[]));
        if (poolAddresses.length == 0) revert ADDRESS_ZERO();
        // Calculate total number of operations
        uint256 totalOperations = 0;
        for (uint256 i = 0; i < poolAddresses.length; i++) {
            ISuperfluidPool pool = ISuperfluidPool(poolAddresses[i]);
            (int256 claimableBalance, ) = pool.getClaimableNow(msgSender);
            if (claimableBalance > 0) {
                totalOperations += 2; // One for claim, one for downgrade
            }
        }

        // Initialize operations array
        operations = new ISuperfluid.Operation[](totalOperations);

        // Build operations for all pools
        uint256 operationIndex = 0;
        for (uint256 i = 0; i < poolAddresses.length; i++) {
            ISuperfluidPool pool = ISuperfluidPool(poolAddresses[i]);
            (int256 claimableBalance, ) = pool.getClaimableNow(msgSender);
            if (claimableBalance > 0) {
                ISuperfluid.Operation[] memory poolOps = _buildPoolOperations(host, pool, msgSender);
                for (uint256 j = 0; j < poolOps.length; j++) {
                    operations[operationIndex] = poolOps[j];
                    operationIndex++;
                }
            }
        }

        return operations;
    }

    /**
     * @notice Builds operations for a specific pool
     * @param host The Superfluid host contract
     * @param pool The pool to build operations for
     * @param msgSender The message sender
     * @return operations The operations built for the pool
     */
    function _buildPoolOperations(
        ISuperfluid host,
        ISuperfluidPool pool,
        address msgSender
    ) internal view returns (ISuperfluid.Operation[] memory operations) {
        (int256 claimableBalance, ) = pool.getClaimableNow(msgSender);

        operations = new ISuperfluid.Operation[](2);

        // op: connect outTokenDistributionPool
        IGeneralDistributionAgreementV1 gda = IGeneralDistributionAgreementV1(
            address(
                host.getAgreementClass(keccak256("org.superfluid-finance.agreements.GeneralDistributionAgreement.v1"))
            )
        );
        operations[0] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_SUPERFLUID_CALL_AGREEMENT,
            target: address(gda),
            data: abi.encode(
                abi.encodeCall(
                    gda.claimAll,
                    (
                        pool,
                        msgSender,
                        new bytes(0) // ctx
                    )
                ), // calldata
                new bytes(0) // userdata
            )
        });

        // op: downgrade
        operations[1] = ISuperfluid.Operation({
            operationType: BatchOperation.OPERATION_TYPE_SUPERTOKEN_DOWNGRADE,
            target: address(pool.superToken()),
            data: abi.encode(claimableBalance)
        });

        return operations;
    }
}
