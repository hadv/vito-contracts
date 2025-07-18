# Vito Contracts - Safe Transaction Pool & Guard

This repository contains smart contracts for Safe wallet transaction management and security guards, including a modular SafeTxPool implementation and delegate call restrictions.

## Overview

### SafeGuard
The SafeGuard contract is a guard implementation for the Safe (formerly Gnosis Safe) smart contract wallet. It restricts delegate calls to only allowed target addresses, providing an additional layer of security.

### SafeTxPool (Refactored Modular Architecture)
The SafeTxPool has been refactored into a modular architecture to solve contract size limitations and improve maintainability:

- **SafeTxPoolRegistry**: Main interface contract (13,240 bytes)
- **SafeTxPoolCore**: Core transaction pool functionality (10,595 bytes)
- **AddressBookManager**: Address book management (3,409 bytes)
- **DelegateCallManager**: Delegate call permissions (4,913 bytes)
- **TrustedContractManager**: Trusted contract management (1,650 bytes)
- **TransactionValidator**: Transaction validation logic (5,580 bytes)

**Key Benefits:**
- ✅ All contracts well within 24KB size limit
- ✅ 100% backward compatibility with original SafeTxPool
- ✅ Enhanced security with proper access control
- ✅ Modular design for easier maintenance and upgrades

## Development

