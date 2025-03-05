# Safe Guard Contracts

This repository contains smart contracts for Safe Guard implementation, which provides delegate call restrictions for Safe multisig wallets.

## Overview

The SafeGuard contract is a guard implementation for the Safe (formerly Gnosis Safe) smart contract wallet. It restricts delegate calls to only allowed target addresses, providing an additional layer of security.

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

After deployment, the SafeGuard can be:
1. Set as a guard on a Safe wallet
2. Configured with allowed target addresses for delegate calls
3. Managed by the owner to add/remove allowed targets

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
