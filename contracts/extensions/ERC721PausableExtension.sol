// contracts/extensions/ERC721PausableExtension.sol
// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ExtensionMessage} from "../interfaces/IERC721Transferrer.sol";
import {PausableExtensionMessage} from "./interfaces/IERC721PausableExtension.sol";

/**
 * @dev ERC721 token with pausable token transfers, minting and burning.
 *
 * @notice This is a customized version of OpenZeppelin's ERC721Pausable contract
 * that's designed to work with the cross-chain extension system.
 */
abstract contract ERC721PausableExtension is ERC721, Pausable {
    // Interface ID for the ERC721Pausable extension
    bytes4 internal constant PAUSABLE_INTERFACE_ID = bytes4(0x5b5e139f); // keccak256("ERC721PausableExtension")

    /**
     * @dev Updates the extension state based on the message
     */
    function _update(
        ExtensionMessage memory extension
    ) internal virtual {
        if (extension.key == PAUSABLE_INTERFACE_ID) {
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
    function _getMessage() internal view returns (ExtensionMessage memory) {
        return ExtensionMessage(PAUSABLE_INTERFACE_ID, abi.encode(PausableExtensionMessage({paused: paused()})));
    }
}
