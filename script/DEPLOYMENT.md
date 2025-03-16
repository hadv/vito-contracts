# SafeTxPool Deployment Guide

This guide explains how to deploy the SafeTxPool contract using Foundry.

## Prerequisites

1. Install Foundry:
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

2. Clone the repository and install dependencies:
```bash
git clone <repository-url>
cd <repository-name>
forge install
```

## Deployment Steps

1. Create a `.env` file in the root directory with your configuration:
```bash
# Required
PRIVATE_KEY=your_private_key_here
NETWORK=SEPOLIA  # or MAINNET

# Network RPC URLs
SEPOLIA_RPC_URL=your_sepolia_rpc_url
MAINNET_RPC_URL=your_mainnet_rpc_url

# Optional (for contract verification)
ETHERSCAN_API_KEY=your_etherscan_api_key
```

2. Load the environment variables:
```zsh
source .env
```

3. Deploy the contract:
```zsh
# Deploy and verify (for public networks)
RPC_URL_VAR="${NETWORK}_RPC_URL"
forge script script/DeploySafeTxPool.s.sol \
    --fork-url "${(P)RPC_URL_VAR}" \
    --broadcast \
    --verify

# Or deploy without verification (for local testing)
forge script script/DeploySafeTxPool.s.sol \
    --fork-url http://localhost:8545 \
    --broadcast
```

## Contract Verification

For public networks (Sepolia, Mainnet), the contract will be automatically verified on Etherscan if you:
1. Include the `ETHERSCAN_API_KEY` in your `.env` file
2. Use the `--verify` flag in the deployment command (as shown above)

## Contract Addresses

After deployment, keep track of the deployed contract addresses:

| Network | Address |
|---------|---------|
| Local   | -       |
| Sepolia | `0xa2ad21dc93B362570D0159b9E3A2fE5D8ecA0424` |
| Mainnet | -       | 