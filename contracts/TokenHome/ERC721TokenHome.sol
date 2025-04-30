// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC721TokenHome} from "./interfaces/IERC721TokenHome.sol";
import {IERC721SendAndCallReceiver} from "../interfaces/IERC721SendAndCallReceiver.sol";
import {
    TransferrerMessage,
    TransferrerMessageType,
    SendTokenMessage,
    SendTokenInput,
    SendAndCallInput,
    TokenSent,
    TokenAndCallSent,
    UpdateRemoteBaseURIMessage,
    SendAndCallMessage,
    CallSucceeded,
    CallFailed,
    UpdateBaseURIInput,
    ExtensionMessage,
    ExtensionMessageParams
} from "../interfaces/IERC721Transferrer.sol";
import {ERC721TokenTransferrer} from "../ERC721TokenTransferrer.sol";
import {TeleporterRegistryOwnableApp} from "@teleporter/registry/TeleporterRegistryOwnableApp.sol";
import {TeleporterMessageInput, TeleporterFeeInfo} from "@teleporter/ITeleporterMessenger.sol";
import {IWarpMessenger} from "@avalabs/subnet-evm-contracts@1.2.0/contracts/interfaces/IWarpMessenger.sol";
import {CallUtils} from "@utilities/CallUtils.sol";
import {SafeERC20TransferFrom} from "@utilities/SafeERC20TransferFrom.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
/**
 * @title ERC721TokenHome
 * @dev A contract enabling cross-chain transfers of ERC721 tokens between Avalanche L1 networks.
 *
 * This contract serves as the "home" for ERC721 tokens on their native chain and allows them to be:
 * 1. Sent to other Avalanche L1 chains using Avalanche's Interchain Messaging (ICM) via Teleporter
 * 2. Received back from other chains
 * 3. Managed with metadata updates that propagate across chains
 *
 * It supports two primary token transfer modes:
 * - Basic transfer: Send a token to an address on another chain
 * - Send and call: Send a token while triggering a contract call on the destination chain
 *
 * This contract maintains registries of connected remote chains and tracks the current location
 * of tokens when they are transferred cross-chain.
 */