This project uses [Foundry](https://github.com/foundry-rs/foundry) for development and testing.

### Install Dependencies

```bash
forge install
```

### Run Tests

```bash
forge test
```

### Run Tests with Coverage

```bash
forge coverage
```

## Deployment Guide

### Prerequisites

1. **Install Foundry**: Follow the [Foundry installation guide](https://book.getfoundry.sh/getting-started/installation)
2. **Clone and setup**:
   ```bash
   git clone https://github.com/hadv/vito-contracts
   cd vito-contracts
   forge install
   ```

### Environment Setup

Create a `.env` file from the example:

```bash
cp .env.example .env
```

Edit `.env` with your values:
```bash
PRIVATE_KEY=your_private_key_without_0x_prefix
RPC_URL=your_rpc_endpoint_url
ETHERSCAN_API_KEY=your_etherscan_api_key_for_verification
```

### Pre-deployment Checks

Always run pre-commit checks before deployment:

```bash
./scripts/pre-commit-check.sh
```

This ensures:
- ✅ Code formatting is correct
- ✅ All contracts build successfully
- ✅ All tests pass (105/105)
- ✅ Contract sizes are within limits

### Deployment Options

#### Option 1: Deploy Refactored SafeTxPool (Recommended)

Deploy the new modular SafeTxPool architecture:

```bash
source .env && forge script script/DeployRefactoredSafeTxPool.s.sol:DeployRefactoredSafeTxPool --rpc-url $RPC_URL --broadcast --verify -vvvv
```

**What gets deployed:**
1. SafeTxPoolCore (transaction management)
2. AddressBookManager (address book functionality)
3. DelegateCallManager (delegate call permissions)
4. TrustedContractManager (trusted contract management)
5. TransactionValidator (validation logic)
6. **SafeTxPoolRegistry** (main interface - use this address)

#### Option 2: Deploy Original SafeTxPool

Deploy the original monolithic SafeTxPool:

```bash
source .env && forge script script/DeploySafeTxPool.s.sol:DeploySafeTxPool --rpc-url $RPC_URL --broadcast --verify -vvvv
```

#### Option 3: Deploy SafeGuard Only

Deploy just the SafeGuard for delegate call restrictions:

```bash
source .env && forge script script/DeploySafeGuard.s.sol:DeploySafeGuard --rpc-url $RPC_URL --broadcast --verify -vvvv
```

### Deployment Flags

- `--verify`: Verify contracts on Etherscan (recommended)
- `--chain-id <id>`: Specify network chain ID
- `--gas-price <price>`: Set specific gas price
- `--legacy`: For networks not supporting EIP-1559
- `-vvvv`: Verbose output for debugging

### Network-Specific Examples

#### Deploy to Ethereum Mainnet
```bash
source .env && forge script script/DeployRefactoredSafeTxPool.s.sol:DeployRefactoredSafeTxPool \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify \
  --chain-id 1 \
  -vvvv
```

#### Deploy to Sepolia Testnet
```bash
source .env && forge script script/DeployRefactoredSafeTxPool.s.sol:DeployRefactoredSafeTxPool \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify \
  --chain-id 11155111 \
  -vvvv
```

#### Deploy to Polygon
```bash
source .env && forge script script/DeployRefactoredSafeTxPool.s.sol:DeployRefactoredSafeTxPool \
  --rpc-url $RPC_URL \
  --broadcast \
  --verify \
  --chain-id 137 \
  -vvvv
```

### Post-Deployment Verification

After deployment, verify the contracts are working correctly:

```bash
# Check contract sizes
forge build --sizes

# Run all tests
forge test

# Check specific contract deployment
cast code <DEPLOYED_CONTRACT_ADDRESS> --rpc-url $RPC_URL
```

## Contract Usage

### SafeTxPool (Refactored) - Recommended

The refactored SafeTxPool provides the same interface as the original but with improved architecture:

#### 1. Basic Setup
```solidity
// Use the SafeTxPoolRegistry address from deployment
SafeTxPoolRegistry pool = SafeTxPoolRegistry(DEPLOYED_REGISTRY_ADDRESS);
```

#### 2. Transaction Pool Functions
```solidity
// Propose a transaction
pool.proposeTx(txHash, safe, to, value, data, operation, nonce);

// Sign a transaction
pool.signTx(txHash, signature);

// Get transaction details
(safe, to, value, data, operation, proposer, nonce, txId) = pool.getTxDetails(txHash);

// Get pending transactions
bytes32[] memory pending = pool.getPendingTxHashes(safe, offset, limit);
```

#### 3. Address Book Management
```solidity
// Add address to Safe's address book (only Safe can call)
pool.addAddressBookEntry(safe, walletAddress, "Recipient Name");

// Remove address from address book
pool.removeAddressBookEntry(safe, walletAddress);

// Get all address book entries
IAddressBookManager.AddressBookEntry[] memory entries = pool.getAddressBookEntries(safe);
```

#### 4. Delegate Call Management
```solidity
// Enable delegate calls for a Safe
pool.setDelegateCallEnabled(safe, true);

// Add allowed delegate call target
pool.addDelegateCallTarget(safe, targetAddress);

// Check if delegate calls are enabled
bool enabled = pool.isDelegateCallEnabled(safe);
```

#### 5. Trusted Contract Management
```solidity
// Add trusted contract (bypasses some validations)
pool.addTrustedContract(safe, tokenAddress);

// Check if contract is trusted
bool trusted = pool.isTrustedContract(safe, contractAddress);
```

#### 6. Guard Functionality
Set the SafeTxPoolRegistry as a Guard on your Safe:

```solidity
// In your Safe wallet, call:
safe.setGuard(DEPLOYED_REGISTRY_ADDRESS);
```

**Benefits of using as Guard:**
- ✅ Automatic transaction validation
- ✅ Address book enforcement
- ✅ Delegate call restrictions
- ✅ Automatic execution tracking
- ✅ Enhanced security for Safe transactions

### SafeGuard (Standalone)

For delegate call restrictions only:

```solidity
SafeGuard guard = SafeGuard(DEPLOYED_GUARD_ADDRESS);

// Add allowed target for delegate calls
guard.addAllowedTarget(targetAddress);

// Set as guard on Safe
safe.setGuard(address(guard));
```

### Migration from Original SafeTxPool

The refactored SafeTxPool is **100% backward compatible**:

```solidity
// Old code works unchanged
SafeTxPool pool = SafeTxPool(DEPLOYED_REGISTRY_ADDRESS);
pool.proposeTx(...); // Same function signature
pool.addAddressBookEntry(...); // Same function signature
// All existing functions work identically
```

**Migration steps:**
1. Deploy the refactored SafeTxPool using the deployment script
2. Update your contract addresses to use the SafeTxPoolRegistry address
3. No code changes required - all functions work identically
4. Optionally update Safe Guards to use the new registry address

## Troubleshooting

### Common Issues

#### 1. Contract Size Limit Error
```
Error: some contracts exceed the runtime size limit (EIP-170: 24576 bytes)
```
**Solution**: Use the refactored SafeTxPool deployment instead of the original.

#### 2. Build Failures
```bash
# Clean and rebuild
forge clean
forge build

# Check formatting
forge fmt --check
```

#### 3. Test Failures
```bash
# Run specific test
forge test --match-contract SafeTxPool -vvv

# Run with gas reporting
forge test --gas-report
```

#### 4. Deployment Issues
- Ensure sufficient ETH balance for gas
- Check RPC URL is correct
- Verify private key format (no 0x prefix)
- For verification, ensure ETHERSCAN_API_KEY is set

### Getting Help

- **Documentation**: See [REFACTORING_GUIDE.md](REFACTORING_GUIDE.md) for detailed architecture information
- **Issues**: Report bugs on [GitHub Issues](https://github.com/hadv/vito-contracts/issues)
- **Testing**: Run `./scripts/pre-commit-check.sh` for comprehensive checks

## Architecture

For detailed information about the refactored architecture, contract interactions, and migration guide, see:
- 📖 [REFACTORING_GUIDE.md](REFACTORING_GUIDE.md) - Comprehensive refactoring documentation
- 🧪 [test/](test/) - Test files with usage examples
- 📜 [script/](script/) - Deployment scripts

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
