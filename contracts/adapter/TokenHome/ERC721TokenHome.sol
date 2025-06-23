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
    TokensSent,
    TokensAndCallSent,
    SendAndCallMessage,
    CallSucceeded,
    CallFailed
} from "../interfaces/IERC721Transferrer.sol";
import {ERC721TokenTransferrer} from "../ERC721TokenTransferrer.sol";
import {TeleporterRegistryOwnableApp} from "@teleporter/registry/TeleporterRegistryOwnableApp.sol";
import {TeleporterMessageInput, TeleporterFeeInfo} from "@teleporter/ITeleporterMessenger.sol";
import {IWarpMessenger} from "@avalabs/subnet-evm-contracts@1.2.0/contracts/interfaces/IWarpMessenger.sol";
import {CallUtils} from "@utilities/CallUtils.sol";
import {SafeERC20TransferFrom} from "@utilities/SafeERC20TransferFrom.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title ERC721TokenHome
 * @dev A contract enabling cross-chain transfers of existing ERC721 tokens between Avalanche L1 networks.
 *
 * This contract serves as an adapter for existing ERC721 tokens on their native chain and allows them to be:
 * 1. Sent to other Avalanche L1 chains using Avalanche's Interchain Messaging (ICM) via Teleporter
 * 2. Received back from other chains
 *
 * It supports two primary token transfer modes:
 * - Basic transfer: Send multiple tokens to an address on another chain
 * - Send and call: Send multiple tokens while triggering a contract call on the destination chain
 *
 * This contract maintains registries of connected remote chains and tracks the current location
 * of tokens when they are transferred cross-chain, while working with existing ERC721 tokens.
 */
