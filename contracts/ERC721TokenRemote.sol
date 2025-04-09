// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import {
    ERC721URIStorage,
    ERC721
} from "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import {IERC721TokenRemote} from "./interfaces/IERC721TokenRemote.sol";
import {TeleporterRegistryOwnableApp} from "@teleporter/registry/TeleporterRegistryOwnableApp.sol";
import {TeleporterMessageInput, TeleporterFeeInfo} from "@teleporter/ITeleporterMessenger.sol";

contract ERC721TokenRemote is IERC721TokenRemote, ERC721URIStorage, TeleporterRegistryOwnableApp {
    // Home chain ID
    bytes32 public immutable homeChainId;

    // Home chain contract address
    address public immutable homeContractAddress;

    // For demonstration purposes (replace with ICM implementation)
    event SendMessageToHome(address destAddress, bytes message);

    constructor(
        string memory name,
        string memory symbol,
        bytes32 homeChainId,
        address homeContractAddress,
        address teleporterRegistryAddress,
        uint256 minTeleporterVersion
    )
        ERC721(name, symbol)
        TeleporterRegistryOwnableApp(teleporterRegistryAddress, msg.sender, minTeleporterVersion)
    {
        homeChainId = homeChainId;
        homeContractAddress = homeContractAddress;

        emit HomeChainRegistered(homeChainId, homeContractAddress);
    }

    function getHomeChainId() external view override returns (bytes32) {
        return homeChainId;
    }

    function getHomeTokenAddress() external view override returns (address) {
        return homeContractAddress;
    }

    // For demonstration - in a real implementation, this would be provided by ICM
    // or fetched from the home chain
    function setTokenURI(uint256 tokenId, string memory uri) external onlyOwner {
        _setTokenURI(tokenId, uri);
    }

    function receiveToken(uint256 tokenId, address recipient) external override {
        // In a real implementation, this would have access control based on ICM
        // For now, allow any call for demonstration

        // Mint the token to the recipient
        _mint(recipient, tokenId);

        // For a complete implementation, the tokenURI would be provided in the cross-chain message
        // or fetched from the home chain

        emit TokenMinted(tokenId, recipient);
    }

    function returnToken(uint256 tokenId, address recipient) external override {
        require(_exists(tokenId), "Token does not exist");
        require(
            ownerOf(tokenId) == msg.sender || isApprovedForAll(ownerOf(tokenId), msg.sender)
                || getApproved(tokenId) == msg.sender,
            "Not owner or approved"
        );

        // Burn the token
        _burn(tokenId);

        // For demonstration - in a real implementation this would use ICM
        bytes memory message = abi.encode(tokenId, recipient);
        emit SendMessageToHome(homeContractAddress, message);

        emit TokenBurned(tokenId, recipient);
    }

    function _receiveTeleporterMessage(
        bytes32 sourceBlockchainID,
        address originSenderAddress,
        bytes memory message
    ) internal override {
        // TODO: Implement
    }

    // Helper function to check if token exists
    function _exists(
        uint256 tokenId
    ) internal view returns (bool) {
        try this.ownerOf(tokenId) returns (address) {
            return true;
        } catch {
            return false;
        }
    }
}