abstract contract ERC721TokenHome is IERC721TokenHome, ERC721TokenTransferrer, TeleporterRegistryOwnableApp {
    /// @notice Gas limit for updating base URI on remote chains
    uint256 public constant UPDATE_BASE_URI_GAS_LIMIT = 120000;

    /// @notice Mapping from blockchain ID to the contract address on that chain
    mapping(bytes32 => address) internal _remoteContracts;

    /// @notice Mapping from token ID to the blockchain ID where the token currently exists
    mapping(uint256 => bytes32) internal _tokenLocation;

    /// @notice List of all registered remote chains
    bytes32[] internal _registeredChains;

    /**
     * @notice Initializes the ERC721TokenHome contract
     * @param name The name of the ERC721 token
     * @param symbol The symbol of the ERC721 token
     * @param baseURI The base URI for token metadata
     * @param teleporterRegistryAddress The address of the Teleporter registry
     * @param minTeleporterVersion The minimum required Teleporter version
     */
    constructor(
        string memory name,
        string memory symbol,
        string memory baseURI,
        address teleporterRegistryAddress,
        uint256 minTeleporterVersion
    )
        ERC721TokenTransferrer(name, symbol, baseURI)
        TeleporterRegistryOwnableApp(teleporterRegistryAddress, msg.sender, minTeleporterVersion)
    {}

    /**
     * @notice Returns all blockchain IDs of registered remote chains
     * @return Array of blockchain IDs
     */
    function getRegisteredChains() external view override returns (bytes32[] memory) {
        return _registeredChains;
    }

    /**
     * @notice Returns the number of registered remote chains
     * @return Number of registered chains
     */
    function getRegisteredChainsLength() external view override returns (uint256) {
        return _registeredChains.length;
    }

    function getRemoteContract(
        bytes32 remoteBlockchainID
    ) external view override returns (address) {
        return _remoteContracts[remoteBlockchainID];
    }

    function getTokenLocation(
        uint256 tokenId
    ) external view override returns (bytes32) {
        return _tokenLocation[tokenId];
    }

    /**
     * @notice Sends a token to a recipient on another chain
     * @dev The token is transferred to this contract, and a message is sent to the destination chain
     * @param input Parameters for the cross-chain token transfer
     * @param tokenId The ID of the token to send
     */
    function send(SendTokenInput calldata input, uint256 tokenId) external override {
        _validateSendTokenInput(input);

        address tokenOwner = ownerOf(tokenId);
        transferFrom(tokenOwner, address(this), tokenId);

        _handleFees(input.primaryFeeTokenAddress, input.primaryFee);
        TransferrerMessage memory message = TransferrerMessage({
            messageType: TransferrerMessageType.SINGLE_HOP_SEND,
            payload: abi.encode(
                SendTokenMessage({
                    recipient: input.recipient,
                    tokenId: tokenId,
                    extensions: _getExtensionMessages(
                        ExtensionMessageParams({tokenId: tokenId, messageType: TransferrerMessageType.SINGLE_HOP_SEND})
                    )
                })
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

        _tokenLocation[tokenId] = input.destinationBlockchainID;

        emit TokenSent(messageID, msg.sender, tokenId);
    }

    /**
     * @notice Sends a token to a contract on another chain and executes a function on that contract
     * @dev The token is transferred to this contract, and a message is sent to the destination chain
     * @dev If the contract call fails, the token is sent to the fallback recipient
     * @param input Parameters for the cross-chain token transfer and contract call
     * @param tokenId The ID of the token to send
     */
    function sendAndCall(SendAndCallInput calldata input, uint256 tokenId) external override {
        _validateSendAndCallInput(input);

        address tokenOwner = ownerOf(tokenId);
        transferFrom(tokenOwner, address(this), tokenId);

        SendAndCallMessage memory message = SendAndCallMessage({
            tokenId: tokenId,
            originSenderAddress: msg.sender,
            recipientContract: input.recipientContract,
            recipientPayload: input.recipientPayload,
            recipientGasLimit: input.recipientGasLimit,
            fallbackRecipient: input.fallbackRecipient,
            extensions: _getExtensionMessages(
                ExtensionMessageParams({tokenId: tokenId, messageType: TransferrerMessageType.SINGLE_HOP_CALL})
            )
        });

        _handleFees(input.primaryFeeTokenAddress, input.primaryFee);
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

        _tokenLocation[tokenId] = input.destinationBlockchainID;

        emit TokenAndCallSent(messageID, msg.sender, tokenId);
    }

    /**
     * @notice Updates the base URI for all tokens and optionally updates it on remote chains
     * @dev Only callable by the owner
     * @param newBaseURI The new base URI
     * @param updateRemotes Whether to update the base URI on all registered remote chains
     * @param feeInfo Information about the fee to pay for cross-chain messages (if updating remotes)
     */
    function updateBaseURI(
        string memory newBaseURI,
        bool updateRemotes,
        TeleporterFeeInfo memory feeInfo
    ) external virtual onlyOwner {
        _baseURIStorage = newBaseURI;
        emit BaseURIUpdated(newBaseURI);
        if (updateRemotes) {
            _handleFees(feeInfo.feeTokenAddress, feeInfo.amount * _registeredChains.length);
            for (uint256 i = 0; i < _registeredChains.length; i++) {
                bytes32 remoteBlockchainID = _registeredChains[i];
                address remoteContract = _remoteContracts[remoteBlockchainID];
                _updateRemoteBaseURI(remoteBlockchainID, remoteContract, newBaseURI, feeInfo);
            }
        }
    }

    /**
     * @notice Updates the base URI on a specific remote chain
     * @dev Only callable by the owner
     * @param input Parameters for the cross-chain URI update
     */
    function updateRemoteBaseURI(
        UpdateBaseURIInput calldata input
    ) external onlyOwner {
        address remoteContract = _remoteContracts[input.destinationBlockchainID];
        require(input.destinationBlockchainID != bytes32(0), "ERC721TokenHome: zero destination blockchain ID");
        require(remoteContract != address(0), "ERC721TokenHome: destination chain not registered");
        _handleFees(input.primaryFeeTokenAddress, input.primaryFee);
        _updateRemoteBaseURI(
            input.destinationBlockchainID,
            remoteContract,
            _baseURIStorage,
            TeleporterFeeInfo({feeTokenAddress: input.primaryFeeTokenAddress, amount: input.primaryFee})
        );
    }

    /**
     * @notice Internal function to update the base URI on a remote chain
     * @param destinationBlockchainID The blockchain ID of the destination chain
     * @param remoteContract The address of the contract on the destination chain
     * @param uri The new base URI
     * @param feeInfo Information about the fee to pay for the cross-chain message
     */
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

    /**
     * @notice Validates the input parameters for a basic token send
     * @param input The input parameters to validate
     */
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

    /**
     * @notice Validates the input parameters for a send and call operation
     * @param input The input parameters to validate
     */
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

    /**
     * @notice Registers a remote contract on another chain
     * @dev Can only be called internally, triggered by receiving a register message from a remote chain
     * @param remoteBlockchainID The blockchain ID of the remote chain
     * @param remoteNftTransferrerAddress The address of the contract on the remote chain
     */
    function _registerRemote(bytes32 remoteBlockchainID, address remoteNftTransferrerAddress) internal {
        require(remoteBlockchainID != bytes32(0), "ERC721TokenHome: zero remote blockchain ID");
        require(remoteBlockchainID != _blockchainID, "ERC721TokenHome: cannot register remote on same chain");
        require(remoteNftTransferrerAddress != address(0), "ERC721TokenHome: zero remote token transferrer address");
        require(_remoteContracts[remoteBlockchainID] == address(0), "ERC721TokenHome: remote already registered");

        _remoteContracts[remoteBlockchainID] = remoteNftTransferrerAddress;
        _registeredChains.push(remoteBlockchainID);

        emit RemoteChainRegistered(remoteBlockchainID, remoteNftTransferrerAddress);
    }

    /**
     * @notice Handles the send and call operation when receiving a token from another chain
     * @dev Approves the recipient contract to use the token, then calls it with the specified payload
     * @dev If the call fails or the token is still owned by this contract, transfers it to the fallback recipient
     * @param message The message containing the send and call details
     * @param sourceBlockchainID The blockchain ID of the source chain
     * @param originSenderAddress The address of the sender contract on the source chain
     * @param tokenId The ID of the token being transferred
     */
    function _handleSendAndCall(
        SendAndCallMessage memory message,
        bytes32 sourceBlockchainID,
        address originSenderAddress,
        uint256 tokenId
    ) internal {
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

        _approve(message.recipientContract, tokenId, address(this));
        bool success = CallUtils._callWithExactGas(message.recipientGasLimit, message.recipientContract, payload);

        if (success) {
            emit CallSucceeded(message.recipientContract, tokenId);

            if (ownerOf(tokenId) == address(this)) {
                _safeTransfer(address(this), message.fallbackRecipient, tokenId, "");
            }
        } else {
            emit CallFailed(message.recipientContract, tokenId);
            _safeTransfer(address(this), message.fallbackRecipient, tokenId, "");
        }
    }

    /**
     * @notice Handles the collection of fees for cross-chain operations
     * @dev Transfers the fee token from the sender to this contract
     * @param feeTokenAddress The address of the token used for fees
     * @param feeAmount The amount of the fee
     */
    function _handleFees(address feeTokenAddress, uint256 feeAmount) internal {
        if (feeAmount == 0) {
            return;
        }
        SafeERC20TransferFrom.safeTransferFrom(IERC20(feeTokenAddress), _msgSender(), feeAmount);
    }

    function _validateReceiveToken(
        bytes32 sourceBlockchainID,
        address originSenderAddress,
        uint256 tokenId
    ) internal view {
        require(originSenderAddress == _remoteContracts[sourceBlockchainID], "ERC721TokenHome: invalid sender");
        require(_tokenLocation[tokenId] == sourceBlockchainID, "ERC721TokenHome: invalid token source");
    }

    /**
     * @notice Processes incoming Teleporter messages from other chains
     * @dev Handles different message types: registering remotes, receiving tokens, and send-and-call operations
     * @param sourceBlockchainID The blockchain ID of the source chain
     * @param originSenderAddress The address of the sender on the source chain
     * @param message The encoded message
     */
    function _receiveTeleporterMessage(
        bytes32 sourceBlockchainID,
        address originSenderAddress,
        bytes memory message
    ) internal virtual override {
        TransferrerMessage memory transferrerMessage = abi.decode(message, (TransferrerMessage));

        if (transferrerMessage.messageType == TransferrerMessageType.REGISTER_REMOTE) {
            _registerRemote(sourceBlockchainID, originSenderAddress);
        } else if (transferrerMessage.messageType == TransferrerMessageType.SINGLE_HOP_SEND) {
            SendTokenMessage memory sendTokenMessage = abi.decode(transferrerMessage.payload, (SendTokenMessage));
            _validateReceiveToken(sourceBlockchainID, originSenderAddress, sendTokenMessage.tokenId);
            _tokenLocation[sendTokenMessage.tokenId] = bytes32(0);
            _safeTransfer(address(this), sendTokenMessage.recipient, sendTokenMessage.tokenId, "");
        } else if (transferrerMessage.messageType == TransferrerMessageType.SINGLE_HOP_CALL) {
            SendAndCallMessage memory sendAndCallMessage = abi.decode(transferrerMessage.payload, (SendAndCallMessage));
            _validateReceiveToken(sourceBlockchainID, originSenderAddress, sendAndCallMessage.tokenId);
            _tokenLocation[sendAndCallMessage.tokenId] = bytes32(0);
            _handleSendAndCall(sendAndCallMessage, sourceBlockchainID, originSenderAddress, sendAndCallMessage.tokenId);
        } else if (transferrerMessage.messageType == TransferrerMessageType.UPDATE_EXTENSIONS) {
            ExtensionMessage[] memory extensions = abi.decode(transferrerMessage.payload, (ExtensionMessage[]));
            require(originSenderAddress == _remoteContracts[sourceBlockchainID], "ERC721TokenHome: invalid sender");
            _updateExtensions(extensions);
        }
    }
}
