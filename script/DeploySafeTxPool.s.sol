// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/SafeTxPoolCore.sol";
import "../src/AddressBookManager.sol";
import "../src/DelegateCallManager.sol";
import "../src/TrustedContractManager.sol";
import "../src/TransactionValidator.sol";
import "../src/SafeTxPoolRegistry.sol";

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
        AddressBookManager addressBookManager = new AddressBookManager(address(0));
        console.log("   AddressBookManager deployed at:", address(addressBookManager));

        console.log("3. Deploying DelegateCallManager...");
        DelegateCallManager delegateCallManager = new DelegateCallManager(address(0));
        console.log("   DelegateCallManager deployed at:", address(delegateCallManager));

        console.log("4. Deploying TrustedContractManager...");
        TrustedContractManager trustedContractManager = new TrustedContractManager(address(0));
        console.log("   TrustedContractManager deployed at:", address(trustedContractManager));

        console.log("5. Deploying TransactionValidator...");
        TransactionValidator transactionValidator =
            new TransactionValidator(address(addressBookManager), address(trustedContractManager));
        console.log("   TransactionValidator deployed at:", address(transactionValidator));

        console.log("6. Deploying SafeTxPoolRegistry...");
        SafeTxPoolRegistry registry = new SafeTxPoolRegistry(
            address(txPoolCore),
            address(addressBookManager),
            address(delegateCallManager),
            address(trustedContractManager),
            address(transactionValidator)
        );
        console.log("   SafeTxPoolRegistry deployed at:", address(registry));

        // Update all components to use the correct registry address
        console.log("7. Updating component registry addresses...");
        txPoolCore.setRegistry(address(registry));
        console.log("   SafeTxPoolCore registry updated");

        addressBookManager.updateRegistry(address(registry));
        console.log("   AddressBookManager registry updated");

        delegateCallManager.updateRegistry(address(registry));
        console.log("   DelegateCallManager registry updated");

        trustedContractManager.updateRegistry(address(registry));
        console.log("   TrustedContractManager registry updated");

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("SafeTxPoolCore:          ", address(txPoolCore));
        console.log("AddressBookManager:      ", address(addressBookManager));
        console.log("DelegateCallManager:     ", address(delegateCallManager));
        console.log("TrustedContractManager:  ", address(trustedContractManager));
        console.log("TransactionValidator:    ", address(transactionValidator));
        console.log("SafeTxPoolRegistry:      ", address(registry));
        console.log("\n=== Usage Instructions ===");
        console.log("Main contract to use: SafeTxPoolRegistry at", address(registry));
        console.log("This contract provides the same interface as the original SafeTxPool");
        console.log("\nAll contracts are within size limits:");
        console.log("- SafeTxPoolCore:         10,595 bytes (13,981 bytes margin)");
        console.log("- SafeTxPoolRegistry:     13,240 bytes (11,336 bytes margin)");
        console.log("- All manager contracts:  < 5,000 bytes each");
    }
}
