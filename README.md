# Avalanche Interchain NFT Transfer

## Background

Avalanche Interchain Messaging (ICM) is a protocol that enables asynchronous cross-chain messaging between EVM L1s within Avalanche. Teleporter is a smart contract interface that implements ICM, providing features like replay protection, retry mechanisms, and relayer incentivization for cross-chain communication. 
  * [ICM Docs](https://build.avax.network/docs/cross-chain/avalanche-warp-messaging/overview)

Avalanche Interchain Token Transfer (ICTT) is a standard that enables tokens to be transferred between L1s, with each transfer consisting of locking the asset as collateral on the home L1 and minting a representation of the asset on the remote L1.
  * [ICTT Docs](https://build.avax.network/docs/cross-chain/interchain-token-transfer/overview)

For NFTs, we introduce Avalanche Interchain NFT Transfer (ICNFTT). This will enable seamless transfer of digital assets between Avalanche L1s while preserving their unique characteristics, ownership history, and associated metadata in order to create a unified NFT ecosystem across Avalanche L1s, making it easier for users to transfer NFTs across different chains and use them in their favorite apps and marketplaces.

## ICTT vs ICNFTT

If you are already familiar with ICTT, ICNFTT has some key similarities and differences. 

### Similar Patterns:

- New and Existing tokens are easily supported.
- Home/Remote deployments, using:
  - handshake/acknowledgement pattern on setup. [1]
  - lock/mint pattern on transfer.
- Hub/Spoke architecture
  - One canonical Home edition is intended to live on the Hub and Remotes are intended to live on one or more spokes. [2]
  - Home and Remotes have one-to-many relationship
  - Remotes should not act as Homes in order to avoid complex network relationships.
- Features may be added to Home and Remote tokens as long as they are compatible with the relevant L1s and ICM.

### Key Differences:

- Support for NFTs :)
- Only hops to/from Home/Remotes are supported; no support for multi-hop as the nth hop has no payment mechanism for the relayer
- ICTT effectively has autonomous, independent state between L1s.
  - The default Remote ERC20 token can function completely without their canonical Home token counterparts.
- ICNFTT may need a mixture of synced and unsynced state. Remote NFTs may need to check canonical edition for data, including for permissioning.
  - NFTs very often use custom plugins with many different write needs and permissions.
- Data read requirements for ERC20 integrations are fairly straightforward; basically applications need a price and balance.
  - NFTs with custom plugins need more information, which may or may not be synced across Home and Remotes.

## Generalizing the differences for ICNFTT

There are two core challenges:
- Manging a combination of synced and out of sync state
- Reading accurate data while out of sync

## Managing State Sync Across L1s

We introduce possible approaches to manage state sync across L1s, then discuss some specific examples.

We recommend following the pattern of ICTT for Autonomous Remote as much as possible and pushing other changes, including permissioned changes like `pause()` from Home to Remote (Hub-Push Async).

Possible approaches:

| # | State Sync Model | Description |
|---|------------|-------------|
| 1 | Autonomous Remote | Remote NFTs operate independently with minimal synchronization to Home, explicitly allowing for out-of-sync states |
| 2 | Acknowledge Change | Changes require explicit approval from Home token and acknowledgement from Remote token before taking effect on Home and Remote |
| 3 | Hub-Centered Sync | Operations on Remote chains are forwarded back to Home chain, maintaining a single source of truth |
| 4 | Hub-Push Async | Changes are pushed from Home and require no acknowledgement from Remote |

It may be neceesary to mix and match approaches, dending on the NFTs specific implementation.

#### Example 1: Mint

A contract that allows for infinite mints can allow for `mint()` to be called from any chain (using the Autonomous Remote Model).

However, if `mint()` must follow other rules and pass other checks, like a maximum supply, it is better for `mint()` to take place on the Home token (using the Hub-Centered Sync Model).

#### Example 2: Approve

There is no reason for approvals to sync across L1s. Approvals and related functions should be handled using the Autonomous Remote Model.

### Handling Auth and Permissioned Functions

Different state sync models handle authorization operations in different ways. The choices affects security, gas costs, and user experience.

| State Sync Model | Auth Handling Approach | Security Profile | User Experience | Gas Costs |
|------------------|------------------------|------------------|----------------|-----------|
| Autonomous Remote | • Each chain maintains separate permissions<br>• No cross-chain permission checks<br>• Local validation only | • Medium security<br>• Isolated permission systems<br>• Chain-specific vulnerabilities | • Fast responses<br>• Chain-specific permissions may confuse users<br>• Works when either chain is down | Low |
| Acknowledge Change | • Permission changes require approval from Home<br>• Two-phase commit for critical operations<br>• Dual-chain validation | • High security<br>• Consensus required for changes<br>• Resistant to single-chain attacks | • Slower responses<br>• More predictable behavior<br>• Higher failure rate during network issues | High |
| Hub-Centered Sync | • All permissions validated by Home<br>• Remote defers to Home for auth decisions<br>• Single source of truth | • High security<br>• Centralized control<br>• Hub vulnerabilities affect all chains | • Consistent but high latency<br>• Simple mental model<br>• Fails if Home chain is unavailable | Medium-High |
| Hub-Push Async | • Home pushes permission changes to Remote<br>• Remote trusts but doesn't confirm changes<br>• One-way notification system | • Medium-High security<br>• Fast propagation of changes<br>• Potential desynchronization | • Quick updates<br>• May see temporary inconsistencies<br>• Works when Remote unavailable | Medium |

#### Example: Managing Contract Admin Permissions

Consider a collection where admins can pause trading, add to allowlists, or change fees:

| State Sync Model | Implementation | Tradeoffs |
|------------------|----------------|-----------|
| Autonomous Remote | • Each chain has separate admin lists<br>• Admin on Home can't pause trading on Remote<br>• Actions must be repeated on each chain | • Simple implementation<br>• Independent administration<br>• Poor emergency response across chains |
| Acknowledge Change | • Admin changes require two-way confirmation<br>• Home proposes changes, Remote acknowledges<br>• Both chains maintain synchronized admin state | • Maximum consistency<br>• Changes applied atomically across chains<br>• Extremely high security for admin operations<br>• Double the messaging costs<br>• Risk if Remote cannot respond |
| Hub-Centered Sync | • All verification happens on Home<br>• Remote forwards admin actions to Home<br>• Home validates and returns result | • Single admin list to maintain<br>• Consistent permissions<br>• High latency for actions on Remote<br>• Risk if Home cannot respond |
| Hub-Push Async | • Home pushes admin list changes to Remote<br>• Remote maintains local copy of admin list<br>• Admin actions use local list for validation | • Fast local validation after sync<br>• Good balance of consistency and performance<br>• May have brief permission inconsistencies |

The decision for syncing state and handling auth also impacts how we should read canonical data.

## Reading Canonical Data

We need to read data from its canonical source(s). The approach(es) taken for syncing state offers different tradeoffs.

**We believe this is the biggest implementation hurdle on ICNFTT. We can move NFTs cross-chain, but from where should smart contracts and clients look for data? And how do integrators know in advance the state sync model, which may be different across different parts of the contracts?**

For the most part, applications will need to merge and reconcile data from multiple chains. We will want to first query the canonical Home for information, then query any Remotes.

| State Sync Model | Data Reading Strategy | Implementation Complexity |
|------------------|----------------------|---------------------------|
| Autonomous Remote and Hub-Push Async | • Query Home first for canonical data<br>• Fall back to Remote for local modifications<br>• Combine results client-side | High |
| Acknowledge Change and Hub-Centered Sync | • Read from either chain<br>• Consistent views<br>• Atomic updates across chains | Low |

#### Example: Implementing ERC721Enumerable Interface

We provide an example case for implementing `tokenOfOwnerByIndex(address owner, uint256 index)` using two extremes:

| State Sync Model | Data Reading Implementation | Challenges |
|---------------------|----------------|------------|
| Autonomous Remote | • Remote maintains local enumeration for bridged tokens<br>• May need to query Home for complete enumeration | • Hard to provide accurate global index values<br>• Requires complex logic to merge Home and Remote data |
| Hub-Centered Sync | • Remote always handles transfers by going Home for definitive ownership reconciliation<br>• Only query home | • High cost<br>• High latency<br>• Depends on Home chain availability |

### Data Reading Experience by State Sync Model

#### Example: Autonomous Remote

A marketplace showing an NFT's attributes might display different rarities or metadata depending on whether it's accessing the Home or Remote version, leading to confusion about the "true" state of the NFT.

#### Example: Acknowledge Change

Users experience highly consistent data across chains but with higher latency. This model provides the most predictable experience since all data is synchronized via two-phase commit. Users can trust that what they see is identical regardless of which chain they're interacting with, but all operations take longer to complete.

#### Example: Hub-Centered Sync

Users experience a single source of truth with variable latency. Since all data is ultimately sourced from the Home chain, users get consistent information but with performance that varies based on cross-chain communication speed. If the Home chain is unavailable, all data access may fail.

#### Example: Hub-Push Async

Users experience fast local reads with periodic updates. Applications can rely on indicators showing when data was last synchronized, giving users transparency about potential staleness. This balances performance and consistency well.

### Reading Data from Canonical Sources

We need to read data from its canonical source(s). The approach taken for syncing state matters here.

In case we let the chains be out of sync, we will want to first query the canonical Home for information, then query any Remotes.

| State Sync Approach | Data Reading Approach | Pros | Cons |
|---------------------|----------------------|------|------|
| Autonomous Remote | • Query Home first for canonical data<br>• Fall back to Remote for local modifications<br>• Combine results client-side | • More up-to-date data<br>• Works when either chain is down<br>• Flexible implementation | • Complex result merging<br>• Potential for conflicting data<br>• Higher client-side complexity |
| Acknowledge Change | • Query Home only as single source of truth<br>• All data is consistent across chains | • Simple implementation<br>• Guaranteed data consistency<br>• Single query needed | • Less responsive<br>• Data staleness if Home chain is slow<br>• Fails if Home chain is down |
| Hub-Centered Sync | • Query Home as the authoritative source<br>• Can query Remote for faster local reads | • Consistent data with latency trade-offs<br>• Flexible read patterns<br>• Good for hybrid applications | • Potential temporary inconsistencies<br>• Need to know which chain has latest data<br>• May require timestamp tracking |

## Notes

[1] Ack is designed to ensure there is a working connection between chains and contracts before allowing transfers. This fundamentally assumes L1 availability and no irregular state changes (e.g. a deployed contract's bytecode changes).

[2] It is expected that transfers between spokes will tend to "hop" using the hub.

Multi-hop ICM message fees are paid in the token being transferred, how would this be solved for NFTs? [Ref](https://github.com/ava-labs/icm-contracts/tree/main/contracts/ictt#icm-message-fees)