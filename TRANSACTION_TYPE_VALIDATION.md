# Transaction Type-Specific Validation

## Overview

The SafeTxPool contract now implements transaction type-specific validation to address the security gap in ERC20 token transfers. Previously, the address book guard only validated the `to` address, which for ERC20 transfers is the token contract address, not the actual recipient. This enhancement provides more granular validation based on the transaction type.

## Transaction Types

The system classifies transactions into the following types:

### 1. NATIVE_TRANSFER
- **Description**: ETH transfers with no transaction data
- **Validation**: Recipient address must be in the address book
- **Example**: Sending ETH directly to an address

### 2. ERC20_TRANSFER
- **Description**: ERC20 token transfers using `transfer(address,uint256)`
- **Validation**: 
  - If token contract is trusted: Only recipient must be in address book
  - If token contract is not trusted: Both contract and recipient must be in address book
- **Example**: `token.transfer(recipient, amount)`

### 3. ERC20_TRANSFER_FROM
- **Description**: ERC20 token transfers using `transferFrom(address,address,uint256)`
- **Validation**: Same as ERC20_TRANSFER but extracts recipient from the `to` parameter
- **Example**: `token.transferFrom(from, to, amount)`

### 4. CONTRACT_INTERACTION
- **Description**: General smart contract interactions
- **Validation**:
  - If contract is trusted: No additional validation required
  - If contract is not trusted: Contract must be in the address book
- **Example**: Calling any other contract function

### 5. DELEGATE_CALL
- **Description**: Delegate call operations
- **Validation**:
  - If contract is trusted: No additional validation required
  - If contract is not trusted: Contract must be in the address book
  - Note: Existing delegate call restrictions still apply
- **Example**: Proxy pattern implementations

## Trusted Contracts

The system introduces a "trusted contracts" concept for frequently used contracts like token contracts:

### Benefits
- **Simplified UX**: Users don't need to add every token contract to their address book
- **Enhanced Security**: Recipients are still validated even for trusted contracts
- **Flexibility**: Can be managed per Safe wallet

### Management Functions

```solidity
// Add a trusted contract
function addTrustedContract(address safe, address contractAddress) external;

// Remove a trusted contract
function removeTrustedContract(address safe, address contractAddress) external;

// Check if a contract is trusted
function isTrustedContract(address safe, address contractAddress) external view returns (bool);
```

## Validation Logic

### For ERC20 Transfers

1. **Extract recipient address** from transaction data
2. **Check if token contract is trusted**
3. **Apply validation rules**:
   - Trusted contract: Only validate recipient
   - Non-trusted contract: Validate both contract and recipient

### For Other Transaction Types

- **Native transfers**: Validate recipient address
- **Contract interactions**: Check if contract is trusted, otherwise validate contract address
- **Delegate calls**: Check if contract is trusted, otherwise validate contract address (plus existing delegate call restrictions)

## Error Types

The system introduces new specific error types:

```solidity
error RecipientNotInAddressBook();  // Recipient not in address book
error ContractNotTrusted();         // Contract not trusted and not in address book
```

## Usage Examples

### Setting Up a Safe with Enhanced Trust Model

```solidity
// 1. Add frequently used recipients to address book
safeTxPool.addAddressBookEntry(safeAddress, recipientAddress, "Alice");

// 2. Add trusted contracts (tokens, DEXs, protocols, etc.)
safeTxPool.addTrustedContract(safeAddress, usdcTokenAddress);
safeTxPool.addTrustedContract(safeAddress, daiTokenAddress);
safeTxPool.addTrustedContract(safeAddress, uniswapRouterAddress);
safeTxPool.addTrustedContract(safeAddress, aavePoolAddress);

// 3. Now you can interact with trusted contracts without adding them to address book
// - Send tokens to Alice using trusted token contracts
// - Interact with trusted DEX contracts
// - Use trusted DeFi protocols
```

### ERC20 Transfer Scenarios

#### Scenario 1: Trusted Token Contract
```solidity
// Token is trusted, recipient is in address book ✅
// Only recipient validation required
token.transfer(alice, 100);
```

#### Scenario 2: Non-Trusted Token Contract
```solidity
// Token not trusted, both must be in address book
// 1. Add token to address book
safeTxPool.addAddressBookEntry(safeAddress, tokenAddress, "NewToken");
// 2. Recipient already in address book ✅
token.transfer(alice, 100);
```

#### Scenario 3: Trusted Token, Unknown Recipient
```solidity
// Token is trusted, but recipient not in address book ❌
// Will revert with RecipientNotInAddressBook
token.transfer(unknownAddress, 100);
```

### Contract Interaction Scenarios

#### Scenario 1: Trusted Contract Interaction
```solidity
// Contract is trusted, interaction allowed ✅
uniswapRouter.swapExactTokensForTokens(...);
```

#### Scenario 2: Non-Trusted Contract in Address Book
```solidity
// Contract not trusted, but in address book ✅
// 1. Add contract to address book
safeTxPool.addAddressBookEntry(safeAddress, contractAddress, "MyContract");
// 2. Interaction allowed
myContract.someFunction(...);
```

#### Scenario 3: Non-Trusted Contract Not in Address Book
```solidity
// Contract not trusted and not in address book ❌
// Will revert with ContractNotTrusted
unknownContract.someFunction(...);
```

## Migration Guide

### For Existing Safes

1. **No immediate action required**: Existing address book entries continue to work
2. **Optional optimization**: Add frequently used token contracts as trusted contracts
3. **Enhanced security**: Recipients are now validated for token transfers

### For New Safes

1. **Add recipients** to address book as before
2. **Add trusted contracts** for tokens you frequently use
3. **Enjoy enhanced security** with simplified UX

## Security Considerations

### Enhanced Protection
- **Prevents token theft**: Recipients are validated even for token transfers
- **Maintains compatibility**: Existing address book entries work unchanged
- **Flexible trust model**: Per-Safe trusted contract management

### Best Practices
- **Regular review**: Periodically review trusted contracts
- **Principle of least privilege**: Only trust contracts you frequently interact with
- **Recipient validation**: Always verify recipients are in your address book

## Events

The system emits events for monitoring and debugging:

```solidity
event TrustedContractAdded(address indexed safe, address indexed contractAddress);
event TrustedContractRemoved(address indexed safe, address indexed contractAddress);
event TransactionValidated(address indexed safe, address indexed to, TransactionType txType);
```

## Testing

Comprehensive tests are provided in `test/SafeTxPoolTypeSpecificValidation.t.sol` covering:

- All transaction types
- Trusted contract scenarios
- Error conditions
- Edge cases

Run tests with:
```bash
forge test --match-contract SafeTxPoolTypeSpecificValidationTest
```
