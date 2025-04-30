// contracts/extensions/ERC721PausableExtension.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ExtensionMessage, ExtensionMessageParams} from "../interfaces/IERC721Transferrer.sol";
import {PausableExtensionMessage} from "./interfaces/IERC721PausableExtension.sol";
import {ERC721Extension} from "./ERC721Extension.sol";
/**
 * @dev ERC721 token with pausable token transfers, minting and burning.
 *
 * @notice This is a customized version of OpenZeppelin's ERC721Pausable contract
 * that's designed to work with the cross-chain extension system.
 */

abstract contract ERC721PausableExtension is ERC721Extension, Pausable {
    bytes4 internal constant PAUSABLE_EXTENSION_ID = bytes4(0xda81525d); // keccak256("ERC721PausableExtension")

    /**
     * @dev Updates the extension state based on the message
     */
    function _update(
        ExtensionMessage memory extension
    ) internal virtual override {
        if (extension.key == PAUSABLE_EXTENSION_ID) {
            PausableExtensionMessage memory pausableExtensionMessage =
                abi.decode(extension.value, (PausableExtensionMessage));

            if (pausableExtensionMessage.paused && !paused()) {
                _pause();
            } else if (!pausableExtensionMessage.paused && paused()) {
                _unpause();
            }
        }
    }

    /**
     * @dev Gets the extension message for the current pause state
     */
    function _getMessage(
        ExtensionMessageParams memory
    ) internal view virtual override returns (ExtensionMessage memory) {}
}
