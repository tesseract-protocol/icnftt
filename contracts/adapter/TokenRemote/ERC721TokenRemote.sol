// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {IERC721TokenRemote} from "./interfaces/IERC721TokenRemote.sol";
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
import {IERC721SendAndCallReceiver} from "../interfaces/IERC721SendAndCallReceiver.sol";
import {TeleporterRegistryOwnableApp} from "@teleporter/registry/TeleporterRegistryOwnableApp.sol";
import {TeleporterMessageInput, TeleporterFeeInfo} from "@teleporter/ITeleporterMessenger.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CallUtils} from "@utilities/CallUtils.sol";
import {SafeERC20TransferFrom} from "@utilities/SafeERC20TransferFrom.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/**
 * @title ERC721TokenRemote
 * @dev A contract that represents ERC721 tokens on a remote Avalanche L1 chain.
 *
 * This contract serves as a "remote" representation for ERC721 tokens that are native to another chain.
 * It works in conjunction with a home contract to enable cross-chain token transfers using Avalanche's
 * Interchain Messaging (ICM) via Teleporter.
 *
 * Key features:
 * 1. Mints tokens when they are received from the home chain
 * 2. Burns tokens when they are sent back to the home chain
 * 3. Supports both basic transfers and send-and-call operations
 * 4. Maintains a connection with a single home chain where the tokens originate
 *
 * The contract must be registered with its corresponding home contract before it can be used.
 */
