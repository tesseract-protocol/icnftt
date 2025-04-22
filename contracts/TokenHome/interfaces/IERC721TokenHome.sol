// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC721Transferrer} from "../../interfaces/IERC721Transferrer.sol";

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
     * @notice Returns the address of the contract on a remote chain
     * @param remoteBlockchainID The blockchain ID of the remote chain
     * @return The address of the contract on the remote chain
     */
    function getRemoteContract(
        bytes32 remoteBlockchainID
    ) external view returns (address);

    /**
     * @notice Returns the blockchain ID of the remote chain where a token is located
     * @param tokenId The ID of the token
     * @return The blockchain ID of the remote chain
     */
    function getTokenLocation(
        uint256 tokenId
    ) external view returns (bytes32);

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
}
