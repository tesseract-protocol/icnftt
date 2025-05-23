// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {ERC721TokenTransferrer} from "../../ERC721TokenTransferrer.sol";
import {ERC721URIStorageExtension} from "../../extensions/ERC721URIStorageExtension.sol";
import {
    TransferrerMessage,
    TransferrerMessageType,
    ExtensionMessage,
    ExtensionMessageParams
} from "../../interfaces/IERC721Transferrer.sol";
import {TeleporterMessageInput, TeleporterFeeInfo} from "@teleporter/ITeleporterMessenger.sol";
import {URIStorageExtensionMessage, UpdateURIInput} from "../../extensions/interfaces/IERC721URIStorageExtension.sol";
import {ERC721HomeExtension} from "./ERC721HomeExtension.sol";
/**
 * @title ERC721URIStorageHomeExtension
 * @dev An extension of ERC721TokenHome that adds enhanced URI storage and management functionality for NFTs.
 *
 * This contract enables per-token URI management with cross-chain synchronization capabilities,
 * allowing token metadata to be consistently maintained across all chains where the tokens
 * might travel.
 *
 * Key features:
 * 1. Store and retrieve individual token URIs
 * 2. Update token URIs on the home chain
 * 3. Propagate URI updates to remote chains where tokens currently exist
 * 4. Selectively update URIs on specific remote chains
 *
 * @dev This extension should be inherited instead of ERC721TokenHome if enhanced
 * token URI management functionality is needed for your token contract
 */

abstract contract ERC721URIStorageHomeExtension is ERC721URIStorageExtension, ERC721HomeExtension {
    /// @notice Gas limit for updating token URI on remote chains
    uint256 public constant UPDATE_TOKEN_URI_GAS_LIMIT = 120000;

    /**
     * @dev Emitted when a request to update a specific token URI on a remote chain is sent
     * @param teleporterMessageID The ID of the Teleporter message
     * @param destinationBlockchainID The blockchain ID of the destination chain
     * @param remote The address of the contract on the remote chain
     * @param tokenId The ID of the token
     * @param uri The new token URI
     */
    event UpdateRemoteTokenURI(
        bytes32 indexed teleporterMessageID,
        bytes32 indexed destinationBlockchainID,
        address indexed remote,
        uint256 tokenId,
        string uri
    );

    function _baseURI() internal view virtual override (ERC721, ERC721TokenTransferrer) returns (string memory) {
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
            bytes32 remoteBlockchainID = _tokenLocation[tokenId];
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
            key: URI_STORAGE_EXTENSION_ID,
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

    /**
     * @dev Gets the extension message for the current token URI
     */
    function _getMessage(
        ExtensionMessageParams memory params
    ) internal view virtual override returns (ExtensionMessage memory) {
        return ExtensionMessage(
            URI_STORAGE_EXTENSION_ID,
            abi.encode(URIStorageExtensionMessage({tokenId: params.tokenId, uri: _tokenURIs[params.tokenId]}))
        );
    }

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal virtual override (ERC721URIStorageExtension, ERC721TokenTransferrer) returns (address) {
        return super._update(to, tokenId, auth);
    }
}
