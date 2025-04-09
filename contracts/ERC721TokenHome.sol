// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC721URIStorage, ERC721} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
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
import {IWarpMessenger} from "@avalabs/subnet-evm-contracts@1.2.0/contracts/interfaces/IWarpMessenger.sol";

contract ERC721TokenHome is IERC721TokenHome, INFTTransferrer, ERC721URIStorage, TeleporterRegistryOwnableApp {
    bytes32 private immutable _blockchainID;

    // Mapping from chainId to remote contract address
    mapping(bytes32 => address) private _remoteContracts;

    string private _baseURIStorage;

    // Array of registered chain IDs
    bytes32[] private _registeredChains;

    constructor(
        string memory name,
        string memory symbol,
        string memory baseURI,
        address teleporterRegistryAddress,
        uint256 minTeleporterVersion
    ) ERC721(name, symbol) TeleporterRegistryOwnableApp(teleporterRegistryAddress, msg.sender, minTeleporterVersion) {
        _blockchainID = IWarpMessenger(0x0200000000000000000000000000000000000005).getBlockchainID();
        _baseURIStorage = baseURI;
    }

    function _baseURI() internal view override returns (string memory) {
        return _baseURIStorage;
    }

    function getRegisteredChains() external view override returns (bytes32[] memory) {
        return _registeredChains;
    }

    function getBlockchainID() external view override returns (bytes32) {
        return _blockchainID;
    }

    function updateBaseURI(
        string memory newBaseURI
    ) external onlyOwner {
        _baseURIStorage = newBaseURI;
    }

    function updateRemoteBaseURI(
        SendNFTInput calldata input
    ) external onlyOwner {
        _validateSendNFTInput(input);
        TransferrerMessage memory message =
            TransferrerMessage({messageType: TransferrerMessageType.UPDATE_REMOTE_BASE_URI, payload: abi.encode(input)});
        bytes32 messageID = _sendTeleporterMessage(
            TeleporterMessageInput({
                destinationBlockchainID: input.destinationBlockchainID,
                destinationAddress: input.destinationTokenTransferrerAddress,
                feeInfo: TeleporterFeeInfo({feeTokenAddress: input.primaryFeeTokenAddress, amount: input.primaryFee}),
                requiredGasLimit: input.requiredGasLimit,
                allowedRelayerAddresses: new address[](0),
                message: abi.encode(message)
            })
        );
    }

    function mint(address to, uint256 tokenId, string memory uri) external onlyOwner {
        _mint(to, tokenId);
        _setTokenURI(tokenId, uri);
    }

    function send(SendNFTInput calldata input, uint256 tokenId) external override {
        _validateSendNFTInput(input);

        require(_exists(tokenId), "ERC721TokenHome: token does not exist");
        require(
            ownerOf(tokenId) == msg.sender || isApprovedForAll(ownerOf(tokenId), msg.sender)
                || getApproved(tokenId) == msg.sender,
            "ERC721TokenHome: not owner or approved"
        );

        _transfer(msg.sender, address(this), tokenId);

        TransferrerMessage memory message = TransferrerMessage({
            messageType: TransferrerMessageType.SINGLE_HOP_SEND,
            payload: abi.encode(TransferTokenMessage({recipient: input.recipient, tokenId: tokenId}))
        });
        bytes32 messageID = _sendTeleporterMessage(
            TeleporterMessageInput({
                destinationBlockchainID: input.destinationBlockchainID,
                destinationAddress: input.destinationTokenTransferrerAddress,
                feeInfo: TeleporterFeeInfo({feeTokenAddress: input.primaryFeeTokenAddress, amount: input.primaryFee}),
                requiredGasLimit: input.requiredGasLimit,
                allowedRelayerAddresses: new address[](0),
                message: abi.encode(message)
            })
        );

        emit TokenSent(messageID, msg.sender, tokenId);
    }

    function _validateSendNFTInput(
        SendNFTInput calldata input
    ) internal view {
        require(input.destinationBlockchainID != bytes32(0), "ERC721TokenHome: zero destination blockchain ID");
        require(
            input.destinationTokenTransferrerAddress != address(0),
            "ERC721TokenHome: zero destination token transferrer address"
        );
        require(input.recipient != address(0), "ERC721TokenHome: zero recipient");
        require(
            _remoteContracts[input.destinationBlockchainID] != address(0),
            "ERC721TokenHome: destination chain not registered"
        );
    }

    // Register a remote contract on another chain
    function _registerRemote(bytes32 remoteBlockchainID, address remoteNftTransferrerAddress) internal {
        require(remoteBlockchainID != bytes32(0), "ERC721TokenHome: zero remote blockchain ID");
        require(remoteBlockchainID != _blockchainID, "ERC721TokenHome: cannot register remote on same chain");
        require(remoteNftTransferrerAddress != address(0), "ERC721TokenHome: zero remote token transferrer address");
        require(_remoteContracts[remoteBlockchainID] == address(0), "ERC721TokenHome: remote already registered");

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
            _safeTransfer(address(this), transferTokenMessage.recipient, transferTokenMessage.tokenId, "");
        }
    }

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
