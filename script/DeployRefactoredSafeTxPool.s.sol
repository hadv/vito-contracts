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

        // Deploy core components
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
        TransactionValidator transactionValidator = new TransactionValidator(
            address(addressBookManager),
            address(trustedContractManager)
        );
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

        vm.stopBroadcast();

        console.log("\n=== Deployment Summary ===");
        console.log("SafeTxPoolCore:          ", address(txPoolCore));
        console.log("AddressBookManager:      ", address(addressBookManager));
        console.log("DelegateCallManager:     ", address(delegateCallManager));
        console.log("TrustedContractManager:  ", address(trustedContractManager));
        console.log("TransactionValidator:    ", address(transactionValidator));
        console.log("SafeTxPoolRegistry:      ", address(registry));
        console.log("\nMain contract to use: SafeTxPoolRegistry at", address(registry));
        console.log("This contract provides the same interface as the original SafeTxPool");
    }
}
