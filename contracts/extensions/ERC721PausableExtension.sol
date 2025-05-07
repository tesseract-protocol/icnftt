// contracts/extensions/ERC721PausableExtension.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
/**
 * @dev ERC721 token with pausable token transfers, minting and burning.
 *
 * @notice This is a customized version of OpenZeppelin's ERC721Pausable contract
 * that's designed to work with the cross-chain extension system.
 */

abstract contract ERC721PausableExtension is Pausable {
    bytes4 internal constant PAUSABLE_EXTENSION_ID = bytes4(0xda81525d); // keccak256("ERC721PausableExtension")
}
