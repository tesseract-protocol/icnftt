// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721PausableExtension} from "../../extensions/ERC721PausableExtension.sol";
import {ERC721TokenRemote} from "../ERC721TokenRemote.sol";
import {ERC721TokenTransferrer} from "../../ERC721TokenTransferrer.sol";

/**
 * @title ERC721PausableRemoteExtension
 * @dev An extension of ERC721TokenRemote that adds pausable functionality for NFTs on remote chains.
 *
 * This contract implements the pause mechanism for tokens on non-native chains,
 * allowing tokens to be frozen in place when necessary. It works in conjunction with
 * ERC721PausableHomeExtension to maintain consistent pause states across the chain network.
 *
 * Key features:
 * 1. Block token transfers when the contract is paused
 * 2. Allow pause state to be controlled via cross-chain messages
 * 3. Enable tokens to complete their transit even during paused state
 *
 * @dev This extension should be inherited instead of ERC721TokenRemote if pausable
 * functionality is needed for your remote token contract
 */
abstract contract ERC721PausableRemoteExtension is ERC721PausableExtension, ERC721TokenRemote {
    function _beforeTokenTransfer(address, uint256 tokenId) internal virtual override {
        if (_ownerOf(tokenId) != address(0)) {
            _requireNotPaused();
        }
    }

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal virtual override (ERC721TokenTransferrer) returns (address) {
        return super._update(to, tokenId, auth);
    }
}