abstract contract ERC721TokenHome is
    IERC721TokenHome,
    ERC721TokenTransferrer,
    TeleporterRegistryOwnableApp
{
    /// @notice Mapping from blockchain ID to the contract address on that chain
    mapping(bytes32 remoteBlockchainID => address remoteContractAddress) internal _remoteContracts;

    /// @notice Mapping from token ID to the blockchain ID where the token currently exists
    mapping(uint256 tokenId => bytes32 blockchainID) internal _tokenLocation;

    /// @notice List of all registered remote chains
    bytes32[] internal _registeredChains;

    /// @notice The address of the ERC721 token contract on the home chain
    address internal _token;

    /// @notice Mapping from blockchain ID to the expected remote contract address
    mapping(bytes32 => address) internal _expectedRemoteContracts;

    /**
     * @notice Initializes the ERC721TokenHome contract
     * @param token The address of the existing ERC721 token contract to adapt
     * @param teleporterRegistryAddress The address of the Teleporter registry
     * @param teleporterManager The address of the Teleporter manager that will be responsible for managing cross-chain messages
     * @param minTeleporterVersion The minimum required Teleporter version
     */
    constructor(
        address token,
        address teleporterRegistryAddress,
        address teleporterManager,
        uint256 minTeleporterVersion
    )
        ERC721TokenTransferrer()
        TeleporterRegistryOwnableApp(teleporterRegistryAddress, teleporterManager, minTeleporterVersion)
    {
        _token = token;
    }

    /**
     * @notice Returns all blockchain IDs of registered remote chains
     * @return Array of blockchain IDs
     */
    function getRegisteredChains() external view override returns (bytes32[] memory) {
        return _registeredChains;
    }

    /**
     * @notice Returns the blockchain ID of a registered remote chain
     * @param index The index of the registered chain
     * @return The blockchain ID of the registered chain
     */
    function getRegisteredChain(
        uint256 index
    ) external view override returns (bytes32) {
        return _registeredChains[index];
    }

    /**
     * @notice Returns the number of registered remote chains
     * @return Number of registered chains
     */
    function getRegisteredChainsLength() external view override returns (uint256) {
        return _registeredChains.length;
    }

    /**
     * @notice Returns the address of the contract on a remote chain
     * @param remoteBlockchainID The blockchain ID of the remote chain
     * @return The address of the contract on the remote chain
     */
    function getRemoteContract(
        bytes32 remoteBlockchainID
    ) external view override returns (address) {
        return _remoteContracts[remoteBlockchainID];
    }

    /**
     * @notice Returns the blockchain ID of the remote chain where a token currently exists
     * @dev Returns bytes32(0) if the token is on the current chain
     * @param tokenId The ID of the token
     * @return The blockchain ID of the chain where the token currently exists
     */
    function getTokenLocation(
        uint256 tokenId
    ) external view override returns (bytes32) {
        return _tokenLocation[tokenId];
    }

    /**
     * @notice Returns the address of the existing ERC721 token contract being adapted
     * @return The address of the ERC721 token contract that this adapter interacts with
     */
    function getToken() external view override returns (address) {
        return _token;
    }

    /**
     * @notice Sets the expected remote contract address for a chain
     * @dev Can only be called by the contract owner. Set to address(0) to remove permissions.
     * @param remoteBlockchainID The blockchain ID of the remote chain
     * @param expectedRemoteAddress The expected address of the remote contract
     */
    function setExpectedRemoteContract(bytes32 remoteBlockchainID, address expectedRemoteAddress) external {
        _checkTeleporterRegistryAppAccess();
        require(remoteBlockchainID != bytes32(0), "ERC721TokenHome: invalid remote blockchain ID");
        require(remoteBlockchainID != _blockchainID, "ERC721TokenHome: cannot set same chain");
        require(_remoteContracts[remoteBlockchainID] == address(0), "ERC721TokenHome: chain already registered");

        _expectedRemoteContracts[remoteBlockchainID] = expectedRemoteAddress;
        emit RemoteChainExpectedContractSet(remoteBlockchainID, expectedRemoteAddress);
    }

    /**
     * @notice Returns the expected remote contract address for a chain
     * @param remoteBlockchainID The blockchain ID of the remote chain
     * @return The expected remote contract address
     */
    function getExpectedRemoteContract(bytes32 remoteBlockchainID) external view returns (address) {
        return _expectedRemoteContracts[remoteBlockchainID];
    }

    /**
     * @notice Sends a token to a recipient on another chain
     * @dev The token is transferred to this contract, and a message is sent to the destination chain
     * @param input Parameters for the cross-chain token transfer
     * @param tokenIds The IDs of the tokens to send
     */
    function send(SendTokenInput calldata input, uint256[] calldata tokenIds) external {
        _send(input, tokenIds);
    }

    /**
     * @notice Sends a token to a contract on another chain and executes a function on that contract
     * @dev The token is transferred to this contract, and a message is sent to the destination chain
     * @dev If the contract call fails, the token is sent to the fallback recipient
     * @param input Parameters for the cross-chain token transfer and contract call
     * @param tokenIds The IDs of the tokens to send
     */
    function sendAndCall(SendAndCallInput calldata input, uint256[] calldata tokenIds) external {
        _sendAndCall(input, tokenIds);
    }

    /**
     * @dev See {ERC721TokenHome-send}
     */
    function _send(SendTokenInput calldata input, uint256[] calldata tokenIds) internal nonReentrant {
        _validateSendTokenInput(input);

        bytes[] memory tokenMetadata =
            _transferIn(tokenIds, TransferrerMessageType.SINGLE_HOP_SEND, input.destinationBlockchainID);

        _handleFees(input.primaryFeeTokenAddress, input.primaryFee);
        TransferrerMessage memory message = TransferrerMessage({
            messageType: TransferrerMessageType.SINGLE_HOP_SEND,
            payload: abi.encode(
                SendTokenMessage({recipient: input.recipient, tokenIds: tokenIds, tokenMetadata: tokenMetadata})
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

        emit TokensSent(messageID, _msgSender(), tokenIds);
    }

    /**
     * @dev See {ERC721TokenHome-sendAndCall}
     */
    function _sendAndCall(SendAndCallInput calldata input, uint256[] calldata tokenIds) internal nonReentrant {
        _validateSendAndCallInput(input);

        bytes[] memory tokenMetadata =
            _transferIn(tokenIds, TransferrerMessageType.SINGLE_HOP_CALL, input.destinationBlockchainID);

        SendAndCallMessage memory message = SendAndCallMessage({
            tokenIds: tokenIds,
            originSenderAddress: _msgSender(),
            recipientContract: input.recipientContract,
            recipientPayload: input.recipientPayload,
            recipientGasLimit: input.recipientGasLimit,
            fallbackRecipient: input.fallbackRecipient,
            tokenMetadata: tokenMetadata
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

        emit TokensAndCallSent(messageID, _msgSender(), tokenIds);
    }

    /**
     * @notice Transfers tokens from sender to this contract and prepares metadata for cross-chain transfer
     * @dev Verifies the caller is the token owner, transfers tokens to this contract, and updates token location
     * @param tokenIds The IDs of the tokens to transfer
     * @param messageType The type of transfer message being prepared
     * @param destinationBlockchainID The blockchain ID of the destination chain
     * @return tokenMetadata The prepared metadata for each token
     */
    function _transferIn(
        uint256[] memory tokenIds,
        TransferrerMessageType messageType,
        bytes32 destinationBlockchainID
    ) internal returns (bytes[] memory tokenMetadata) {
        tokenMetadata = new bytes[](tokenIds.length);
        for (uint256 i = 0; i < tokenIds.length; ++i) {
            uint256 tokenId = tokenIds[i];
            address tokenOwner = IERC721(_token).ownerOf(tokenId);
            require(tokenOwner == _msgSender(), "ERC721TokenHome: token not owned by sender");
            tokenMetadata[i] = _prepareTokenMetadata(tokenId, messageType);
            _tokenLocation[tokenId] = destinationBlockchainID;
            IERC721(_token).transferFrom(tokenOwner, address(this), tokenId);
        }
    }

    /**
     * @notice Prepares token metadata for cross-chain transfer
     * @dev Must be implemented by derived contracts to create appropriate metadata for tokens
     * @param tokenId The ID of the token to prepare metadata for
     * @param messageType The type of transfer message being prepared
     * @return The encoded token metadata
     */
    function _prepareTokenMetadata(
        uint256 tokenId,
        TransferrerMessageType messageType
    ) internal view virtual returns (bytes memory);

    /**
     * @notice Validates the input parameters for a basic token send
     * @param input The input parameters to validate
     */
    function _validateSendTokenInput(
        SendTokenInput memory input
    ) internal view {
        require(input.destinationBlockchainID != bytes32(0), "ERC721TokenHome: invalid destination blockchain ID");
        address remoteContract = _remoteContracts[input.destinationBlockchainID];
        require(remoteContract != address(0), "ERC721TokenHome: destination chain not registered");
        require(
            remoteContract == input.destinationTokenTransferrerAddress,
            "ERC721TokenHome: invalid destination token transferrer address"
        );
        require(input.recipient != address(0), "ERC721TokenHome: invalid recipient");
    }

    /**
     * @notice Validates the input parameters for a send and call operation
     * @param input The input parameters to validate
     */
    function _validateSendAndCallInput(
        SendAndCallInput memory input
    ) internal view {
        require(input.destinationBlockchainID != bytes32(0), "ERC721TokenHome: invalid destination blockchain ID");
        address remoteContract = _remoteContracts[input.destinationBlockchainID];
        require(remoteContract != address(0), "ERC721TokenHome: destination chain not registered");
        require(
            remoteContract == input.destinationTokenTransferrerAddress,
            "ERC721TokenHome: invalid destination token transferrer address"
        );
        require(input.recipientContract != address(0), "ERC721TokenHome: invalid recipient contract");
        require(input.fallbackRecipient != address(0), "ERC721TokenHome: invalid fallback recipient");
        require(input.requiredGasLimit > 0, "ERC721TokenHome: invalid required gas limit");
        require(input.recipientGasLimit > 0, "ERC721TokenHome: invalid recipient gas limit");
        require(input.recipientGasLimit < input.requiredGasLimit, "ERC721TokenHome: invalid recipient gas limit");
    }

    /**
     * @notice Registers a remote contract on another chain
     * @dev Can only be called internally, triggered by receiving a register message from a remote chain
     * @param remoteBlockchainID The blockchain ID of the remote chain
     * @param remoteNftTransferrerAddress The address of the contract on the remote chain
     */
    function _registerRemote(bytes32 remoteBlockchainID, address remoteNftTransferrerAddress) internal {
        require(remoteBlockchainID != bytes32(0), "ERC721TokenHome: invalid remote blockchain ID");
        require(remoteBlockchainID != _blockchainID, "ERC721TokenHome: cannot register remote on same chain");
        require(remoteNftTransferrerAddress != address(0), "ERC721TokenHome: invalid remote token transferrer address");
        require(_remoteContracts[remoteBlockchainID] == address(0), "ERC721TokenHome: remote already registered");
        require(
            remoteNftTransferrerAddress == _expectedRemoteContracts[remoteBlockchainID],
            "ERC721TokenHome: unexpected remote contract address"
        );

        _remoteContracts[remoteBlockchainID] = remoteNftTransferrerAddress;
        _registeredChains.push(remoteBlockchainID);

        emit RemoteChainRegistered(remoteBlockchainID, remoteNftTransferrerAddress);
    }

    /**
     * @notice Handles the send and call operation when receiving tokens from another chain
     * @dev Approves the recipient contract to use the tokens, then calls it with the specified payload
     * @dev If the call fails or the tokens are still owned by this contract, transfers them to the fallback recipient
     * @param message The message containing the send and call details
     * @param sourceBlockchainID The blockchain ID of the source chain
     * @param originSenderAddress The address of the sender contract on the source chain
     * @param tokenIds The IDs of the tokens being transferred
     */
    function _handleSendAndCall(
        SendAndCallMessage memory message,
        bytes32 sourceBlockchainID,
        address originSenderAddress,
        uint256[] memory tokenIds
    ) internal {
        bytes memory payload = abi.encodeCall(
            IERC721SendAndCallReceiver.receiveTokens,
            (
                sourceBlockchainID,
                originSenderAddress,
                message.originSenderAddress,
                _token,
                tokenIds,
                message.recipientPayload
            )
        );

        for (uint256 i = 0; i < tokenIds.length; ++i) {
            uint256 tokenId = tokenIds[i];
            IERC721(_token).approve(message.recipientContract, tokenId);
        }
        bool success = CallUtils._callWithExactGas(message.recipientGasLimit, message.recipientContract, payload);
        if (success) {
            emit CallSucceeded(message.recipientContract, tokenIds);
        } else {
            emit CallFailed(message.recipientContract, tokenIds);
        }

        for (uint256 i = 0; i < tokenIds.length; ++i) {
            uint256 tokenId = tokenIds[i];
            if (IERC721(_token).ownerOf(tokenId) == address(this)) {
                IERC721(_token).transferFrom(address(this), message.fallbackRecipient, tokenId);
            }
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

    /**
     * @notice Validates that a token being received is coming from the chain it was previously sent to
     * @param sourceBlockchainID The blockchain ID of the source chain
     * @param originSenderAddress The address of the sender contract on the source chain
     * @param tokenId The ID of the token being received
     */
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
            for (uint256 i = 0; i < sendTokenMessage.tokenIds.length; ++i) {
                _validateReceiveToken(sourceBlockchainID, originSenderAddress, sendTokenMessage.tokenIds[i]);
                _tokenLocation[sendTokenMessage.tokenIds[i]] = bytes32(0);
                IERC721(_token).safeTransferFrom(
                    address(this), sendTokenMessage.recipient, sendTokenMessage.tokenIds[i]
                );
            }
        } else if (transferrerMessage.messageType == TransferrerMessageType.SINGLE_HOP_CALL) {
            SendAndCallMessage memory sendAndCallMessage = abi.decode(transferrerMessage.payload, (SendAndCallMessage));
            for (uint256 i = 0; i < sendAndCallMessage.tokenIds.length; ++i) {
                _validateReceiveToken(sourceBlockchainID, originSenderAddress, sendAndCallMessage.tokenIds[i]);
                _tokenLocation[sendAndCallMessage.tokenIds[i]] = bytes32(0);
            }
            _handleSendAndCall(sendAndCallMessage, sourceBlockchainID, originSenderAddress, sendAndCallMessage.tokenIds);
        }
    }
}
