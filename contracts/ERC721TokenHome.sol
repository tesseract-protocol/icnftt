// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {ERC721URIStorage, ERC721} from "./ERC721URIStorage.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IERC721TokenHome, UpdateURIInput} from "./interfaces/IERC721TokenHome.sol";
import {TeleporterRegistryOwnableApp} from "@teleporter/registry/TeleporterRegistryOwnableApp.sol";
import {TeleporterMessageInput, TeleporterFeeInfo} from "@teleporter/ITeleporterMessenger.sol";
import {
    TransferrerMessage,
    TransferrerMessageType,
    SendTokenMessage,
    SendTokenInput,
    SendAndCallInput,
    TokenSent,
    TokenAndCallSent,
    IERC721Transferrer,
    UpdateRemoteBaseURIMessage,
    UpdateRemoteTokenURIMessage,
    SendAndCallMessage,
    CallSucceeded,
    CallFailed
} from "./interfaces/IERC721Transferrer.sol";
import {IERC721SendAndCallReceiver} from "./interfaces/IERC721SendAndCallReceiver.sol";
import {IWarpMessenger} from "@avalabs/subnet-evm-contracts@1.2.0/contracts/interfaces/IWarpMessenger.sol";
import {CallUtils} from "@utilities/CallUtils.sol";

