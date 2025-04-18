// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC721TokenHome, ERC721} from "../ERC721TokenHome.sol";
import {ERC721URIStorageExtension} from "../../extensions/ERC721URIStorageExtension.sol";
import {TransferrerMessage, TransferrerMessageType, ExtensionMessage} from "../../interfaces/IERC721Transferrer.sol";
import {TeleporterMessageInput, TeleporterFeeInfo} from "@teleporter/ITeleporterMessenger.sol";
import {
    URIStorageExtensionMessage,
    UpdateURIInput,
    UpdateRemoteTokenURI
} from "../../extensions/interfaces/IERC721URIStorageExtension.sol";

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

    /**
     * @notice Updates the URI for a specific token on a specific remote chain
     * @dev Only callable by the owner
     * @param input Parameters for the cross-chain URI update
     * @param tokenId The ID of the token to update
     * @param uri The new URI for the token
     */
    function updateRemoteTokenURI(UpdateURIInput calldata input, uint256 tokenId, string memory uri) public onlyOwner {
        address remoteContract = _remoteContracts[input.destinationBlockchainID];
        require(input.destinationBlockchainID != bytes32(0), "ERC721TokenHome: zero destination blockchain ID");
        require(remoteContract != address(0), "ERC721TokenHome: destination chain not registered");
        _updateRemoteTokenURI(
            input.destinationBlockchainID,
            remoteContract,
            tokenId,
            uri,
            TeleporterFeeInfo({feeTokenAddress: input.primaryFeeTokenAddress, amount: input.primaryFee})
        );
    }

    /**
     * @notice Internal function to update a token URI on a remote chain
     * @param destinationBlockchainID The blockchain ID of the destination chain
     * @param remoteContract The address of the contract on the destination chain
     * @param tokenId The ID of the token to update
     * @param uri The new URI for the token
     * @param feeInfo Information about the fee to pay for the cross-chain message
     */
    function _updateRemoteTokenURI(
        bytes32 destinationBlockchainID,
        address remoteContract,
        uint256 tokenId,
        string memory uri,
        TeleporterFeeInfo memory feeInfo
    ) internal {
        ExtensionMessage[] memory extensions = new ExtensionMessage[](1);
        extensions[0] = ExtensionMessage({
            key: ERC4906_INTERFACE_ID,
            value: abi.encode(URIStorageExtensionMessage({tokenId: tokenId, uri: uri}))
        });
        TransferrerMessage memory message =
            TransferrerMessage({messageType: TransferrerMessageType.UPDATE_EXTENSIONS, payload: abi.encode(extensions)});
        bytes32 messageID = _sendTeleporterMessage(
            TeleporterMessageInput({
                destinationBlockchainID: destinationBlockchainID,
                destinationAddress: remoteContract,
                feeInfo: feeInfo,
                requiredGasLimit: UPDATE_TOKEN_URI_GAS_LIMIT,
                allowedRelayerAddresses: new address[](0),
                message: abi.encode(message)
            })
        );
        emit UpdateRemoteTokenURI(messageID, destinationBlockchainID, remoteContract, tokenId, uri);
    }
}
