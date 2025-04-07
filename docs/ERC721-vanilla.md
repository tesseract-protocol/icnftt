# Avalanche Interchain NFT Transfer (ICNFTT) - ERC721 Specification

## Overview

This document specifies the implementation of ERC721 Home and Remote tokens for Avalanche Interchain NFT Transfer (ICNFTT), enabling seamless transfer of NFTs between Avalanche L1s while preserving their unique characteristics and ownership history.

## Token Architecture

ICNFTT follows a Hub/Spoke model:
- **Home Token**: The canonical version of the NFT living on the Hub chain.
- **Remote Token**: Representation of the NFT on Spoke chains.

Definitions:

- **Bridge**: Smart contracts facilitating cross-chain messaging via ICM.
- **Lock**: The process of locking an NFT on its Home chain when transferred to a Remote chain.
- **Mint**: The process of creating a representation of a locked NFT on a Remote chain.
- **Burn**: The process of destroying a Remote NFT when transferring back to Home.
- **Unlock**: The process of releasing a locked NFT on its Home chain.

## State Sync Model

We recommend a hybrid approach to state synchronization:

1. **Autonomous Remote** for local operations like approvals and transfers.
2. **Hub-Push Async** for admin operations like pausing and metadata changes.
3. **Hub-Centered Sync** for critical functions like minting (when supply limits exist) or initial ICNFTT deployment.

## Core Interface

Both Home and Remote tokens implement the standard ERC721 interface:

```solidity
interface IERC721 {
    function balanceOf(address owner) external view returns (uint256 balance);
    function ownerOf(uint256 tokenId) external view returns (address owner);
    function safeTransferFrom(address from, address to, uint256 tokenId) external;
    function transferFrom(address from, address to, uint256 tokenId) external;
    function approve(address to, uint256 tokenId) external;
    function getApproved(uint256 tokenId) external view returns (address operator);
    function setApprovalForAll(address operator, bool approved) external;
    function isApprovedForAll(address owner, address operator) external view returns (bool);
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
    
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);
}
```

Plus the standard metadata extension:

```solidity
interface IERC721Metadata {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function tokenURI(uint256 tokenId) external view returns (string memory);
}
```

## Home/Remote Interfaces

### Home Interface

```solidity
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
```

### Remote Interface

```solidity
interface IICNFTTRemote {
    // Receives message from Home to mint a token
    function receiveToken(
        uint256 tokenId,
        address recipient
    ) external;
    
    // Burns the token on Remote and sends message to unlock on Home
    function returnToken(
        uint256 tokenId, 
        address recipient
    ) external;
    
    // Returns the Home chain ID
    function getHomeChainId() external view returns (uint32);
    
    // Returns the Home token address
    function getHomeTokenAddress() external view returns (address);
    
    event TokenMinted(uint256 indexed tokenId, address indexed recipient);
    event TokenBurned(uint256 indexed tokenId, address indexed recipient);
    event HomeChainRegistered(uint32 indexed chainId, address indexed homeAddress);
}
```

## State Sync and Data Reading Strategy

### Autonomous Remote Operations

These functions operate independently on each chain with no cross-chain synchronization:
- `approve`
- `getApproved`
- `setApprovalForAll`
- `isApprovedForAll`
- `transferFrom` and `safeTransferFrom` (for local transfers)

### Hub-Push Async Operations

These operations are pushed from Home to Remote but don't require acknowledgement:
- Contract pausing/unpausing (global)
- Metadata updates (tokenURI changes)
- Administrative access control changes

### Hub-Centered Sync Operations

These operations require interaction with the Home chain:
- Minting (when supply-constrained)
- Burning (requires Home chain to handle state properly)
- Token deployment

## Metadata Handling

Metadata should follow these guidelines:

1. Remote tokens should either:
   - Redirect `tokenURI` requests to the Home token (recommended for dynamic metadata)
   - Maintain a synchronized copy of metadata (for static or rarely changing metadata)

2. Metadata updates:
   - For dynamic metadata: Home token serves as source of truth
   - For cached metadata: Updates pushed from Home to Remote via Hub-Push Async

## Implementation Recommendations

### Managing Ownership and Transfers

1. **Local Transfers**: Allow transfers between users on same chain without cross-chain messaging.
2. **Cross-Chain Transfers**:
   - Home→Remote: Lock on Home, mint on Remote
   - Remote→Home: Burn on Remote, unlock on Home
   - Remote→Remote: Use Home as intermediate (burn on source, mint on destination)

### Token Enumeration

If implementing ERC721Enumerable:
- Remote tokens should maintain local enumeration state for locally present tokens
- Global supply queries should be directed to Home token with a syncing strategy (e.g. sync totalSupply once all tokens are minted)
- Client applications should merge enumeration data from multiple chains when needed

### Extensions and Additional Features

1. **Pausable**: Admin operations should propagate from Home to all Remotes.
2. **Burnable**: Local burning should not be supported on Remote chains.
3. **Access Control**: Admin roles should be synchronized from Home to Remotes.

## Data Reading Patterns for Applications

Applications interacting with ICNFTT tokens should follow these patterns:

1. **Basic Data Retrieval**:
   - Query local chain first for basic data (ownership, approvals)
   - Fall back to Home chain for canonical data (global supply, metadata)

2. **Metadata Display**:
   - Follow tokenURI to the authoritative source (typically Home chain)
   - Cache and refresh periodically to handle changes

3. **Cross-Chain Awareness**:
   - Applications should check if a token is available on the current chain
   - Provide bridging options if token exists on another chain
   - Display token location (Home vs Remote chain)

## Error Handling

1. **Consistency Errors**:
   - Detect and handle cases where Remote state diverges from Home
   - Provide recovery mechanisms for desynchronized tokens

2. **Message Failures**:
   - Implement retry mechanisms for failed ICM messages
   - Allow manual intervention for critical failures
