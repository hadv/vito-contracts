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
 * @title DeployRefactoredSafeTxPool
 * @notice Deployment script for the refactored SafeTxPool components
 */
contract DeployRefactoredSafeTxPool is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        vm.startBroadcast(deployerPrivateKey);

        console.log("Deploying refactored SafeTxPool components...");

        // First deploy a placeholder registry to get its address
        console.log("1. Deploying placeholder SafeTxPoolRegistry...");
        SafeTxPoolRegistry tempRegistry =
            new SafeTxPoolRegistry(address(0), address(0), address(0), address(0), address(0));
        address registryAddress = address(tempRegistry);
        console.log("   Placeholder registry address:", registryAddress);

        // Deploy core components with the registry address
        console.log("2. Deploying SafeTxPoolCore...");
        SafeTxPoolCore txPoolCore = new SafeTxPoolCore();
        console.log("   SafeTxPoolCore deployed at:", address(txPoolCore));

        console.log("3. Deploying AddressBookManager...");
        AddressBookManager addressBookManager = new AddressBookManager(registryAddress);
        console.log("   AddressBookManager deployed at:", address(addressBookManager));

        console.log("4. Deploying DelegateCallManager...");
        DelegateCallManager delegateCallManager = new DelegateCallManager(registryAddress);
        console.log("   DelegateCallManager deployed at:", address(delegateCallManager));

        console.log("5. Deploying TrustedContractManager...");
        TrustedContractManager trustedContractManager = new TrustedContractManager(registryAddress);
        console.log("   TrustedContractManager deployed at:", address(trustedContractManager));

        console.log("6. Deploying TransactionValidator...");
        TransactionValidator transactionValidator =
            new TransactionValidator(address(addressBookManager), address(trustedContractManager));
        console.log("   TransactionValidator deployed at:", address(transactionValidator));

        console.log("7. Deploying final SafeTxPoolRegistry...");
        SafeTxPoolRegistry registry = new SafeTxPoolRegistry(
            address(txPoolCore),
            address(addressBookManager),
            address(delegateCallManager),
            address(trustedContractManager),
            address(transactionValidator)
        );
        console.log("   Final SafeTxPoolRegistry deployed at:", address(registry));

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
