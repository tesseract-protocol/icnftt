// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC721Transferrer} from "./interfaces/IERC721Transferrer.sol";
import {ExtensionMessage} from "./interfaces/IERC721Transferrer.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IWarpMessenger} from "@avalabs/subnet-evm-contracts@1.2.0/contracts/interfaces/IWarpMessenger.sol";

abstract contract ERC721TokenTransferrer is ERC721, IERC721Transferrer {
    bytes32 internal immutable _blockchainID;
    string internal _baseURIStorage;

    constructor(string memory name, string memory symbol, string memory baseURI) ERC721(name, symbol) {
        _baseURIStorage = baseURI;
        _blockchainID = IWarpMessenger(0x0200000000000000000000000000000000000005).getBlockchainID();
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseURIStorage;
    }

    function getBlockchainID() external view override returns (bytes32) {
        return _blockchainID;
    }

    function _updateExtensions(
        ExtensionMessage[] memory extensions
    ) internal virtual;

    function _getExtensionMessages(
        uint256 tokenId
    ) internal virtual returns (ExtensionMessage[] memory);

    function _beforeTokenTransfer(address to, uint256 tokenId) internal virtual {}
    function _afterTokenTransfer(address from, address to, uint256 tokenId) internal virtual {}

    function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address) {
        _beforeTokenTransfer(to, tokenId);
        address from = super._update(to, tokenId, auth);
        _afterTokenTransfer(from, to, tokenId);
        return from;
    }
}
