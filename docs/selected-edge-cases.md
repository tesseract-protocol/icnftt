
### Selected edge cases:

These edge cases are presented without solution to describe common traits of implementation challenges and better classify them.

| # | Location | Edge Case | Relative Difficulty | Description |
|---|----------|-----------|---------------------|-------------|
| 1 | Remote → Home | Writing `mint()` | Easy | Remote contract needs to initiate minting of a token on the Home chain |
| 2 | Home | Reading `totalSupply()` | Easy | Home needs to provide an accurate count of all NFTs in existence for canonical reference |
| 3 | Remote | Reading `totalSupply()` | Hard | Remote needs to account for tokens that exist on Home chain but haven't been bridged |
| 4 | Remote | Reading `ownerOf(id)` for non-bridged tokens | Hard | Remote contract is queried about ownership of a token that exists on Home but hasn't been transferred to this chain |
| 5 | Both | Handling token approvals across chains | Hard | Determining whether approvals granted on one chain should be valid on another chain |
| 6 | Both | Reading `ERC721Enumerable` functions | Hard | Ensuring `tokenByIndex()` and other enumeration functions return globally consistent results across all chains |
| 7 | Home → Remote | Collection-wide metadata changes | Medium | Updates to collection-level metadata on Home need to be propagated to all Remote implementations + auth checks |

#### Example: Handling Token Approvals Across Chains

When a user approves an address to transfer their token on the Home chain:

| State Sync Approach | Implementation | Considerations |
|---------------------|----------------|----------------|
| Autonomous Remote | • Approvals only apply on the chain where granted<br>• No synchronization of approval state | • Simplest implementation<br>• Users must explicitly approve on each chain<br>• Clear mental model but potentially confusing UX |
| Acknowledge Change | • Approvals on Home are mirrored on Remote after confirmation<br>• Approvals on Remote require Home validation | • Consistent approval state across chains<br>• Higher gas costs<br>• Approval operations have higher latency |
| Hub-Centered Sync | • All approval operations are recorded on Home<br>• Remote chains check Home for approval status | • Single source of truth for approvals<br>• High latency for approval checks<br>• Higher cross-chain messaging costs |

### Examples

We mint tokens on Home, then lock and transfer them to remote ERC721.
- We transfer Home id #99 to Remote.

| State Sync Approach | Home State | Remote State | Pros | Cons |
|-------------------|------------|--------------|------|------|
| Autonomous Remote | Home maintains token ownership records but doesn't track remote operations | Remote operates independently with occasional updates to Home | • Minimal cross-chain communication<br>• Lower gas costs<br>• Better performance | • Potential data inconsistencies<br>• Difficult to resolve conflicts<br>• Home chain has incomplete picture |
| Acknowledge Change | Home holds pending operations until confirmed by Remote | Remote waits for Home approval before executing operations | • Strong consistency guarantees<br>• Clear audit trail<br>• Prevents invalid operations | • Higher latency for operations<br>• More expensive (2x messages)<br>• Vulnerable to chain outages |
| Hub-Centered Sync | Home is the source of truth and records all operations | Remote forwards all operations to Home and syncs state | • Single source of truth<br>• Guaranteed consistency<br>• Simplifies recovery scenarios | • Highest cross-chain message volume<br>• Highest gas costs<br>• Remote operations blocked if Home is unavailable |

Example for transferring NFT ID #99 from a Home to Remote:

| State Sync Approach | Home State Changes | Remote State Changes |
|-------------------|-------------------|---------------------|
| Autonomous Remote | • Lock token #99<br>• Record transfer to Remote chain | • Mint representation of token #99<br>• Assign to recipient<br>• No confirmation back to Home |
| Acknowledge Change | • Lock token #99<br>• Create pending transfer record<br>• Finalize transfer after Remote ack | • Request approval from Home for #99<br>• Wait for approval<br>• Mint representation only after approval<br>• Send confirmation to Home |
| Hub-Centered Sync | • Lock token #99<br>• Record transfer to Remote chain<br>• Update metadata when Remote reports changes | • Mint representation of token #99<br>• Assign to recipient<br>• Send confirmation to Home<br>• Send all metadata changes back to Home |

Example for updating metadata URL on NFT ID #99:

| State Sync Approach | Home State Changes | Remote State Changes |
|-------------------|-------------------|---------------------|
| Autonomous Remote | • No changes on Home<br>• No awareness of metadata update | • Update metadata URL for token #99<br>• Home chain unaware of changes<br>• Metadata inconsistent between chains |
| Acknowledge Change | • Receive metadata update request<br>• Verify and approve update<br>• Update canonical metadata | • Request approval for metadata change<br>• Wait for Home approval<br>• Apply metadata update only after approval<br>• Consistent metadata across chains |
| Hub-Centered Sync | • Receive notification of metadata update<br>• Update canonical metadata to match Remote | • Update metadata URL for token #99<br>• Send metadata update back to Home<br>• Eventual consistency after sync completes |
