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
