// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {
    TeleporterFeeInfo,
    TeleporterMessageInput,
    TeleporterMessage,
    TeleporterMessageReceipt
} from "@teleporter/ITeleporterMessenger.sol";

// Mock of IWarpMessenger to return chain IDs
contract MockWarpMessenger {
    bytes32 private _blockchainId;

    constructor(
        bytes32 blockchainId
    ) {
        _blockchainId = blockchainId;
    }

    /// forge-lint: disable-next-item(mixed-case-function)
    function getBlockchainID() external view returns (bytes32) {
        return _blockchainId;
    }
}

// Mock TeleporterRegistry to simulate the registry functionality
contract MockTeleporterRegistry {
    address private _owner;
    address private _latestTeleporter;

    constructor(
        address mockTeleporter
    ) {
        _owner = msg.sender;
        _latestTeleporter = mockTeleporter;
    }

    // Mock the necessary functions that our contracts will call
    function latestVersion() external pure returns (uint256) {
        return 1;
    }

    function getLatestTeleporter() external view returns (address) {
        return _latestTeleporter;
    }

    function getTeleporterAddress(
        uint256
    ) external view returns (address) {
        return _latestTeleporter;
    }

    function getVersionFromAddress(
        address
    ) external pure returns (uint256) {
        return 1;
    }

    function getMinTeleporterVersion() external pure returns (uint256) {
        return 1;
    }
}

