// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IICNFTTRemote.sol";

contract ICNFTTRemote is IICNFTTRemote, ERC721URIStorage, Ownable {
    // Home chain ID
    uint32 private _homeChainId;
    
    // Home chain contract address
    address private _homeContractAddress;
    
    // For demonstration purposes (replace with ICM implementation)
    event SendMessageToHome(address destAddress, bytes message);
    
    constructor(
        string memory name,
        string memory symbol,
        uint32 homeChainId,
        address homeContractAddress
    ) ERC721(name, symbol) Ownable(msg.sender) {
        _homeChainId = homeChainId;
        _homeContractAddress = homeContractAddress;
        
        emit HomeChainRegistered(homeChainId, homeContractAddress);
    }
    
    // Implementation of IICNFTTRemote functions
    
    function receiveToken(
        uint256 tokenId,
        address recipient
    ) external override {
        // In a real implementation, this would have access control based on ICM
        // For now, allow any call for demonstration
        
        // Mint the token to the recipient
        _mint(recipient, tokenId);
        
        // For a complete implementation, the tokenURI would be provided in the cross-chain message
        // or fetched from the home chain
        
        emit TokenMinted(tokenId, recipient);
    }
    
    function returnToken(
        uint256 tokenId, 
        address recipient
    ) external override {
        require(_exists(tokenId), "Token does not exist");
        require(ownerOf(tokenId) == msg.sender || isApprovedForAll(ownerOf(tokenId), msg.sender) || getApproved(tokenId) == msg.sender,
            "Not owner or approved");
        
        // Burn the token
        _burn(tokenId);
        
        // For demonstration - in a real implementation this would use ICM
        bytes memory message = abi.encode(tokenId, recipient);
        emit SendMessageToHome(_homeContractAddress, message);
        
        emit TokenBurned(tokenId, recipient);
    }
    
    function getHomeChainId() external view override returns (uint32) {
        return _homeChainId;
    }
    
    function getHomeTokenAddress() external view override returns (address) {
        return _homeContractAddress;
    }
    
    // For demonstration - in a real implementation, this would be provided by ICM
    // or fetched from the home chain
    function setTokenURI(uint256 tokenId, string memory uri) external onlyOwner {
        _setTokenURI(tokenId, uri);
    }
    
    // Helper function to check if token exists
    function _exists(uint256 tokenId) internal view returns (bool) {
        try this.ownerOf(tokenId) returns (address) {
            return true;
        } catch {
            return false;
        }
    }
} 