// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {
    ERC721URIStorage,
    ERC721
} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {IERC721TokenHome} from "./interfaces/IERC721TokenHome.sol";
import {TeleporterRegistryOwnableApp} from "@teleporter/registry/TeleporterRegistryOwnableApp.sol";
import {TeleporterMessageInput, TeleporterFeeInfo} from "@teleporter/ITeleporterMessenger.sol";
import {
    TransferrerMessage,
    TransferrerMessageType,
    TransferTokenMessage,
    SendNFTInput,
    TokenSent,
    INFTTransferrer
} from "./interfaces/INFTTransferrer.sol";
import {IWarpMessenger} from
    "@avalabs/subnet-evm-contracts@1.2.0/contracts/interfaces/IWarpMessenger.sol";

contract ERC721TokenHome is
    IERC721TokenHome,
    INFTTransferrer,
    ERC721URIStorage,
    TeleporterRegistryOwnableApp
{
    bytes32 public immutable blockchainID;

    // Mapping from tokenId to lock status
    mapping(uint256 => bool) private _lockedTokens;

    // Mapping from chainId to remote contract address
    mapping(bytes32 => address) private _remoteContracts;

    // Array of registered chain IDs
    bytes32[] private _registeredChains;

    constructor(
        string memory name,
        string memory symbol,
        address teleporterRegistryAddress,
        uint256 minTeleporterVersion
    )
        ERC721(name, symbol)
        TeleporterRegistryOwnableApp(teleporterRegistryAddress, msg.sender, minTeleporterVersion)
    {
        blockchainID = IWarpMessenger(0x0200000000000000000000000000000000000005).getBlockchainID();
    }

    // Mint function (for demonstration)
    function mint(address to, uint256 tokenId, string memory uri) external onlyOwner {
        _mint(to, tokenId);
        _setTokenURI(tokenId, uri);
    }

    function getRegisteredChains() external view override returns (bytes32[] memory) {
        return _registeredChains;
    }

    function isTokenLocked(
        uint256 tokenId
    ) external view override returns (bool) {
        return _lockedTokens[tokenId];
    }

    // Implementation of IICNFTTHome functions

    function send(SendNFTInput calldata input, uint256 tokenId) external override {
        _validateSendNFTInput(input, tokenId);

        // Lock the token
        _lockedTokens[tokenId] = true;

        TransferrerMessage memory message = TransferrerMessage({
            messageType: TransferrerMessageType.SINGLE_HOP_SEND,
            payload: abi.encode(TransferTokenMessage({recipient: input.recipient, tokenId: tokenId}))
        });
        bytes32 messageID = _sendTeleporterMessage(
            TeleporterMessageInput({
                destinationBlockchainID: input.destinationBlockchainID,
                destinationAddress: input.destinationTokenTransferrerAddress,
                feeInfo: TeleporterFeeInfo({
                    feeTokenAddress: input.primaryFeeTokenAddress,
                    amount: input.primaryFee
                }),
                requiredGasLimit: input.requiredGasLimit,
                allowedRelayerAddresses: new address[](0),
                message: abi.encode(message)
            })
        );

        emit TokenSent(messageID, msg.sender, tokenId);

        emit TokenLocked(tokenId, input.destinationBlockchainID, input.recipient);
    }

    function _validateSendNFTInput(SendNFTInput calldata input, uint256 tokenId) internal view {
        require(
            input.destinationBlockchainID != bytes32(0), "NFTHome: zero destination blockchain ID"
        );
        require(
            input.destinationTokenTransferrerAddress != address(0),
            "NFTHome: zero destination token transferrer address"
        );
        require(input.recipient != address(0), "NFTHome: zero recipient");
        require(_exists(tokenId), "Token does not exist");
        require(
            ownerOf(tokenId) == msg.sender || isApprovedForAll(ownerOf(tokenId), msg.sender)
                || getApproved(tokenId) == msg.sender,
            "Not owner or approved"
        );
        require(!_lockedTokens[tokenId], "Token already locked");
        require(
            _remoteContracts[input.destinationBlockchainID] != address(0),
            "Destination chain not registered"
        );
    }

    function _receiveToken(
        bytes32 sourceBlockchainID,
        address recipient,
        uint256 tokenId
    ) internal {
        require(_lockedTokens[tokenId], "NFTHome: Token not locked");

        // Unlock the token
        _lockedTokens[tokenId] = false;

        // Transfer the token to the recipient
        _safeTransfer(address(this), recipient, tokenId, "");

        emit TokenUnlocked(tokenId, sourceBlockchainID, recipient);
    }

    // Register a remote contract on another chain
    function _registerRemote(
        bytes32 remoteBlockchainID,
        address remoteNftTransferrerAddress
    ) internal {
        require(remoteBlockchainID != bytes32(0), "NFTHome: zero remote blockchain ID");
        require(remoteBlockchainID != blockchainID, "NFTHome: cannot register remote on same chain");
        require(
            remoteNftTransferrerAddress != address(0),
            "NFTHome: zero remote token transferrer address"
        );
        require(
            _remoteContracts[remoteBlockchainID] == address(0), "NFTHome: remote already registered"
        );

        _remoteContracts[remoteBlockchainID] = remoteNftTransferrerAddress;
        _registeredChains.push(remoteBlockchainID);

        emit RemoteChainRegistered(remoteBlockchainID, remoteNftTransferrerAddress);
    }

    function _receiveTeleporterMessage(
        bytes32 sourceBlockchainID,
        address originSenderAddress,
        bytes memory message
    ) internal override {
        TransferrerMessage memory transferrerMessage = abi.decode(message, (TransferrerMessage));

        if (transferrerMessage.messageType == TransferrerMessageType.REGISTER_REMOTE) {
            _registerRemote(sourceBlockchainID, originSenderAddress);
        } else if (transferrerMessage.messageType == TransferrerMessageType.SINGLE_HOP_SEND) {
            TransferTokenMessage memory transferTokenMessage =
                abi.decode(transferrerMessage.payload, (TransferTokenMessage));
            _receiveToken(
                sourceBlockchainID, transferTokenMessage.recipient, transferTokenMessage.tokenId
            );
        }
    }

    // Override transferFrom and safeTransferFrom to prevent transfers of locked tokens
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId,
        uint256 batchSize
    ) internal view {
        require(!_lockedTokens[tokenId], "Token is locked");
    }

    // Helper function to check if token exists
    function _exists(
        uint256 tokenId
    ) internal view returns (bool) {
        try this.ownerOf(tokenId) returns (address) {
            return true;
        } catch {
            return false;
        }
    }
}
