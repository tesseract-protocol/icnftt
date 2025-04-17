// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC721Transferrer} from "../../interfaces/IERC721Transferrer.sol";

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
 * @title IERC721TokenHome
 * @dev Interface for a contract that manages ERC721 tokens on their native Avalanche L1 chain.
 *
 * This interface defines the functions and events for a "home" contract that allows ERC721 tokens
 * to be sent to other Avalanche L1 chains using Avalanche's Interchain Messaging (ICM) and received
 * back from those chains. It also supports propagating metadata updates across chains.
 */
interface IERC721TokenHome is IERC721Transferrer {
    /**
     * @notice Returns all blockchain IDs of registered remote chains
     * @return Array of blockchain IDs
     */
    function getRegisteredChains() external view returns (bytes32[] memory);

    /**
     * @notice Returns the number of registered remote chains
     * @return Number of registered chains
     */
    function getRegisteredChainsLength() external view returns (uint256);

    /**
     * @notice Returns the blockchain ID of the current chain
     * @return The blockchain ID
     */
    function getBlockchainID() external view returns (bytes32);

    /**
     * @dev Emitted when the base URI for all tokens is updated
     * @param newBaseURI The new base URI
     */
    event BaseURIUpdated(string newBaseURI);

    /**
     * @dev Emitted when a remote chain contract is registered
     * @param blockchainID The blockchain ID of the registered remote chain
     * @param remote The address of the contract on the remote chain
     */
    event RemoteChainRegistered(bytes32 indexed blockchainID, address indexed remote);

    /**
     * @dev Emitted when a request to update a remote chain's base URI is sent
     * @param teleporterMessageID The ID of the Teleporter message
     * @param destinationBlockchainID The blockchain ID of the destination chain
     * @param remote The address of the contract on the remote chain
     * @param baseURI The new base URI
     */
    event UpdateRemoteBaseURI(
        bytes32 indexed teleporterMessageID,
        bytes32 indexed destinationBlockchainID,
        address indexed remote,
        string baseURI
    );

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
}