// Mock Teleporter to simulate cross-chain message passing
contract MockTeleporterMessenger {
    // Events defined in ITeleporterMessenger
    /// forge-lint: disable-next-item(mixed-case-variable)
    event SendCrossChainMessage(
        bytes32 indexed messageId,
        bytes32 indexed destinationBlockchainID,
        TeleporterMessage message,
        TeleporterFeeInfo feeInfo
    );

    event ReceiveCrossChainMessage(
        bytes32 indexed messageId,
        bytes32 indexed sourceBlockchainId,
        address indexed deliverer,
        address rewardRedeemer,
        TeleporterMessage message
    );

    // Message structure for easier storage
    struct PendingMessage {
        address sender;
        bytes message;
        uint256 nonce;
    }

    // Chain IDs - from the test contract
    bytes32 public immutable HOME_CHAIN_ID;
    bytes32 public immutable REMOTE_CHAIN_ID;

    // Current message nonce
    uint256 private _messageNonce;

    // Simple queue of pending messages by destination
    mapping(bytes32 destinationChainId => mapping(address destinationAddress => PendingMessage[])) private
        _pendingMessages;

    constructor(
        bytes32 homeChainId,
        bytes32 remoteChainId
    ) {
        HOME_CHAIN_ID = homeChainId;
        REMOTE_CHAIN_ID = remoteChainId;
    }

    // Send a cross-chain message
    function sendCrossChainMessage(
        TeleporterMessageInput calldata messageInput
    ) external returns (bytes32) {
        // Generate a message ID based on current nonce
        bytes32 messageId =
            keccak256(abi.encodePacked(_messageNonce, HOME_CHAIN_ID, messageInput.destinationBlockchainID));

        // Create the TeleporterMessage
        TeleporterMessage memory message = TeleporterMessage({
            messageNonce: _messageNonce,
            originSenderAddress: msg.sender,
            destinationBlockchainID: messageInput.destinationBlockchainID,
            destinationAddress: messageInput.destinationAddress,
            requiredGasLimit: messageInput.requiredGasLimit,
            allowedRelayerAddresses: messageInput.allowedRelayerAddresses,
            receipts: new TeleporterMessageReceipt[](0),
            message: messageInput.message
        });

        // Store the message
        _pendingMessages[messageInput.destinationBlockchainID][messageInput.destinationAddress].push(
            PendingMessage({sender: msg.sender, message: messageInput.message, nonce: _messageNonce})
        );

        // Increment nonce for next message
        _messageNonce++;

        // Emit event for tracking
        emit SendCrossChainMessage(messageId, messageInput.destinationBlockchainID, message, messageInput.feeInfo);

        return messageId;
    }

    // Deliver the next pending message (FIFO - first in, first out)
    function deliverNextMessage(
        bytes32 destinationChainId,
        address destinationAddress
    ) external returns (bool) {
        PendingMessage[] storage messages = _pendingMessages[destinationChainId][destinationAddress];
        require(messages.length > 0, "No pending messages");

        // Get the oldest message
        PendingMessage memory pendingMsg = messages[0];

        // Remove it by shifting the array (simple queue)
        for (uint i = 0; i < messages.length - 1; i++) {
            messages[i] = messages[i + 1];
        }
        messages.pop();

        // Determine source chain based on message direction
        bytes32 sourceChainId = (destinationChainId == HOME_CHAIN_ID) ? REMOTE_CHAIN_ID : HOME_CHAIN_ID;

        // Create message ID for the event
        bytes32 messageId = keccak256(abi.encodePacked(pendingMsg.nonce, sourceChainId, destinationChainId));

        // Create TeleporterMessage for the event
        TeleporterMessage memory teleporterMessage = TeleporterMessage({
            messageNonce: pendingMsg.nonce,
            originSenderAddress: pendingMsg.sender,
            destinationBlockchainID: destinationChainId,
            destinationAddress: destinationAddress,
            requiredGasLimit: 200000, // Default value
            allowedRelayerAddresses: new address[](0),
            receipts: new TeleporterMessageReceipt[](0),
            message: pendingMsg.message
        });

        // Emit receive event
        emit ReceiveCrossChainMessage(
            messageId,
            sourceChainId,
            msg.sender, // deliverer
            msg.sender, // reward redeemer
            teleporterMessage
        );

        // Call the destination contract
        (bool success,) = destinationAddress.call(
            abi.encodeWithSignature(
                "receiveTeleporterMessage(bytes32,address,bytes)", sourceChainId, pendingMsg.sender, pendingMsg.message
            )
        );

        return success;
    }

    // Deliver the latest pending message (LIFO - last in, first out)
    function deliverLatestMessage(
        bytes32 destinationChainId,
        address destinationAddress
    ) external returns (bool) {
        PendingMessage[] storage messages = _pendingMessages[destinationChainId][destinationAddress];
        require(messages.length > 0, "No pending messages");

        // Get the newest message (last in queue)
        uint256 lastIndex = messages.length - 1;
        PendingMessage memory pendingMsg = messages[lastIndex];

        // Remove it (pop the last element)
        messages.pop();

        // Determine source chain based on message direction
        bytes32 sourceChainId = (destinationChainId == HOME_CHAIN_ID) ? REMOTE_CHAIN_ID : HOME_CHAIN_ID;

        // Create message ID for the event
        bytes32 messageId = keccak256(abi.encodePacked(pendingMsg.nonce, sourceChainId, destinationChainId));

        // Create TeleporterMessage for the event
        TeleporterMessage memory teleporterMessage = TeleporterMessage({
            messageNonce: pendingMsg.nonce,
            originSenderAddress: pendingMsg.sender,
            destinationBlockchainID: destinationChainId,
            destinationAddress: destinationAddress,
            requiredGasLimit: 200000, // Default value
            allowedRelayerAddresses: new address[](0),
            receipts: new TeleporterMessageReceipt[](0),
            message: pendingMsg.message
        });

        // Emit receive event
        emit ReceiveCrossChainMessage(
            messageId,
            sourceChainId,
            msg.sender, // deliverer
            msg.sender, // reward redeemer
            teleporterMessage
        );

        // Call the destination contract
        (bool success,) = destinationAddress.call(
            abi.encodeWithSignature(
                "receiveTeleporterMessage(bytes32,address,bytes)", sourceChainId, pendingMsg.sender, pendingMsg.message
            )
        );

        return success;
    }

    /// forge-lint: disable-start(mixed-case-variable)
    // Check if there are pending messages
    function hasPendingMessages(
        bytes32 destinationChainId,
        address destinationAddress
    ) external view returns (bool) {
        return _pendingMessages[destinationChainId][destinationAddress].length > 0;
    }

    // Get count of pending messages
    function getPendingMessageCount(
        bytes32 destinationChainId,
        address destinationAddress
    ) external view returns (uint256) {
        return _pendingMessages[destinationChainId][destinationAddress].length;
    }
    /// forge-lint: disable-end(mixed-case-variable)
}
