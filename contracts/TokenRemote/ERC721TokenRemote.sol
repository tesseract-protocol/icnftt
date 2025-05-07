// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC721TokenRemote} from "./interfaces/IERC721TokenRemote.sol";
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
    ExtensionMessage,
    ExtensionMessageParams
} from "../interfaces/IERC721Transferrer.sol";
import {ERC721TokenTransferrer} from "../ERC721TokenTransferrer.sol";
import {IERC721SendAndCallReceiver} from "../interfaces/IERC721SendAndCallReceiver.sol";
import {TeleporterRegistryOwnableApp} from "@teleporter/registry/TeleporterRegistryOwnableApp.sol";
import {TeleporterMessageInput, TeleporterFeeInfo} from "@teleporter/ITeleporterMessenger.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {CallUtils} from "@utilities/CallUtils.sol";
import {SafeERC20TransferFrom} from "@utilities/SafeERC20TransferFrom.sol";

/**
 * @title ERC721TokenRemote
 * @dev A contract that represents ERC721 tokens on a remote Avalanche L1 chain.
 *
 * This contract serves as a "remote" representation for ERC721 tokens that are native to another chain.
 * It works in conjunction with ERC721TokenHome to enable cross-chain token transfers using Avalanche's
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
abstract contract ERC721TokenRemote is IERC721TokenRemote, ERC721TokenTransferrer, TeleporterRegistryOwnableApp {
    /// @notice The blockchain ID of the home chain where the original tokens exist
    bytes32 internal immutable _homeBlockchainID;

    /// @notice The address of the token contract on the home chain
    address internal immutable _homeContractAddress;

    /// @notice Gas limit required for registering with the home contract
    uint256 public constant REGISTER_REMOTE_REQUIRED_GAS = 130_000;

    /// @notice Whether this contract has been registered with the home contract
    bool internal _isRegistered;

    /**
     * @notice Initializes the ERC721TokenRemote contract
     * @param name The name of the ERC721 token
     * @param symbol The symbol of the ERC721 token
     * @param homeChainId_ The blockchain ID of the home chain
     * @param homeContractAddress_ The address of the home contract
     * @param teleporterRegistryAddress The address of the Teleporter registry
     * @param minTeleporterVersion The minimum required Teleporter version
     */
    constructor(
        string memory name,
        string memory symbol,
        bytes32 homeChainId_,
        address homeContractAddress_,
        address teleporterRegistryAddress,
        uint256 minTeleporterVersion
    )
        ERC721TokenTransferrer(name, symbol, "")
        TeleporterRegistryOwnableApp(teleporterRegistryAddress, msg.sender, minTeleporterVersion)
    {
        require(homeChainId_ != bytes32(0), "ERC721TokenRemote: zero home blockchain ID");
        require(homeContractAddress_ != address(0), "ERC721TokenRemote: zero home contract address");

        _homeBlockchainID = homeChainId_;
        _homeContractAddress = homeContractAddress_;

        emit HomeChainRegistered(_homeBlockchainID, _homeContractAddress);
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
     * @notice Sends a token back to the home chain
     * @dev Burns the token on this chain and sends a message to the home chain
     * @param input Parameters for the cross-chain token transfer
     * @param tokenId The ID of the token to send
     */
    function send(SendTokenInput calldata input, uint256 tokenId) external override {
        require(input.destinationBlockchainID == _homeBlockchainID, "ERC721TokenRemote: can only send to home chain");
        require(
            input.destinationTokenTransferrerAddress == _homeContractAddress,
            "ERC721TokenRemote: can only send to home contract"
        );
        require(_isRegistered, "ERC721TokenRemote: not registered");

        address tokenOwner = ownerOf(tokenId);
        transferFrom(tokenOwner, address(this), tokenId);

        TransferrerMessage memory message = TransferrerMessage({
            messageType: TransferrerMessageType.SINGLE_HOP_SEND,
            payload: abi.encode(
                SendTokenMessage({recipient: input.recipient, tokenId: tokenId, extensions: new ExtensionMessage[](0)})
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

        _burn(tokenId);

        emit TokenBurned(tokenId, tokenOwner);
        emit TokenSent(messageID, msg.sender, tokenId);
    }

    /**
     * @notice Sends a token to a contract on the home chain and calls a function on it
     * @dev Burns the token on this chain and sends a message to the home chain
     * @param input Parameters for the cross-chain token transfer and contract call
     * @param tokenId The ID of the token to send
     */
    function sendAndCall(SendAndCallInput calldata input, uint256 tokenId) external override {
        require(input.destinationBlockchainID == _homeBlockchainID, "ERC721TokenRemote: can only send to home chain");
        require(
            input.destinationTokenTransferrerAddress == _homeContractAddress,
            "ERC721TokenRemote: can only send to home contract"
        );
        require(_isRegistered, "ERC721TokenRemote: not registered");
        require(input.recipientContract != address(0), "ERC721TokenRemote: zero recipient contract address");
        require(input.fallbackRecipient != address(0), "ERC721TokenRemote: zero fallback recipient address");
        require(input.requiredGasLimit > 0, "ERC721TokenRemote: zero required gas limit");
        require(input.recipientGasLimit > 0, "ERC721TokenRemote: zero recipient gas limit");
        require(input.recipientGasLimit < input.requiredGasLimit, "ERC721TokenRemote: recipient gas limit too high");

        address tokenOwner = ownerOf(tokenId);
        transferFrom(tokenOwner, address(this), tokenId);

        SendAndCallMessage memory callMessage = SendAndCallMessage({
            recipientContract: input.recipientContract,
            tokenId: tokenId,
            originSenderAddress: msg.sender,
            recipientPayload: input.recipientPayload,
            recipientGasLimit: input.recipientGasLimit,
            fallbackRecipient: input.fallbackRecipient,
            extensions: new ExtensionMessage[](0)
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

        _burn(tokenId);

        emit TokenBurned(tokenId, tokenOwner);
        emit TokenAndCallSent(messageID, msg.sender, tokenId);
    }

    /**
     * @notice Processes a send and call message by minting the NFT and calling the recipient contract
     * @dev Mints the token, calls the recipient contract, and handles any failures by sending to fallback
     * @param message The send and call message containing the details of the operation
     * @param tokenId The ID of the token being transferred
     */
    function _handleSendAndCall(SendAndCallMessage memory message, uint256 tokenId) internal {
        bytes memory payload = abi.encodeCall(
            IERC721SendAndCallReceiver.receiveToken,
            (
                _homeBlockchainID,
                _homeContractAddress,
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
     * @notice Updates contract extensions based on received extension messages
     * @dev Must be implemented by derived contracts to update extension-specific state
     * @param extensions Array of extension messages to process
     */
    function _updateExtensions(
        ExtensionMessage[] memory extensions
    ) internal virtual;

    /**
     * @notice Registers this contract with the home contract
     * @dev Sends a registration message to the home contract
     * @param feeInfo Information about the fee to pay for the cross-chain message
     */
    function registerWithHome(
        TeleporterFeeInfo calldata feeInfo
    ) external virtual {
        require(!_isRegistered, "ERC721TokenRemote: already registered");

        TransferrerMessage memory message =
            TransferrerMessage({messageType: TransferrerMessageType.REGISTER_REMOTE, payload: bytes("")});

        _handleFees(feeInfo.feeTokenAddress, feeInfo.amount);

        _sendTeleporterMessage(
            TeleporterMessageInput({
                destinationBlockchainID: _homeBlockchainID,
                destinationAddress: _homeContractAddress,
                feeInfo: feeInfo,
                requiredGasLimit: REGISTER_REMOTE_REQUIRED_GAS,
                allowedRelayerAddresses: new address[](0),
                message: abi.encode(message)
            })
        );
    }

    /**
     * @notice Mints a token received from the home chain to a recipient
     * @dev Internal function called when a token is received from the home chain
     * @param tokenId The ID of the token to mint
     * @param recipient The address to mint the token to
     */
    function _receiveToken(uint256 tokenId, address recipient, ExtensionMessage[] memory extensions) internal {
        _mint(recipient, tokenId);
        _updateExtensions(extensions);
        emit TokenMinted(tokenId, recipient);
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
     * @notice Processes incoming Teleporter messages from the home chain
     * @dev Handles different message types including token transfers, send-and-call operations, and URI updates
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
        }

        if (transferrerMessage.messageType == TransferrerMessageType.SINGLE_HOP_SEND) {
            SendTokenMessage memory sendTokenMessage = abi.decode(transferrerMessage.payload, (SendTokenMessage));
            _receiveToken(sendTokenMessage.tokenId, sendTokenMessage.recipient, sendTokenMessage.extensions);
        } else if (transferrerMessage.messageType == TransferrerMessageType.SINGLE_HOP_CALL) {
            SendAndCallMessage memory sendAndCallMessage = abi.decode(transferrerMessage.payload, (SendAndCallMessage));
            _receiveToken(sendAndCallMessage.tokenId, address(this), sendAndCallMessage.extensions);
            _handleSendAndCall(sendAndCallMessage, sendAndCallMessage.tokenId);
        } else if (transferrerMessage.messageType == TransferrerMessageType.UPDATE_REMOTE_BASE_URI) {
            UpdateRemoteBaseURIMessage memory updateRemoteBaseURIMessage =
                abi.decode(transferrerMessage.payload, (UpdateRemoteBaseURIMessage));
            _baseURIStorage = updateRemoteBaseURIMessage.baseURI;
            emit RemoteBaseURIUpdated(_baseURIStorage);
        } else if (transferrerMessage.messageType == TransferrerMessageType.UPDATE_EXTENSIONS) {
            ExtensionMessage[] memory extensions = abi.decode(transferrerMessage.payload, (ExtensionMessage[]));
            _updateExtensions(extensions);
        }
    }
}
