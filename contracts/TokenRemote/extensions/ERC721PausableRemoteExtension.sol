// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721PausableExtension} from "../../extensions/ERC721PausableExtension.sol";
import {ERC721TokenRemote} from "../ERC721TokenRemote.sol";
import {ERC721TokenTransferrer} from "../../ERC721TokenTransferrer.sol";

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
