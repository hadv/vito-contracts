// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/SafeTxPoolRegistry.sol";
import "../src/SafeTxPoolCore.sol";
import "../src/AddressBookManager.sol";
import "../src/DelegateCallManager.sol";
import "../src/TrustedContractManager.sol";
import "../src/TransactionValidator.sol";
import "../src/interfaces/ITrustedContractManager.sol";

contract TrustedContractExample is Script {
    function run() external {
        console.log("=== Trusted Contract Management Example ===");

        // Deploy all components
        SafeTxPoolCore txPoolCore = new SafeTxPoolCore();
        AddressBookManager addressBookManager = new AddressBookManager();
        DelegateCallManager delegateCallManager = new DelegateCallManager();
        TrustedContractManager trustedContractManager = new TrustedContractManager();
        TransactionValidator transactionValidator =
            new TransactionValidator(address(addressBookManager), address(trustedContractManager));

        // Deploy registry
        SafeTxPoolRegistry pool = new SafeTxPoolRegistry(
            address(txPoolCore),
            address(addressBookManager),
            address(delegateCallManager),
            address(trustedContractManager),
            address(transactionValidator)
        );

        // Set registry addresses for all components (one-time only)
        txPoolCore.setRegistry(address(pool));
        addressBookManager.setRegistry(address(pool));
        delegateCallManager.setRegistry(address(pool));
        trustedContractManager.setRegistry(address(pool));

        console.log("SafeTxPool deployed at:", address(pool));

        // Example Safe and contract addresses
        address safe = address(0x1234567890123456789012345678901234567890);
        address usdcToken = address(0xa0B86A33e6441e6E80D0C4C6C7527D72E1d7e1e1);
        address daiToken = address(0xB0b86a33e6441e6e80D0c4c6C7527d72e1D7e1e2);
        address uniswapRouter = address(0xc0b86a33E6441E6E80d0c4C6c7527d72E1d7E1e3);

        console.log("Example Safe address:", safe);
        console.log("USDC Token address:", usdcToken);
        console.log("DAI Token address:", daiToken);
        console.log("Uniswap Router address:", uniswapRouter);

        // Simulate Safe calling the functions
        vm.startPrank(safe);

        console.log("\n=== Adding Trusted Contracts ===");

        // Add trusted contracts with names
        pool.addTrustedContract(safe, usdcToken, "USDC Token");
        console.log("Added USDC Token as trusted contract");

        pool.addTrustedContract(safe, daiToken, "DAI Token");
        console.log("Added DAI Token as trusted contract");

        pool.addTrustedContract(safe, uniswapRouter, "Uniswap V3 Router");
        console.log("Added Uniswap Router as trusted contract");

        console.log("\n=== Checking Trusted Status ===");

        // Check if contracts are trusted
        console.log("USDC is trusted:", pool.isTrustedContract(safe, usdcToken));
        console.log("DAI is trusted:", pool.isTrustedContract(safe, daiToken));
        console.log("Uniswap Router is trusted:", pool.isTrustedContract(safe, uniswapRouter));

        // Check a non-trusted contract
        address randomContract = address(0xDEADBEEF);
        console.log("Random contract is trusted:", pool.isTrustedContract(safe, randomContract));

        console.log("\n=== Getting All Trusted Contracts ===");

        // Get all trusted contracts
        ITrustedContractManager.TrustedContractEntry[] memory trustedContracts = pool.getTrustedContracts(safe);
        console.log("Total trusted contracts:", trustedContracts.length);

        for (uint256 i = 0; i < trustedContracts.length; i++) {
            console.log("Contract", i + 1, ":");
            console.log("  Address:", trustedContracts[i].contractAddress);
            console.log("  Name:", string(abi.encodePacked(trustedContracts[i].name)));
        }

        console.log("\n=== Updating Contract Name ===");

        // Update a contract name
        pool.addTrustedContract(safe, uniswapRouter, "Uniswap V3 Router v2");
        console.log("Updated Uniswap Router name");

        // Get updated list
        trustedContracts = pool.getTrustedContracts(safe);
        for (uint256 i = 0; i < trustedContracts.length; i++) {
            if (trustedContracts[i].contractAddress == uniswapRouter) {
                console.log("Updated Uniswap Router name:", string(abi.encodePacked(trustedContracts[i].name)));
                break;
            }
        }

        console.log("\n=== Removing Trusted Contract ===");

        // Remove a trusted contract
        pool.removeTrustedContract(safe, daiToken);
        console.log("Removed DAI Token from trusted contracts");

        // Check updated status
        console.log("DAI is still trusted:", pool.isTrustedContract(safe, daiToken));

        // Get final list
        trustedContracts = pool.getTrustedContracts(safe);
        console.log("Final trusted contracts count:", trustedContracts.length);

        vm.stopPrank();

        console.log("\n=== Example Complete ===");
    }
}
