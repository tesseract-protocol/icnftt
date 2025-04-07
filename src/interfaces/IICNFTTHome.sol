// SPDX-License-Identifier: MIT
pragma solidity 0.8.25;

interface IICNFTTHome {
    // Locks the token on Home chain and sends message to mint on Remote
    function sendToken(
        uint256 tokenId, 
        uint32 destinationChainId,
        address recipient
    ) external;
    
    // Receives message from Remote and unlocks the token
    function receiveToken(
        uint256 tokenId,
        address recipient
    ) external;
    
    // View function to check if token is locked
    function isTokenLocked(uint256 tokenId) external view returns (bool);
    
    // Returns all chains where this token has Remote versions
    function getRegisteredChains() external view returns (uint32[] memory);
    
    event TokenLocked(uint256 indexed tokenId, uint32 indexed destinationChainId, address indexed recipient);
    event TokenUnlocked(uint256 indexed tokenId, uint32 indexed sourceChainId, address indexed recipient);
    event RemoteChainRegistered(uint32 indexed chainId, address indexed remoteAddress);
} 