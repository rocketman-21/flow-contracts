// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.26;

import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/// @title IERC721Checkpointable
/// @notice A limited version of the ERC721Checkpointable interface from the nouns-monorepo
/// @dev This interface is specifically designed for the NounsToken used by the Nouns DAO on Ethereum mainnet.
interface IERC721Checkpointable is IERC721 {
    ///                                                          ///
    ///                           FUNCTIONS                      ///
    ///                                                          ///

    /// @notice The current number of votes for an account
    /// @param account The account address
    function getCurrentVotes(address account) external view returns (uint96);

    /// @notice The number of votes for an account at a past timestamp
    /// @param account The account address
    /// @param blockNumber The past block number
    function getPriorVotes(address account, uint256 blockNumber) external view returns (uint96);
}
