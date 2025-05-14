// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {IERC721Transferrer, ExtensionMessageParams} from "./interfaces/IERC721Transferrer.sol";
import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {IWarpMessenger} from "@avalabs/subnet-evm-contracts@1.2.0/contracts/interfaces/IWarpMessenger.sol";

/**
 * @title ERC721TokenTransferrer
 * @dev An abstract base contract for cross-chain ERC721 token transferring functionality.
 *
 * This contract serves as the foundation for both Home and Remote token contracts in the
 * Interchain NFT (ICNFTT) system. It provides common functionality for managing tokens
 * that can be transferred between Avalanche chains.
 *
 * Key features:
 * 1. Stores the blockchain ID of the current chain
 * 2. Manages the base URI for token metadata
 * 3. Defines the extension system interfaces for token behavior customization
 * 4. Implements hooks for token lifecycle events
 *
 * The contract is designed to be extended by both Home and Remote token implementations.
 */
abstract contract ERC721TokenTransferrer is ERC721, IERC721Transferrer {
    /// @notice The blockchain ID of the current chain
    bytes32 internal immutable _blockchainID;

    /// @notice The base URI used for token metadata
    string internal _baseURIStorage;

    /**
     * @notice Initializes the ERC721TokenTransferrer contract
     * @param name The name of the ERC721 token
     * @param symbol The symbol of the ERC721 token
     * @param baseURI The base URI for token metadata
     */
    constructor(string memory name, string memory symbol, string memory baseURI) ERC721(name, symbol) {
        _baseURIStorage = baseURI;
        _blockchainID = IWarpMessenger(0x0200000000000000000000000000000000000005).getBlockchainID();
    }

    /**
     * @notice Returns the base URI for token metadata
     * @return The base URI string
     */
    function _baseURI() internal view virtual override returns (string memory) {
        return _baseURIStorage;
    }

    /**
     * @notice Returns the blockchain ID of the current chain
     * @return The blockchain ID
     */
    function getBlockchainID() external view override returns (bytes32) {
        return _blockchainID;
    }

    /**
     * @notice Hook that is called before token transfers
     * @dev Can be overridden by derived contracts to implement custom behavior
     * @param to The recipient address
     * @param tokenId The ID of the token being transferred
     */
    function _beforeTokenTransfer(address to, uint256 tokenId) internal virtual {}

    /**
     * @notice Hook that is called after token transfers
     * @dev Can be overridden by derived contracts to implement custom behavior
     * @param from The sender address
     * @param to The recipient address
     * @param tokenId The ID of the token being transferred
     */
    function _afterTokenTransfer(address from, address to, uint256 tokenId) internal virtual {}

    /**
     * @notice Updates token ownership and calls lifecycle hooks
     * @dev Overrides ERC721._update to add custom behavior
     * @param to The recipient address
     * @param tokenId The ID of the token being transferred
     * @param auth The authorized address for the transfer
     * @return The previous owner address
     */
    function _update(address to, uint256 tokenId, address auth) internal virtual override returns (address) {
        _beforeTokenTransfer(to, tokenId);
        address from = super._update(to, tokenId, auth);
        _afterTokenTransfer(from, to, tokenId);
        return from;
    }
}
