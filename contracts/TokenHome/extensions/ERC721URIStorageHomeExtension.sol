// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC721TokenHome, ERC721} from "../ERC721TokenHome.sol";
import {ERC721URIStorageExtension} from "../../extensions/ERC721URIStorageExtension.sol";
import {
    UpdateRemoteTokenURIMessage,
    TransferrerMessage,
    TransferrerMessageType
} from "../../interfaces/IERC721Transferrer.sol";
import {TeleporterFeeInfo} from "@teleporter/ITeleporterMessenger.sol";

abstract contract ERC721URIStorageHomeExtension is ERC721URIStorageExtension, ERC721TokenHome {
    function _baseURI() internal view virtual override (ERC721, ERC721TokenHome) returns (string memory) {
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

    /**
     * @notice Updates the URI for a specific token and optionally updates it on the remote chain
     * @dev Only callable by the owner
     * @param tokenId The ID of the token to update
     * @param newURI The new URI for the token
     * @param updateRemote Whether to update the URI on the remote chain if the token is currently on another chain
     * @param feeInfo Information about the fee to pay for the cross-chain message (if updating remote)
     */
    function updateTokenURI(
        uint256 tokenId,
        string memory newURI,
        bool updateRemote,
        TeleporterFeeInfo memory feeInfo
    ) external virtual onlyOwner {
        _setTokenURI(tokenId, newURI);
        if (updateRemote) {
            bytes32 remoteBlockchainID = _tokenRemoteContracts[tokenId];
            if (remoteBlockchainID != bytes32(0)) {
                address remoteContract = _remoteContracts[remoteBlockchainID];
                _updateRemoteTokenURI(remoteBlockchainID, remoteContract, tokenId, newURI, feeInfo);
            }
        }
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
