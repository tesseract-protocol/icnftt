// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC721Transferrer} from "../../interfaces/IERC721Transferrer.sol";

/**
 * @title IERC721TokenHome
 * @dev Interface for a contract that adapts existing ERC721 tokens for cross-chain functionality on Avalanche L1 networks.
 *
 * This interface defines the functions and events for an "adapter" contract that allows existing ERC721 tokens
 * to be sent to other Avalanche L1 chains using Avalanche's Interchain Messaging (ICM) and received
 * back from those chains.
 */
interface IERC721TokenHome is IERC721Transferrer {
    /**
     * @notice Returns the address of the existing ERC721 token contract being adapted
     * @return The address of the ERC721 token contract that this adapter interacts with
     */
    function getToken() external view returns (address);

    /**
     * @notice Returns all blockchain IDs of registered remote chains
     * @return Array of blockchain IDs
     */
    function getRegisteredChains() external view returns (bytes32[] memory);

    /**
     * @notice Returns the blockchain ID of a registered remote chain
     * @param index The index of the registered chain
     * @return The blockchain ID of the registered chain
     */
    function getRegisteredChain(
        uint256 index
    ) external view returns (bytes32);

    /**
     * @notice Returns the number of registered remote chains
     * @return Number of registered chains
     */
    function getRegisteredChainsLength() external view returns (uint256);

    /**
     * @notice Returns the address of the contract on a remote chain
     * @param remoteBlockchainID The blockchain ID of the remote chain
     * @return The address of the contract on the remote chain
     */
    function getRemoteContract(
        bytes32 remoteBlockchainID
    ) external view returns (address);

    /**
     * @notice Returns the blockchain ID of the remote chain where a token currently exists
     * @dev Returns bytes32(0) if the token is on the current chain
     * @param tokenId The ID of the token
     * @return The blockchain ID of the chain where the token currently exists
     */
    function getTokenLocation(
        uint256 tokenId
    ) external view returns (bytes32);

    /**
     * @dev Emitted when a remote chain contract is registered
     * @param blockchainID The blockchain ID of the registered remote chain
     * @param remote The address of the contract on the remote chain
     */
    event RemoteChainRegistered(bytes32 indexed blockchainID, address indexed remote);

    /**
     * @dev Emitted when a remote chain's expected contract is set or removed
     * @param blockchainID The blockchain ID of the remote chain
     * @param expectedRemote The expected address of the remote contract (address(0) if being removed)
     */
    event RemoteChainExpectedContractSet(bytes32 indexed blockchainID, address indexed expectedRemote);
}
