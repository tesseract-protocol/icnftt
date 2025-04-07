# Creator Fee Enforcement for ICNFTT

## Overview

This document outlines the implementation of creator fee enforcement for ICNFTT tokens, ensuring that creator fees are properly enforced across any combination of Home and Remote chains.

OpenSea and the recommended Limit Break 721C token was used for reference in creating this document.
* [Open Sea Creator Fee Enforcement](https://opensea.io/blog/articles/creator-earnings-erc721-c-compatibility-on-opensea)
* [Limit Break Creator Token Standards](https://apptokens.com/docs/integration-guide/creator-token-standards/overview)

In case a token does not need to enforce Royalty fees (e.g. Home token on a chain without a marketplace), the enforcement for that token may be skipped by not supplying a verification function.

## State Sync Model for ICNFTT

We recommend that ownership functions are controlled exclusively from the Home chain (using the "Hub-Push Async" model).

1. **Home Chain**:
   - Acts as the source of truth for creator fee settings
   - Pushes fee updates to Remote chains
   - Maintains the transfer validator registry by chain
   - Can independently enable/disable fee enforcement by chain

2. **Remote Chains**:
   - Receive fee updates from Home
   - Maintain local transfer validator state
   - Enforce fees locally without requiring Home chain validation

The reasons supporting this recomendation:

- `owner()` remains singularly controlled on the canonical chain
- Home chain updates do not depend on Remote chain availablity
- Updates to Remote tokens will have minor latency and temporary inconsistencies, which is a good middle ground for infrequent actions

## Implementation Requirements

Reference: https://docs.opensea.io/docs/creator-fee-enforcement

### 1. Transfer Validator System

- Uses `StrictAuthorizedTransferSecurityRegistry` or `CreatorTokenTransferValidator`
- Acts as an authorizer through the `SignedZone`
- Validates transfers before and after they occur
- Sets and unsets flags for approving specific:
  - Operators
  - Token IDs
  - Token ID & amount combinations

### 2. Interfaces

#### OpenSea Creator Token Interface

Both Home and Remote tokens must implement OpenSea's `ICreatorToken` interface:

```solidity
interface ICreatorToken {
    event TransferValidatorUpdated(address oldValidator, address newValidator);
    function getTransferValidator() external view returns (address validator);
    function getTransferValidationFunction() external view
        returns (bytes4 functionSignature, bool isViewFunction);
    function setTransferValidator(address validator) external;
}
```

#### ICNFTT and Fee Enforcement

ICNFTT manages fee enforcement by passing verification rule updates from Home to Remote.

For example: Limit Break's 721C [Transfer Security Levels](https://apptokens.com/docs/integration-guide/creator-token-standards/v4/for-creators/transfer-security#transfer-security-levels) 
- Home and Remote use independent Transfer Security Levels and access lists
- Home manages Remote

**Important note:** higher `Transfer Security Levels` will be incompatible with ICNFTT by default. For example, blocking receives by Code Length Checks could also block the ICM functionality.

// todo: double-check how the special functions work because code length returns zero for some contract addresses which have contract-like functionality

### 3. Transfer Validation Functions

Both Home and Remote tokens must implement a validation functions in their `_beforeTokenTransfer` hook:

```solidity
// For ERC-721 tokens
function validateTransfer(address caller, address from, address to, uint256 tokenId) external view;
```

The function must be assigned as the transfer validator (if one is set) and `getTransferValidationFunction()` must return the correct function selector.

## Implementation Steps

### 1. Home Token Implementation

```solidity
contract ICNFTTHome is ERC721, ICreatorToken, IICNFTTFeeEnforcement {
    address private _transferValidator;
    bool private _feeEnforcementEnabled;
    
    constructor(address transferValidator) {
        _transferValidator = transferValidator;
        _feeEnforcementEnabled = true; // Default to enabled
    }
    
    // ICreatorToken implementation
    function getTransferValidator() external view returns (address) {
        return _transferValidator;
    }
    
    function getTransferValidationFunction() external view 
        returns (bytes4 functionSignature, bool isViewFunction) {
        return (this.validateTransfer.selector, true);
    }
    
    function setTransferValidator(address validator) external onlyOwner {
        address oldValidator = _transferValidator;
        _transferValidator = validator;
        emit TransferValidatorUpdated(oldValidator, validator);
        
        // Push validator update to all Remote chains
        _pushValidatorUpdate(validator);
    }
    
    // IICNFTTFeeEnforcement implementation
    function toggleFeeEnforcement(bool enabled) external onlyOwner {
        _feeEnforcementEnabled = enabled;
        emit FeeEnforcementToggled(enabled);
    }
    
    function isFeeEnforcementEnabled() external view returns (bool) {
        return _feeEnforcementEnabled;
    }
    
    function validateTransfer(
        address caller,
        address from,
        address to,
        uint256 tokenId
    ) external view {
        if (!_feeEnforcementEnabled) return;
        
        // Validate transfer through transfer validator
        ITransferValidator(_transferValidator).validateTransfer(
            caller,
            from,
            to,
            tokenId
        );
    }
    
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, tokenId);
        
        // Validate transfer before it occurs if enforcement is enabled
        if (_feeEnforcementEnabled && from != address(0) && to != address(0)) {
            validateTransfer(msg.sender, from, to, tokenId);
        }
    }
}
```

### 2. Remote Token Implementation

```solidity
contract ICNFTTRemote is ERC721, ICreatorToken, IICNFTTFeeEnforcement {
    address private _transferValidator;
    bool private _feeEnforcementEnabled;
    address private immutable _homeAddress;
    
    modifier onlyHome() {
        // todo: update for icm originator
        require(msg.sender == _homeAddress, "Caller is not the Home contract");
        _;
    }
    
    constructor(
        address transferValidator,
        address homeAddress
    ) {
        _transferValidator = transferValidator;
        _homeAddress = homeAddress;
        _feeEnforcementEnabled = true; // Default to enabled
    }
    
    // ICreatorToken implementation
    function getTransferValidator() external view returns (address) {
        return _transferValidator;
    }
    
    function getTransferValidationFunction() external view 
        returns (bytes4 functionSignature, bool isViewFunction) {
        return (this.validateTransfer.selector, true);
    }
    
    function setTransferValidator(address validator) external onlyHome {
        address oldValidator = _transferValidator;
        _transferValidator = validator;
        emit TransferValidatorUpdated(oldValidator, validator);
    }
    
    // IICNFTTFeeEnforcement implementation
    function toggleFeeEnforcement(bool enabled) external onlyOwner {
        _feeEnforcementEnabled = enabled;
        emit FeeEnforcementToggled(enabled);
    }
    
    function isFeeEnforcementEnabled() external view returns (bool) {
        return _feeEnforcementEnabled;
    }
    
    function validateTransfer(
        address caller,
        address from,
        address to,
        uint256 tokenId
    ) external view {
        if (!_feeEnforcementEnabled) return;
        
        // Validate transfer through transfer validator
        ITransferValidator(_transferValidator).validateTransfer(
            caller,
            from,
            to,
            tokenId
        );
    }
    
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 tokenId
    ) internal virtual override {
        super._beforeTokenTransfer(from, to, tokenId);
        
        // Validate transfer before it occurs if enforcement is enabled
        if (_feeEnforcementEnabled && from != address(0) && to != address(0)) {
            validateTransfer(msg.sender, from, to, tokenId);
        }
    }
}
```

## Integration with OpenSea

To integrate with OpenSea's creator fee enforcement:

1. **Order Requirements**:
   - Use order type: `FULL_RESTRICTED` or `PARTIAL_RESTRICTED`
   - Set zone to SignedZone
   - Use `fulfillAdvancedOrder`, `fulfillAvailableAdvancedOrders`, or `matchAdvancedOrders`
   - Include `extraData` following SIP-7 specification
   - Only enforce when fee enforcement is enabled on the chain

2. **Function Signatures**:
   - `0xcaee23ea`: validateTransfer(address,address,address,uint256)

3. **SIP-7 ExtraData Substandards**:
   - Substandard 7: For operator-level validation
   - Substandard 8: For ERC-721 token validation

## Other Integration Considerations

1. **Validator Updates**:
   - Only Home chain can update the transfer validator
   - Updates do not need to be atomic
   - Fee enforcement can be configured independently for each chain

2. **Transfer Validation**:
   - All transfers must be validated before execution when enabled
   - Failed validations should revert the transaction
   - Validation should be gas-efficient
   - Validation can be skipped when fee enforcement is disabled

3. **Cross-Chain Consistency**:
   - Fee settings should be consistent across chains when enabled
   - Remote chains should maintain local validator state
   - Failed updates should be retried
   - Each chain can independently manage fee enforcement
