// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/**
 * @notice Input structure for updating URI on remote chains.
 *
 * @param destinationBlockchainID The blockchain ID of the destination chain to update.
 * @param primaryFeeTokenAddress The address of the token used to pay for the Teleporter message fee.
 * @param primaryFee The amount of fee tokens to pay for the Teleporter message.
 */
struct UpdateURIInput {
    bytes32 destinationBlockchainID;
    address primaryFeeTokenAddress;
    uint256 primaryFee;
}

/**
 * @notice Message structure for the URI storage extension
 */
struct URIStorageExtensionMessage {
    uint256 tokenId;
    string uri;
}

/**
 * @dev Emitted when a request to update a specific token URI on a remote chain is sent
 * @param teleporterMessageID The ID of the Teleporter message
 * @param destinationBlockchainID The blockchain ID of the destination chain
 * @param remote The address of the contract on the remote chain
 * @param tokenId The ID of the token
 * @param uri The new token URI
 */
event UpdateRemoteTokenURI(
    bytes32 indexed teleporterMessageID,
    bytes32 indexed destinationBlockchainID,
    address indexed remote,
    uint256 tokenId,
    string uri
);
