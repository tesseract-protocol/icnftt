// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC721Transferrer} from "../../interfaces/IERC721Transferrer.sol";

/**
 * @title IERC721TokenRemote
 * @dev Interface for a contract that represents ERC721 tokens on a remote Avalanche L1 chain.
 *
 * This interface defines the functions and events for a remote representation of ERC721 tokens
 * that are native to another chain. The implementing contract works with an ERC721TokenHome contract
 * to enable cross-chain transfers of ERC721 tokens using Avalanche's Interchain Messaging (ICM).
 */
interface IERC721TokenRemote is IERC721Transferrer {
    /**
     * @notice Returns the blockchain ID of the home chain
     * @return The home chain's blockchain ID
     */
    function getHomeBlockchainID() external view returns (bytes32);

    /**
     * @notice Returns the address of the token contract on the home chain
     * @return The home contract address
     */
    function getHomeTokenAddress() external view returns (address);

    /**
     * @notice Returns the blockchain ID of the current chain
     * @return The blockchain ID
     */
    function getBlockchainID() external view returns (bytes32);

    /**
     * @notice Returns whether this contract has been registered with the home contract
     * @return Registration status
     */
    function getIsRegistered() external view returns (bool);

    /**
     * @dev Emitted when a token is minted on the remote chain
     * @param tokenId The ID of the token minted
     * @param owner The address of the token recipient
     */
    event TokenMinted(uint256 indexed tokenId, address indexed owner);

    /**
     * @dev Emitted when a token is burned on the remote chain to be sent back to the home chain
     * @param tokenId The ID of the token burned
     * @param owner The address of the token owner before burning
     */
    event TokenBurned(uint256 indexed tokenId, address indexed owner);

    /**
     * @dev Emitted when the base URI is updated by the home chain
     * @param baseURI The new base URI
     */
    event RemoteBaseURIUpdated(string indexed baseURI);

    /**
     * @dev Emitted when a specific token URI is updated by the home chain
     * @param tokenId The ID of the token
     * @param uri The new token URI
     */
    event RemoteTokenURIUpdated(uint256 indexed tokenId, string indexed uri);

    /**
     * @dev Emitted when the home chain is registered during contract creation
     * @param chainId The blockchain ID of the home chain
     * @param homeAddress The address of the home contract
     */
    event HomeChainRegistered(bytes32 indexed chainId, address indexed homeAddress);
}
