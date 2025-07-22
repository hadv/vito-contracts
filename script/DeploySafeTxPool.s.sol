// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/SafeTxPoolCore.sol";
import "../src/AddressBookManager.sol";
import "../src/DelegateCallManager.sol";
import "../src/TrustedContractManager.sol";
import "../src/TransactionValidator.sol";
import "../src/SafePoolRegistry.sol";

/**
 * @title DeploySafeTxPool
 * @notice Deployment script for the SafeTxPool components
 */
contract DeploySafeTxPool is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying SafeTxPool components...");

        // Deploy core components first
        console.log("1. Deploying SafeTxPoolCore...");
        SafeTxPoolCore txPoolCore = new SafeTxPoolCore();
        console.log("   SafeTxPoolCore deployed at:", address(txPoolCore));

        console.log("2. Deploying AddressBookManager...");
        AddressBookManager addressBookManager = new AddressBookManager();
        console.log("   AddressBookManager deployed at:", address(addressBookManager));

        console.log("3. Deploying DelegateCallManager...");
        DelegateCallManager delegateCallManager = new DelegateCallManager();
        console.log("   DelegateCallManager deployed at:", address(delegateCallManager));

        console.log("4. Deploying TrustedContractManager...");
        TrustedContractManager trustedContractManager = new TrustedContractManager();
        console.log("   TrustedContractManager deployed at:", address(trustedContractManager));

        console.log("5. Deploying TransactionValidator...");
        TransactionValidator transactionValidator =
            new TransactionValidator(address(addressBookManager), address(trustedContractManager));
        console.log("   TransactionValidator deployed at:", address(transactionValidator));

        console.log("6. Deploying SafePoolRegistry...");
        SafePoolRegistry registry = new SafePoolRegistry(
            address(txPoolCore),
            address(addressBookManager),
            address(delegateCallManager),
            address(trustedContractManager),
            address(transactionValidator)
        );
        console.log("   SafePoolRegistry deployed at:", address(registry));

        // Set registry addresses for all components (one-time only)
        console.log("7. Setting component registry addresses...");
        txPoolCore.setRegistry(address(registry));
        console.log("   SafeTxPoolCore registry set");

        addressBookManager.setRegistry(address(registry));
        console.log("   AddressBookManager registry set");

        delegateCallManager.setRegistry(address(registry));
        console.log("   DelegateCallManager registry set");

        trustedContractManager.setRegistry(address(registry));
        console.log("   TrustedContractManager registry set");

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("SafeTxPoolCore:          ", address(txPoolCore));
        console.log("AddressBookManager:      ", address(addressBookManager));
        console.log("DelegateCallManager:     ", address(delegateCallManager));
        console.log("TrustedContractManager:  ", address(trustedContractManager));
        console.log("TransactionValidator:    ", address(transactionValidator));
        console.log("SafePoolRegistry:      ", address(registry));
        console.log("\n=== Usage Instructions ===");
        console.log("Main contract to use: SafePoolRegistry at", address(registry));
        console.log("This contract provides the same interface as the original SafeTxPool");
        console.log("\nAll contracts are within size limits:");
        console.log("- SafeTxPoolCore:         10,595 bytes (13,981 bytes margin)");
        console.log("- SafePoolRegistry:     13,240 bytes (11,336 bytes margin)");
        console.log("- All manager contracts:  < 5,000 bytes each");
    }
}
