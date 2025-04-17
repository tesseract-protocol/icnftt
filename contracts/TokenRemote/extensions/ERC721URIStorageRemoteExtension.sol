// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC721TokenRemote, ERC721} from "../ERC721TokenRemote.sol";
import {ERC721URIStorageExtension} from "../../extensions/ERC721URIStorageExtension.sol";
import {
    UpdateRemoteTokenURIMessage,
    TransferrerMessage,
    TransferrerMessageType
} from "../../interfaces/IERC721Transferrer.sol";

abstract contract ERC721URIStorageRemoteExtension is ERC721URIStorageExtension, ERC721TokenRemote {
    function _baseURI() internal view virtual override (ERC721, ERC721TokenRemote) returns (string memory) {
        return super._baseURI();
    }

    function tokenURI(
        uint256 tokenId
    ) public view virtual override (ERC721URIStorageExtension, ERC721) returns (string memory) {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override (ERC721URIStorageExtension, ERC721) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function _receiveTeleporterMessage(
        bytes32 sourceBlockchainID,
        address originSenderAddress,
        bytes memory message
    ) internal virtual override {
        super._receiveTeleporterMessage(sourceBlockchainID, originSenderAddress, message);

        TransferrerMessage memory transferrerMessage = abi.decode(message, (TransferrerMessage));

        if (transferrerMessage.messageType == TransferrerMessageType.UPDATE_REMOTE_TOKEN_URI) {
            UpdateRemoteTokenURIMessage memory updateRemoteTokenURIMessage =
                abi.decode(transferrerMessage.payload, (UpdateRemoteTokenURIMessage));
            _tokenURIs[updateRemoteTokenURIMessage.tokenId] = updateRemoteTokenURIMessage.uri;
        }
    }
}
