// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/**
 * @title IERC721Transferrer
 * @dev Interface for contracts that can transfer ERC721 tokens across Avalanche chains.
 * This interface defines the structures, events, and functions needed for cross-chain
 * token transfers using Avalanche's Interchain Messaging (ICM).
 */

/**
 * @notice Input structure for basic token transfers across chains.
 * @dev Users must populate this structure when calling the send function.
 *
 * @param destinationBlockchainID The blockchain ID of the destination chain where the token will be sent.
 * @param destinationTokenTransferrerAddress The address of the token contract on the destination chain.
 * @param recipient The address that will receive the token on the destination chain.
 * @param primaryFeeTokenAddress The address of the token used to pay for the Teleporter message fee.
 * @param primaryFee The amount of fee tokens to pay for the Teleporter message.
 * @param requiredGasLimit The gas limit required for executing the message on the destination chain.
 */
struct SendTokenInput {
    bytes32 destinationBlockchainID;
    address destinationTokenTransferrerAddress;
    address recipient;
    address primaryFeeTokenAddress;
    uint256 primaryFee;
    uint256 requiredGasLimit;
}

/**
 * @notice Input structure for sending tokens and triggering a contract call on the destination chain.
 * @dev Users must populate this structure when calling the sendAndCall function.
 *
 * @param destinationBlockchainID The blockchain ID of the destination chain where the token will be sent.
 * @param destinationTokenTransferrerAddress The address of the token contract on the destination chain.
 * @param recipientContract The address of the contract that will receive the token and be called on the destination chain.
 * @param fallbackRecipient The address that will receive the token if the contract call fails or doesn't take ownership.
 * @param recipientPayload The calldata to be passed to the recipient contract.
 * @param recipientGasLimit The gas limit allocated for the recipient contract call (must be less than requiredGasLimit).
 * @param primaryFeeTokenAddress The address of the token used to pay for the Teleporter message fee.
 * @param primaryFee The amount of fee tokens to pay for the Teleporter message.
 * @param requiredGasLimit The total gas limit required for executing the message on the destination chain.
 */
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

/**
 * @dev Types of messages that can be sent between transferrer contracts.
 */
enum TransferrerMessageType {
    REGISTER_REMOTE,
    SINGLE_HOP_SEND,
    SINGLE_HOP_CALL
}

/**
 * @dev Message structure for basic token transfers.
 * @param recipient The address that will receive the tokens on the destination chain
 * @param tokenIds Array of token IDs being transferred
 * @param tokenMetadata Array of metadata bytes for each token being transferred
 */
struct SendTokenMessage {
    address recipient;
    uint256[] tokenIds;
    bytes[] tokenMetadata;
}

/**
 * @dev Message structure for send-and-call operations.
 * @param originSenderAddress The address of the original sender on the source chain
 * @param recipientContract The address of the contract that will receive the tokens and be called
 * @param tokenIds Array of token IDs being transferred
 * @param recipientPayload The calldata to be passed to the recipient contract
 * @param recipientGasLimit The gas limit allocated for the recipient contract call
 * @param fallbackRecipient The address that will receive the tokens if the contract call fails
 * @param tokenMetadata Array of metadata bytes for each token being transferred
 */
struct SendAndCallMessage {
    address originSenderAddress;
    address recipientContract;
    uint256[] tokenIds;
    bytes recipientPayload;
    uint256 recipientGasLimit;
    address fallbackRecipient;
    bytes[] tokenMetadata;
}

/**
 * @dev Generic message structure used for all transferrer messages.
 * @param messageType The type of message being sent (REGISTER_REMOTE, SINGLE_HOP_SEND, or SINGLE_HOP_CALL)
 * @param payload The encoded message payload containing the actual transfer data
 */
struct TransferrerMessage {
    TransferrerMessageType messageType;
    bytes payload;
}

/**
 * @dev Emitted when a token is sent to another chain.
 * @param teleporterMessageID The unique identifier of the Teleporter message
 * @param sender The address of the sender initiating the transfer
 * @param tokenIds Array of token IDs being transferred
 */
event TokensSent(bytes32 indexed teleporterMessageID, address indexed sender, uint256[] tokenIds);

/**
 * @dev Emitted when a token is sent with contract call data to another chain.
 * @param teleporterMessageID The unique identifier of the Teleporter message
 * @param sender The address of the sender initiating the transfer
 * @param tokenIds Array of token IDs being transferred
 */
event TokensAndCallSent(bytes32 indexed teleporterMessageID, address indexed sender, uint256[] tokenIds);

/**
 * @dev Emitted when a contract call succeeds in a send-and-call operation.
 * @param recipientContract The address of the contract that successfully received and processed the tokens
 * @param tokenIds Array of token IDs that were successfully transferred and processed
 */
event CallSucceeded(address indexed recipientContract, uint256[] tokenIds);

/**
 * @dev Emitted when a contract call fails in a send-and-call operation.
 * @param recipientContract The address of the contract that failed to process the tokens
 * @param tokenIds Array of token IDs that were involved in the failed operation
 */
event CallFailed(address indexed recipientContract, uint256[] tokenIds);

/**
 * @title IERC721Transferrer
 * @dev Interface that must be implemented by contracts that enable cross-chain transfers of ERC721 tokens.
 */
interface IERC721Transferrer {
    /**
     * @notice Sends a token to another chain.
     * @param input The parameters defining the cross-chain transfer.
     * @param tokenIds The IDs of the tokens to send.
     */
    function send(
        SendTokenInput calldata input,
        uint256[] calldata tokenIds
    ) external;

    /**
     * @notice Sends a token to another chain and triggers a contract call on the destination chain.
     * @param input The parameters defining the cross-chain transfer and contract call.
     * @param tokenIds The IDs of the tokens to send.
     */
    function sendAndCall(
        SendAndCallInput calldata input,
        uint256[] calldata tokenIds
    ) external;

    /**
     * @notice Returns the blockchain ID that the transferrer is deployed on.
     * @return The blockchain ID.
     */
    function getBlockchainID() external view returns (bytes32);
}
