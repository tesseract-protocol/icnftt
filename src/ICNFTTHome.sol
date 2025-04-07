// SPDX-License-Identifier: MIT
pragma solidity ^0.8.25;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./interfaces/IICNFTTHome.sol";

contract ICNFTTHome is IICNFTTHome, ERC721URIStorage, Ownable {
    // Mapping from tokenId to lock status
    mapping(uint256 => bool) private _lockedTokens;
    
    // Mapping from chainId to remote contract address
    mapping(uint32 => address) private _remoteContracts;
    
    // Array of registered chain IDs
    uint32[] private _registeredChains;
    
    // For demonstration purposes (replace with ICM implementation)
    event SendMessageToRemote(uint32 destChainId, address destAddress, bytes message);
    
    constructor(
        string memory name,
        string memory symbol
    ) ERC721(name, symbol) Ownable(msg.sender) {}
    
    // Mint function (for demonstration)
    function mint(address to, uint256 tokenId, string memory uri) external onlyOwner {
        _mint(to, tokenId);
        _setTokenURI(tokenId, uri);
    }
    
    // Register a remote contract on another chain
    function registerRemoteContract(uint32 chainId, address remoteAddress) external onlyOwner {
        require(remoteAddress != address(0), "Invalid remote address");
        require(_remoteContracts[chainId] == address(0), "Chain already registered");
        
        _remoteContracts[chainId] = remoteAddress;
        _registeredChains.push(chainId);
        
        emit RemoteChainRegistered(chainId, remoteAddress);
    }
    
    // Implementation of IICNFTTHome functions
    
    function sendToken(
        uint256 tokenId, 
        uint32 destinationChainId,
        address recipient
    ) external override {
        require(_exists(tokenId), "Token does not exist");
        require(ownerOf(tokenId) == msg.sender || isApprovedForAll(ownerOf(tokenId), msg.sender) || getApproved(tokenId) == msg.sender,
            "Not owner or approved");
        require(_remoteContracts[destinationChainId] != address(0), "Destination chain not registered");
        require(!_lockedTokens[tokenId], "Token already locked");
        
        // Lock the token
        _lockedTokens[tokenId] = true;
        
        // For demonstration - in a real implementation this would use ICM
        bytes memory message = abi.encode(tokenId, recipient);
        emit SendMessageToRemote(destinationChainId, _remoteContracts[destinationChainId], message);
        
        emit TokenLocked(tokenId, destinationChainId, recipient);
    }
    
    function receiveToken(
        uint256 tokenId,
        address recipient
    ) external override {
        // In a real implementation, this would have access control based on ICM
        // For now, allow any call for demonstration
        
        require(_lockedTokens[tokenId], "Token not locked");
        
        // Unlock the token
        _lockedTokens[tokenId] = false;
        
        // Transfer the token to the recipient
        _safeTransfer(address(this), recipient, tokenId, "");
        
        // For demonstration purposes - in real implementation, sourceChainId would come from ICM
        uint32 sourceChainId = 1;
        
        emit TokenUnlocked(tokenId, sourceChainId, recipient);
    }
    
    function isTokenLocked(uint256 tokenId) external view override returns (bool) {
        return _lockedTokens[tokenId];
    }
    
    function getRegisteredChains() external view override returns (uint32[] memory) {
        return _registeredChains;
    }
    
    // Override transferFrom and safeTransferFrom to prevent transfers of locked tokens
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal virtual override returns (address) {
        require(!_lockedTokens[tokenId], "Token is locked");
        return super._update(to, tokenId, auth);
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