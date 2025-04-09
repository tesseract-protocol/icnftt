// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

enum TransferrerMessageType {
    REGISTER_REMOTE,
    UPDATE_REMOTE_BASE_URI,
    SINGLE_HOP_SEND,
    SINGLE_HOP_CALL
}

struct TransferrerMessage {
    TransferrerMessageType messageType;
    bytes payload;
}

struct TransferTokenMessage {
    address recipient;
    uint256 tokenId;
}

struct UpdateRemoteBaseURIMessage {
    string baseURI;
}

struct SendNFTInput {
    bytes32 destinationBlockchainID;
    address destinationTokenTransferrerAddress;
    address recipient;
    address primaryFeeTokenAddress;
    uint256 primaryFee;
    uint256 requiredGasLimit;
}

event TokenSent(bytes32 indexed teleporterMessageID, address indexed sender, uint256 tokenId);

interface INFTTransferrer {
    function send(SendNFTInput calldata input, uint256 tokenId) external;
}