abstract contract ERC721TokenRemote is
    ERC721,
    IERC721TokenRemote,
    ERC721TokenTransferrer,
    TeleporterRegistryOwnableApp
{
    /// @notice Gas limit required for registering with the home contract
    uint256 public constant REGISTER_REMOTE_REQUIRED_GAS = 130_000;

    /// @notice The blockchain ID of the home chain where the original tokens exist
    bytes32 internal immutable _homeBlockchainID;

    /// @notice The address of the token contract on the home chain
    address internal immutable _homeContractAddress;

    /// @notice Whether this contract has been registered with the home contract
    bool internal _isRegistered;

    /**
     * @notice Initializes the ERC721TokenRemote contract
     * @param name The name of the ERC721 token
     * @param symbol The symbol of the ERC721 token
     * @param homeBlockchainID The blockchain ID of the home chain
     * @param homeContractAddress The address of the home contract
     * @param teleporterRegistryAddress The address of the Teleporter registry
     * @param teleporterManager The address of the Teleporter manager that will be responsible for managing cross-chain messages
     * @param minTeleporterVersion The minimum required Teleporter version
     */
    constructor(
        string memory name,
        string memory symbol,
        bytes32 homeBlockchainID,
        address homeContractAddress,
        address teleporterRegistryAddress,
        address teleporterManager,
        uint256 minTeleporterVersion
    )
        ERC721(name, symbol)
        TeleporterRegistryOwnableApp(teleporterRegistryAddress, teleporterManager, minTeleporterVersion)
    {
        require(homeBlockchainID != bytes32(0), "ERC721TokenRemote: invalid home blockchain ID");
        require(homeContractAddress != address(0), "ERC721TokenRemote: invalid home contract address");

        _homeBlockchainID = homeBlockchainID;
        _homeContractAddress = homeContractAddress;

        emit ERC721TokenRemoteInitialized(_homeBlockchainID, _homeContractAddress);
    }

    /**
     * @notice Sends a token back to the home chain
     * @dev Burns the token on this chain and sends a message to the home chain
     * @param input Parameters for the cross-chain token transfer
     * @param tokenIds The IDs of the tokens to send
     */
    function send(
        SendTokenInput calldata input,
        uint256[] calldata tokenIds
    ) external override {
        require(tokenIds.length > 0, "ERC721TokenRemote: empty token array");
        _send(input, tokenIds);
    }

    /**
     * @notice Sends a token to a contract on the home chain and calls a function on it
     * @dev Burns the token on this chain and sends a message to the home chain
     * @param input Parameters for the cross-chain token transfer and contract call
     * @param tokenIds The IDs of the tokens to send
     */
    function sendAndCall(
        SendAndCallInput calldata input,
        uint256[] calldata tokenIds
    ) external override {
        require(tokenIds.length > 0, "ERC721TokenRemote: empty token array");
        _sendAndCall(input, tokenIds);
    }

    /**
     * @notice Registers this contract with the home contract
     * @dev Sends a registration message to the home contract
     * @param feeInfo Information about the fee to pay for the cross-chain message
     */
    function registerWithHome(
        TeleporterFeeInfo calldata feeInfo
    ) external override {
        require(!_isRegistered, "ERC721TokenRemote: already registered");

        TransferrerMessage memory message =
            TransferrerMessage({messageType: TransferrerMessageType.REGISTER_REMOTE, payload: bytes("")});

        _handleFees(feeInfo.feeTokenAddress, feeInfo.amount);

        bytes32 messageID = _sendTeleporterMessage(
            TeleporterMessageInput({
                destinationBlockchainID: _homeBlockchainID,
                destinationAddress: _homeContractAddress,
                feeInfo: feeInfo,
                requiredGasLimit: REGISTER_REMOTE_REQUIRED_GAS,
                allowedRelayerAddresses: new address[](0),
                message: abi.encode(message)
            })
        );

        emit RegisterWithHome(messageID, _homeBlockchainID, _homeContractAddress);
    }

    /**
     * @notice Returns the blockchain ID of the home chain
     * @return The home chain's blockchain ID
     */
    function getHomeBlockchainID() external view override returns (bytes32) {
        return _homeBlockchainID;
    }

    /**
     * @notice Returns the address of the token contract on the home chain
     * @return The home contract address
     */
    function getHomeTokenAddress() external view override returns (address) {
        return _homeContractAddress;
    }

    /**
     * @notice Returns whether this contract has been registered with the home contract
     * @return Registration status
     */
    function getIsRegistered() external view override returns (bool) {
        return _isRegistered;
    }

    /**
     * @notice Hook that is called before token transfers
     * @dev Can be overridden by derived contracts to implement custom behavior
     * @param to The recipient address
     * @param tokenId The ID of the token being transferred
     */
    function _beforeTokenTransfer(
        address to,
        uint256 tokenId
    ) internal virtual {}

    /**
     * @notice Hook that is called after token transfers
     * @dev Can be overridden by derived contracts to implement custom behavior
     * @param from The sender address
     * @param to The recipient address
     * @param tokenId The ID of the token being transferred
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual {}

    /**
     * @notice Processes token metadata received from the home chain
     * @dev Must be implemented by derived contracts to handle token-specific metadata
     * @param tokenId The ID of the token to update
     * @param metadata The metadata received from the home chain
     */
    function _processTokenMetadata(
        uint256 tokenId,
        bytes memory metadata
    ) internal virtual;

    /**
     * @notice Updates token ownership and calls lifecycle hooks
     * @dev Overrides ERC721._update to add custom behavior
     * @param to The recipient address
     * @param tokenId The ID of the token being transferred
     * @param auth The authorized address for the transfer
     * @return The previous owner address
     */
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal virtual override returns (address) {
        _beforeTokenTransfer(to, tokenId);
        address from = super._update(to, tokenId, auth);
        _afterTokenTransfer(from, to, tokenId);
        return from;
    }

    /**
     * @dev See {ERC721TokenRemote-send}
     */
    function _send(
        SendTokenInput calldata input,
        uint256[] calldata tokenIds
    ) internal nonReentrant {
        _validateSendTokenInput(input);
        _transferInAndBurn(tokenIds);

        TransferrerMessage memory message = TransferrerMessage({
            messageType: TransferrerMessageType.SINGLE_HOP_SEND,
            payload: abi.encode(
                SendTokenMessage({recipient: input.recipient, tokenIds: tokenIds, tokenMetadata: new bytes[](0)})
            )
        });

        _handleFees(input.primaryFeeTokenAddress, input.primaryFee);

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
     * @dev See {ERC721TokenRemote-sendAndCall}
     */
    function _sendAndCall(
        SendAndCallInput calldata input,
        uint256[] calldata tokenIds
    ) internal nonReentrant {
        _validateSendAndCallInput(input);
        _transferInAndBurn(tokenIds);

        SendAndCallMessage memory callMessage = SendAndCallMessage({
            recipientContract: input.recipientContract,
            tokenIds: tokenIds,
            originSenderAddress: _msgSender(),
            recipientPayload: input.recipientPayload,
            recipientGasLimit: input.recipientGasLimit,
            fallbackRecipient: input.fallbackRecipient,
            tokenMetadata: new bytes[](0)
        });

        TransferrerMessage memory message =
            TransferrerMessage({messageType: TransferrerMessageType.SINGLE_HOP_CALL, payload: abi.encode(callMessage)});

        _handleFees(input.primaryFeeTokenAddress, input.primaryFee);

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

        emit TokensAndCallSent(messageID, _msgSender(), tokenIds);
    }

    /**
     * @notice Transfers tokens from owner to this contract and burns them
     * @dev Verifies the caller is the token owner, transfers the tokens, and burns them
     * @param tokenIds The IDs of the tokens to burn
     */
    function _transferInAndBurn(
        uint256[] memory tokenIds
    ) internal {
        for (uint256 i; i < tokenIds.length; ++i) {
            uint256 tokenId = tokenIds[i];
            address tokenOwner = ownerOf(tokenId);
            require(tokenOwner == _msgSender(), "ERC721TokenRemote: token not owned by sender");
            transferFrom(tokenOwner, address(this), tokenId);
            _burn(tokenId);
            emit TokenBurned(tokenId, tokenOwner);
        }
    }

    /**
     * @notice Processes a send and call message by minting the NFT and calling the recipient contract
     * @dev Mints the token, calls the recipient contract, and handles any failures by sending to fallback
     * @param message The send and call message containing the details of the operation
     * @param tokenIds The IDs of the tokens being transferred
     */
    function _handleSendAndCall(
        SendAndCallMessage memory message,
        uint256[] memory tokenIds
    ) internal {
        bytes memory payload = abi.encodeCall(
            IERC721SendAndCallReceiver.receiveTokens,
            (
                _homeBlockchainID,
                _homeContractAddress,
                message.originSenderAddress,
                address(this),
                tokenIds,
                message.recipientPayload
            )
        );

        for (uint256 i; i < tokenIds.length; ++i) {
            _approve(message.recipientContract, tokenIds[i], address(this));
        }
        bool success = CallUtils._callWithExactGas(message.recipientGasLimit, message.recipientContract, payload);

        if (success) {
            emit CallSucceeded(message.recipientContract, tokenIds);
        } else {
            emit CallFailed(message.recipientContract, tokenIds);
        }

        for (uint256 i; i < tokenIds.length; ++i) {
            if (ownerOf(tokenIds[i]) == address(this)) {
                _transfer(address(this), message.fallbackRecipient, tokenIds[i]);
            }
        }
    }

    /**
     * @notice Mints a token received from the home chain to a recipient
     * @dev Internal function called when a token is received from the home chain
     * @param tokenId The ID of the token to mint
     * @param recipient The address to mint the token to
     * @param metadata The token metadata sent from the home chain
     */
    function _receiveToken(
        uint256 tokenId,
        address recipient,
        bytes memory metadata
    ) internal {
        _mint(recipient, tokenId);
        _processTokenMetadata(tokenId, metadata);
        emit TokenMinted(tokenId, recipient);
    }

    /**
     * @notice Handles the collection of fees for cross-chain operations
     * @dev Transfers the fee token from the sender to this contract
     * @param feeTokenAddress The address of the token used for fees
     * @param feeAmount The amount of the fee
     */
    function _handleFees(
        address feeTokenAddress,
        uint256 feeAmount
    ) internal {
        if (feeAmount == 0) {
            return;
        }
        SafeERC20TransferFrom.safeTransferFrom(IERC20(feeTokenAddress), _msgSender(), feeAmount);
    }

    /**
     * @notice Processes incoming Teleporter messages from the home chain
     * @dev Handles different message types including token transfers and send-and-call operations
     * @param sourceBlockchainID The blockchain ID of the source chain
     * @param originSenderAddress The address of the sender on the source chain
     * @param message The encoded message
     */
    function _receiveTeleporterMessage(
        bytes32 sourceBlockchainID,
        address originSenderAddress,
        bytes memory message
    ) internal virtual override {
        require(sourceBlockchainID == _homeBlockchainID, "ERC721TokenRemote: invalid source blockchain");
        require(originSenderAddress == _homeContractAddress, "ERC721TokenRemote: invalid origin sender");

        TransferrerMessage memory transferrerMessage = abi.decode(message, (TransferrerMessage));

        if (!_isRegistered) {
            _isRegistered = true;
            emit HomeChainRegistered(_homeBlockchainID, _homeContractAddress);
        }

        if (transferrerMessage.messageType == TransferrerMessageType.SINGLE_HOP_SEND) {
            SendTokenMessage memory sendTokenMessage = abi.decode(transferrerMessage.payload, (SendTokenMessage));
            for (uint256 i; i < sendTokenMessage.tokenIds.length; ++i) {
                _receiveToken(
                    sendTokenMessage.tokenIds[i], sendTokenMessage.recipient, sendTokenMessage.tokenMetadata[i]
                );
            }
        } else if (transferrerMessage.messageType == TransferrerMessageType.SINGLE_HOP_CALL) {
            SendAndCallMessage memory sendAndCallMessage = abi.decode(transferrerMessage.payload, (SendAndCallMessage));
            for (uint256 i; i < sendAndCallMessage.tokenIds.length; ++i) {
                _receiveToken(sendAndCallMessage.tokenIds[i], address(this), sendAndCallMessage.tokenMetadata[i]);
            }
            _handleSendAndCall(sendAndCallMessage, sendAndCallMessage.tokenIds);
        }
    }

    /**
     * @notice Validates input parameters for basic token send operations
     * @dev Ensures destination is the home chain and contract is registered
     * @param input The input parameters to validate
     */
    function _validateSendTokenInput(
        SendTokenInput memory input
    ) internal view {
        require(input.destinationBlockchainID == _homeBlockchainID, "ERC721TokenRemote: can only send to home chain");
        require(
            input.destinationTokenTransferrerAddress == _homeContractAddress,
            "ERC721TokenRemote: can only send to home contract"
        );
        require(_isRegistered, "ERC721TokenRemote: not registered");
    }

    /**
     * @notice Validates input parameters for send-and-call operations
     * @dev Ensures destination is the home chain, recipient addresses are valid, and gas limits are appropriate
     * @param input The input parameters to validate
     */
    function _validateSendAndCallInput(
        SendAndCallInput memory input
    ) internal view {
        require(input.destinationBlockchainID == _homeBlockchainID, "ERC721TokenRemote: can only send to home chain");
        require(
            input.destinationTokenTransferrerAddress == _homeContractAddress,
            "ERC721TokenRemote: can only send to home contract"
        );
        require(_isRegistered, "ERC721TokenRemote: not registered");
        require(input.recipientContract != address(0), "ERC721TokenRemote: invalid recipient contract address");
        require(input.fallbackRecipient != address(0), "ERC721TokenRemote: invalid fallback recipient address");
        require(input.requiredGasLimit > 0, "ERC721TokenRemote: invalid required gas limit");
        require(input.recipientGasLimit > 0, "ERC721TokenRemote: invalid recipient gas limit");
        require(input.recipientGasLimit < input.requiredGasLimit, "ERC721TokenRemote: recipient gas limit too high");
    }
}
