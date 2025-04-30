// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC721URIStorageExtension} from "../../extensions/ERC721URIStorageExtension.sol";
import {ERC721TokenRemote} from "../ERC721TokenRemote.sol";
import {ERC721TokenTransferrer} from "../../ERC721TokenTransferrer.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/**
 * @title ERC721URIStorageRemoteExtension
 * @dev An extension of ERC721TokenRemote that adds enhanced URI storage for NFTs on remote chains.
 *
 * This contract enables per-token URI management on non-native chains, allowing tokens
 * to maintain consistent metadata regardless of which chain they currently reside on.
 * It works in conjunction with ERC721URIStorageHomeExtension to ensure URI synchronization
 * across the chain network.
 *
 * Key features:
 * 1. Store and retrieve individual token URIs on remote chains
 * 2. Receive URI updates from the home chain
 * 3. Maintain metadata consistency for tokens across all chains
 *
 * @dev This extension should be inherited instead of ERC721TokenRemote if enhanced
 * token URI management functionality is needed for your remote token contract
 */
abstract contract ERC721URIStorageRemoteExtension is ERC721TokenRemote, ERC721URIStorageExtension {
    function _baseURI() internal view virtual override (ERC721, ERC721TokenTransferrer) returns (string memory) {
        return super._baseURI();
    }

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal virtual override (ERC721URIStorageExtension, ERC721TokenTransferrer) returns (address) {
        return super._update(to, tokenId, auth);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override (ERC721URIStorageExtension, ERC721) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function tokenURI(
        uint256 tokenId
    ) public view virtual override (ERC721URIStorageExtension, ERC721) returns (string memory) {
        return super.tokenURI(tokenId);
    }
}
