# ICNFTT: Dynamic Metadata Workflow for ERC721-vanilla

## Overview

This document outlines the workflow for managing dynamic metadata in an ERC721-vanilla implementation with Home and Remote tokens.

The system uses a Hub-Push Async model for metadata updates, where the Home token serves as the source of truth and pushes updates to Remote tokens.

### Purpose for Metadata Updates

1. **Dynamic Functionality**
   - Allow NFTs to evolve over time
   - Support dynamic content
   - Enable progressive reveal of NFT features or content

2. **Technical Improvements**
   - Migrate to new IPFS gateways
   - Update metadata schema in order to add new attributes or traits
   - Fix incorrect or outdated information
   - Optimize storage locations

### Stakeholders for Metadata Updates

1. **Collection Owners**
   - Collection owners who want to update collection-wide metadata
   - Typically an admin with permission to update metadata (e.g. team members or DAO)
   - Want to maintain collection consistency and manage metadata updates efficiently across chains

2. **Token Owners**
   - NFT holders who want to update their token's metadata in order to ensure consistent representation of their NFTs
   - Want to update metadata without complex cross-chain operations

3. **Marketplaces**
   - Platforms that display and trade NFTs need to reflect accurate, up-to-date metadata
   - Want to reduce integration complexity with standardized update flow
     - Enable cross-chain listing without manual synchronization
   - May need to update metadata cache in third-party storage system

4. **Infrastructure Providers**
   - ICM message relayers
   - IPFS storage providers
   - Cache management services

## Most Typical Update Flows

#### Collection-wide Update

The owner updates metadata for collection-wide information.

1. Home is the source of truth
2. Home pushes update to Remote
3. Remote is updated with latest truth

#### Token-Specific Update

The owner updates metadata for token-specific information but does not want to incur the cost to update metadata across chains for many tokenIds and chains.

1. Home is the source of truth
2. Home does not push update to Remote
3. Remote is out of sync with latest truth

It may be users wish to update this metadata by initiating transactions themselves.

1. Home is the source of truth
2. Remote request update from Home (Remote -> Home -> Remote)
3. Remote is updated with latest truth

## Architecture

## Components

### 1. Home Token
- Source of truth for metadata
- Manages metadata updates
- Pushes changes to Remote tokens (if needed)
- Implements metadata update functions
- Emits events for metadata changes

### 2. Remote Token
- Maintains local metadata state
- Receives updates from Home
- Implements standard ERC721 metadata interface

### 3. ICM Message System
- Handles cross-chain communication
- Ensures reliable delivery
- Provides fallback mechanisms

## Workflow Steps

### 1. Metadata Update on Home

- **Originating Chain:** Home Chain
- **Function Classification:** Extension of ERC721Metadata

```solidity
function updateTokenMetadata(uint256 tokenId, string memory newURI) external {
    require(hasUpdatePermission(msg.sender), "Not authorized");
    _updateTokenURI(tokenId, newURI);
    emit MetadataUpdated(tokenId, newURI);
    
    // Push update to all registered Remote tokens
    _pushMetadataUpdate(tokenId, newURI);
}
```

### 2. Cross-Chain Update

- **Originating Chain:** Home Chain
- **Function Classification:** New Internal Function (ICNFTT-specific)

```solidity
function _pushMetadataUpdate(uint256 tokenId, string memory newURI) internal {
    // Send ICM message to each registered Remote
    for (uint i = 0; i < registeredRemotes.length; i++) {
        bytes memory message = abi.encode(
            tokenId,
            newURI
        );
        icm.sendMessage(registeredRemotes[i], message);
    }
}
```

### 3. Remote Token Update

- **Originating Chain:** Remote Chain
- **Function Classification:** New External Function (ICNFTT-specific)

```solidity
function receiveMetadataUpdate(
    uint256 tokenId,
    string memory newURI
) external onlyICM {
    // Update local metadata
    _tokenURIs[tokenId] = newURI;
    
    emit RemoteMetadataUpdated(tokenId, newURI);
}
```

## Client Integration

### 1. Reading Metadata

It is preferred that metadata is read from the Home chain, but for established integrations with NFT standards, this is unlikely to be the common case.

```javascript
async function getTokenMetadata(tokenId) {
    // always read from homeContract
    return await homeContract.tokenURI(tokenId);
}
```

More likely, metadata will be read from any supported chain, which may lead to outdated information:

```javascript
async function getTokenMetadata(chainId, address, tokenId) {
    // read from the chain and address available
    return await (new ERC721(chainId, address)).tokenURI(tokenId);
}
```

### 2. Client-Side State Management

In case a client reads both contracts, and notices a divergence, they could trigger an update which calls the Home token to update Remote.

```javascript
// Get fresh data from both contracts
const [homeURI, remoteURI] = await Promise.all([
    this.homeContract.tokenURI(tokenId),
    this.remoteContract.tokenURI(tokenId)
]);

// Compare and update stale data if needed
if (homeURI !== remoteURI) {
    _updateRemote(tokenId);
}
```
