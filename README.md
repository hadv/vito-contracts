# Safe Guard Contracts

This repository contains smart contracts for Safe Guard implementation, which provides delegate call restrictions for Safe multisig wallets.

## Overview

The SafeGuard contract is a guard implementation for the Safe (formerly Gnosis Safe) smart contract wallet. It restricts delegate calls to only allowed target addresses, providing an additional layer of security.

The SafeTxPool contract serves as both a transaction pool for Safe transactions and can also function as a Guard that automatically marks transactions as executed after they are processed by the Safe.

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

### 1. Environment Setup

First, create a `.env` file from the example:

```bash
cp .env.example .env
```

Edit `.env` with your values:
```
PRIVATE_KEY=your_private_key_without_0x
RPC_URL=your_rpc_url
```

### 2. Deploy Contract

Source the environment variables and run the deployment script:

```bash
source .env && forge script script/DeploySafeGuard.s.sol:DeploySafeGuard --rpc-url $RPC_URL --broadcast -vvvv
```

For deploying the SafeTxPool:

```bash
source .env && forge script script/DeploySafeTxPool.s.sol:DeploySafeTxPool --rpc-url $RPC_URL --broadcast -vvvv
```

#### Optional Deployment Flags

- `--verify`: Verify contract on Etherscan
- `--chain-id <id>`: Specify network chain ID
- `--gas-price <price>`: Set specific gas price
- `--legacy`: For networks not supporting EIP-1559

#### Example: Deploy to Sepolia

```bash
source .env && forge script script/DeploySafeGuard.s.sol:DeploySafeGuard --rpc-url $RPC_URL --broadcast --chain-id 11155111 -vvvv
```

## Contract Usage

### SafeGuard

After deployment, the SafeGuard can be:
1. Set as a guard on a Safe wallet
2. Configured with allowed target addresses for delegate calls
3. Managed by the owner to add/remove allowed targets

### SafeTxPool

The SafeTxPool contract has dual functionality:

1. **Transaction Pool**:
   - Propose transactions for Safe wallets
   - Collect signatures from owners
   - Track pending transactions
   - Mark transactions as executed

2. **Guard for Automatic Execution Tracking**:
   - Implements the Guard interface
   - Can be set as a Guard on Safe wallets
   - Automatically marks transactions as executed in the pool when they are executed by the Safe
   - Directly uses the same transaction hash as the Safe itself (no mapping required)

To use the SafeTxPool as a Guard:
1. Deploy the SafeTxPool contract
2. Set it as a Guard on your Safe wallet using `setGuard`
3. When a transaction is executed by the Safe, the guard's `checkAfterExecution` will automatically mark it as executed in the pool

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
# CI Debug
