// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

struct SendTokenInput {
    bytes32 destinationBlockchainID;
    address destinationTokenTransferrerAddress;
    address recipient;
    address primaryFeeTokenAddress;
    uint256 primaryFee;
    uint256 requiredGasLimit;
}

struct SendAndCallInput {
    bytes32 destinationBlockchainID;
    address destinationTokenTransferrerAddress;
    address recipientContract;
    address fallbackRecipient;
    bytes recipientPayload;
    uint256 recipientGasLimit;
    address primaryFeeTokenAddress;
    uint256 primaryFee;
    uint256 requiredGasLimit;
}

enum TransferrerMessageType {
    REGISTER_REMOTE,
    UPDATE_REMOTE_BASE_URI,
    UPDATE_REMOTE_TOKEN_URI,
    SINGLE_HOP_SEND,
    SINGLE_HOP_CALL
}

struct SendTokenMessage {
    address recipient;
    uint256 tokenId;
    string tokenURI;
}

struct SendAndCallMessage {
    uint256 tokenId;
    string tokenURI;
    address originSenderAddress;
    address recipientContract;
    bytes recipientPayload;
    uint256 recipientGasLimit;
    address fallbackRecipient;
}

struct UpdateRemoteBaseURIMessage {
    string baseURI;
}

struct UpdateRemoteTokenURIMessage {
    uint256 tokenId;
    string uri;
}

struct TransferrerMessage {
    TransferrerMessageType messageType;
    bytes payload;
}

event TokenSent(bytes32 indexed teleporterMessageID, address indexed sender, uint256 tokenId);

event TokenAndCallSent(bytes32 indexed teleporterMessageID, address indexed sender, uint256 tokenId);

event CallSucceeded(address indexed recipientContract, uint256 tokenId);

event CallFailed(address indexed recipientContract, uint256 tokenId);

interface IERC721Transferrer {
    function send(SendTokenInput calldata input, uint256 tokenId) external;
    function sendAndCall(SendAndCallInput calldata input, uint256 tokenId) external;
}
