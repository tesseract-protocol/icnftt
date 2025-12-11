// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC721Transferrer} from "../../interfaces/IERC721Transferrer.sol";
import {TeleporterFeeInfo} from "@teleporter/ITeleporterMessenger.sol";

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
     * @dev Emitted when the ERC721TokenRemote contract is initialized
     * @param homeBlockchainID The blockchain ID of the home chain
     * @param homeContractAddress The address of the home contract
     */
    event ERC721TokenRemoteInitialized(bytes32 indexed homeBlockchainID, address indexed homeContractAddress);

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
     * @dev Emitted after the first successful transfer of tokens from the home chain to the remote chain, finalizing the registration of the home chain
     * @param chainId The blockchain ID of the home chain
     * @param homeAddress The address of the home contract
     */
    event HomeChainRegistered(bytes32 indexed chainId, address indexed homeAddress);

    /**
     * @dev Emitted after a registration message is sent to the home contract
     * @param teleporterMessageID The ID of the Teleporter message
     * @param destinationBlockchainID The blockchain ID of the destination chain
     * @param remote The address of the contract on the remote chain
     */
    event RegisterWithHome(bytes32 indexed teleporterMessageID, bytes32 indexed destinationBlockchainID, address indexed remote);

    /**
     * @notice Registers this contract with the home contract
     * @dev Sends a registration message to the home contract
     * @param feeInfo Information about the fee to pay for the cross-chain message
     */
    function registerWithHome(TeleporterFeeInfo calldata feeInfo) external;

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
     * @notice Returns whether this contract has been registered with the home contract
     * @return Registration status
     */
    function getIsRegistered() external view returns (bool);
}