contract ERC721TokenHome is IERC721TokenHome, IERC721Transferrer, ERC721URIStorage, TeleporterRegistryOwnableApp {
    bytes32 private immutable _blockchainID;

    uint256 public constant UPDATE_TOKEN_URI_GAS_LIMIT = 120000;
    uint256 public constant UPDATE_BASE_URI_GAS_LIMIT = 120000;

    mapping(bytes32 => address) private _remoteContracts;
    mapping(uint256 => bytes32) private _tokenRemoteContracts;

    string private _baseURIStorage;

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

    function getRegisteredChainsLength() external view returns (uint256) {
        return _registeredChains.length;
    }

    function updateBaseURI(
        string memory newBaseURI,
        bool updateRemotes,
        TeleporterFeeInfo memory feeInfo
    ) external virtual onlyOwner {
        _baseURIStorage = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
        if (updateRemotes) {
            for (uint256 i = 0; i < _registeredChains.length; i++) {
                bytes32 remoteBlockchainID = _registeredChains[i];
                address remoteContract = _remoteContracts[remoteBlockchainID];
                _updateRemoteBaseURI(remoteBlockchainID, remoteContract, newBaseURI, feeInfo);
            }
        }
    }

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

    function send(SendTokenInput calldata input, uint256 tokenId) external override {
        _validateSendTokenInput(input);

        address tokenOwner = ownerOf(tokenId);
        transferFrom(tokenOwner, address(this), tokenId);

        TransferrerMessage memory message = TransferrerMessage({
            messageType: TransferrerMessageType.SINGLE_HOP_SEND,
            payload: abi.encode(
                SendTokenMessage({recipient: input.recipient, tokenId: tokenId, tokenURI: _tokenURIs[tokenId]})
            )
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

        _tokenRemoteContracts[tokenId] = input.destinationBlockchainID;

        emit TokenSent(messageID, msg.sender, tokenId);
    }

    function sendAndCall(SendAndCallInput calldata input, uint256 tokenId) external override {
        _validateSendAndCallInput(input);

        address tokenOwner = ownerOf(tokenId);
        transferFrom(tokenOwner, address(this), tokenId);

        SendAndCallMessage memory message = SendAndCallMessage({
            tokenId: tokenId,
            tokenURI: _tokenURIs[tokenId],
            originSenderAddress: msg.sender,
            recipientContract: input.recipientContract,
            recipientPayload: input.recipientPayload,
            recipientGasLimit: input.recipientGasLimit,
            fallbackRecipient: input.fallbackRecipient
        });

        TransferrerMessage memory transferrerMessage =
            TransferrerMessage({messageType: TransferrerMessageType.SINGLE_HOP_CALL, payload: abi.encode(message)});

        bytes32 messageID = _sendTeleporterMessage(
            TeleporterMessageInput({
                destinationBlockchainID: input.destinationBlockchainID,
                destinationAddress: input.destinationTokenTransferrerAddress,
                feeInfo: TeleporterFeeInfo({feeTokenAddress: input.primaryFeeTokenAddress, amount: input.primaryFee}),
                requiredGasLimit: input.requiredGasLimit,
                allowedRelayerAddresses: new address[](0),
                message: abi.encode(transferrerMessage)
            })
        );

        _tokenRemoteContracts[tokenId] = input.destinationBlockchainID;

        emit TokenAndCallSent(messageID, msg.sender, tokenId);
    }

    function updateRemoteBaseURI(
        UpdateURIInput calldata input
    ) external onlyOwner {
        address remoteContract = _remoteContracts[input.destinationBlockchainID];
        require(input.destinationBlockchainID != bytes32(0), "ERC721TokenHome: zero destination blockchain ID");
        require(remoteContract != address(0), "ERC721TokenHome: destination chain not registered");
        _updateRemoteBaseURI(
            input.destinationBlockchainID,
            remoteContract,
            _baseURIStorage,
            TeleporterFeeInfo({feeTokenAddress: input.primaryFeeTokenAddress, amount: input.primaryFee})
        );
    }

    function _updateRemoteBaseURI(
        bytes32 destinationBlockchainID,
        address remoteContract,
        string memory uri,
        TeleporterFeeInfo memory feeInfo
    ) internal {
        TransferrerMessage memory message = TransferrerMessage({
            messageType: TransferrerMessageType.UPDATE_REMOTE_BASE_URI,
            payload: abi.encode(UpdateRemoteBaseURIMessage({baseURI: _baseURIStorage}))
        });
        bytes32 messageID = _sendTeleporterMessage(
            TeleporterMessageInput({
                destinationBlockchainID: destinationBlockchainID,
                destinationAddress: remoteContract,
                feeInfo: feeInfo,
                requiredGasLimit: UPDATE_BASE_URI_GAS_LIMIT,
                allowedRelayerAddresses: new address[](0),
                message: abi.encode(message)
            })
        );
        emit UpdateRemoteBaseURI(messageID, destinationBlockchainID, remoteContract, uri);
    }

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

    function _updateRemoteTokenURI(
        bytes32 destinationBlockchainID,
        address remoteContract,
        uint256 tokenId,
        string memory uri,
        TeleporterFeeInfo memory feeInfo
    ) internal {
        TransferrerMessage memory message = TransferrerMessage({
            messageType: TransferrerMessageType.UPDATE_REMOTE_TOKEN_URI,
            payload: abi.encode(UpdateRemoteTokenURIMessage({tokenId: tokenId, uri: uri}))
        });
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

    function _validateSendTokenInput(
        SendTokenInput calldata input
    ) internal view {
        require(input.destinationBlockchainID != bytes32(0), "ERC721TokenHome: zero destination blockchain ID");
        address remoteContract = _remoteContracts[input.destinationBlockchainID];
        require(remoteContract != address(0), "ERC721TokenHome: destination chain not registered");
        require(
            remoteContract == input.destinationTokenTransferrerAddress,
            "ERC721TokenHome: invalid destination token transferrer address"
        );
        require(
            input.destinationTokenTransferrerAddress != address(0),
            "ERC721TokenHome: zero destination token transferrer address"
        );
        require(input.recipient != address(0), "ERC721TokenHome: zero recipient");
    }

    function _validateSendAndCallInput(
        SendAndCallInput calldata input
    ) internal view {
        require(input.destinationBlockchainID != bytes32(0), "ERC721TokenHome: zero destination blockchain ID");
        address remoteContract = _remoteContracts[input.destinationBlockchainID];
        require(remoteContract != address(0), "ERC721TokenHome: destination chain not registered");
        require(
            remoteContract == input.destinationTokenTransferrerAddress,
            "ERC721TokenHome: invalid destination token transferrer address"
        );
        require(
            input.destinationTokenTransferrerAddress != address(0),
            "ERC721TokenHome: zero destination token transferrer address"
        );
        require(input.recipientContract != address(0), "ERC721TokenHome: zero recipient contract");
        require(input.fallbackRecipient != address(0), "ERC721TokenHome: zero fallback recipient");
        require(input.requiredGasLimit > 0, "ERC721TokenHome: zero required gas limit");
        require(input.recipientGasLimit > 0, "ERC721TokenHome: zero recipient gas limit");
        require(input.recipientGasLimit < input.requiredGasLimit, "TokenHome: invalid recipient gas limit");
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
            SendTokenMessage memory sendTokenMessage = abi.decode(transferrerMessage.payload, (SendTokenMessage));
            _tokenRemoteContracts[sendTokenMessage.tokenId] = bytes32(0);
            _safeTransfer(address(this), sendTokenMessage.recipient, sendTokenMessage.tokenId, "");
        } else if (transferrerMessage.messageType == TransferrerMessageType.SINGLE_HOP_CALL) {
            SendAndCallMessage memory sendAndCallMessage = abi.decode(transferrerMessage.payload, (SendAndCallMessage));
            _tokenRemoteContracts[sendAndCallMessage.tokenId] = bytes32(0);
            _handleSendAndCall(sendAndCallMessage, _blockchainID, originSenderAddress, sendAndCallMessage.tokenId);
        }
    }

    function _handleSendAndCall(
        SendAndCallMessage memory message,
        bytes32 sourceBlockchainID,
        address originSenderAddress,
        uint256 tokenId
    ) internal {
        approve(message.recipientContract, tokenId);

        bytes memory payload = abi.encodeCall(
            IERC721SendAndCallReceiver.receiveToken,
            (
                sourceBlockchainID,
                originSenderAddress,
                message.originSenderAddress,
                address(this),
                tokenId,
                message.recipientPayload
            )
        );

        bool success = CallUtils._callWithExactGas(message.recipientGasLimit, message.recipientContract, payload);

        if (success) {
            emit CallSucceeded(message.recipientContract, tokenId);

            if (ownerOf(tokenId) == address(this)) {
                approve(address(0), tokenId);
                _safeTransfer(address(this), message.fallbackRecipient, tokenId, "");
            }
        } else {
            emit CallFailed(message.recipientContract, tokenId);
            approve(address(0), tokenId);
            _safeTransfer(address(this), message.fallbackRecipient, tokenId, "");
        }
    }
}
