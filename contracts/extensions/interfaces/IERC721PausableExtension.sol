// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

/**
 * @notice Input structure for updating paused state on remote chains.
 *
 * @param destinationBlockchainID The blockchain ID of the destination chain to update.
 * @param primaryFeeTokenAddress The address of the token used to pay for the Teleporter message fee.
 * @param primaryFee The amount of fee tokens to pay for the Teleporter message.
 */
struct UpdatePausedStateInput {
    bytes32 destinationBlockchainID;
    address primaryFeeTokenAddress;
    uint256 primaryFee;
}

/**
 * @notice Message structure for the pausable extension
 */
struct PausableExtensionMessage {
    bool paused;
}
