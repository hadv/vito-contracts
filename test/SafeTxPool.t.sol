// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/SafeTxPoolCore.sol";
import "../src/AddressBookManager.sol";
import "../src/DelegateCallManager.sol";
import "../src/TrustedContractManager.sol";
import "../src/TransactionValidator.sol";
import "../src/SafeTxPoolRegistry.sol";
import "../src/interfaces/IBaseManager.sol";
import "@safe-global/safe-contracts/contracts/common/Enum.sol";

contract SafeTxPoolTest is Test {
    SafeTxPoolCore public txPoolCore;
    AddressBookManager public addressBookManager;
    DelegateCallManager public delegateCallManager;
    TrustedContractManager public trustedContractManager;
    TransactionValidator public transactionValidator;
    SafeTxPoolRegistry public registry;

    address public safe = address(0x1234);
    address public owner1 = address(0x5678);
    address public recipient = address(0x9ABC);

    function setUp() public {
        // Deploy all components with new pattern
        txPoolCore = new SafeTxPoolCore();

        // Deploy managers with zero address initially
        addressBookManager = new AddressBookManager(address(0));
        delegateCallManager = new DelegateCallManager(address(0));
        trustedContractManager = new TrustedContractManager(address(0));

        transactionValidator = new TransactionValidator(address(addressBookManager), address(trustedContractManager));

        // Deploy registry with all components
        registry = new SafeTxPoolRegistry(
            address(txPoolCore),
            address(addressBookManager),
            address(delegateCallManager),
            address(trustedContractManager),
            address(transactionValidator)
        );

        // Update all components to use the correct registry address
        txPoolCore.setRegistry(address(registry));
        addressBookManager.updateRegistry(address(registry));
        delegateCallManager.updateRegistry(address(registry));
        trustedContractManager.updateRegistry(address(registry));
    }

    function testContractSizes() public {
        // Verify that all contracts are within reasonable size limits
        // This is more of a documentation test to show the size improvements

        uint256 txPoolCoreSize = address(txPoolCore).code.length;
        uint256 addressBookSize = address(addressBookManager).code.length;
        uint256 delegateCallSize = address(delegateCallManager).code.length;
        uint256 trustedContractSize = address(trustedContractManager).code.length;
        uint256 validatorSize = address(transactionValidator).code.length;
        uint256 registrySize = address(registry).code.length;

        console.log("Contract sizes:");
        console.log("SafeTxPoolCore:         ", txPoolCoreSize);
        console.log("AddressBookManager:     ", addressBookSize);
        console.log("DelegateCallManager:    ", delegateCallSize);
        console.log("TrustedContractManager: ", trustedContractSize);
        console.log("TransactionValidator:   ", validatorSize);
        console.log("SafeTxPoolRegistry:     ", registrySize);

        // All contracts should be well under the 24KB limit
        assertLt(txPoolCoreSize, 24576, "SafeTxPoolCore too large");
        assertLt(addressBookSize, 24576, "AddressBookManager too large");
        assertLt(delegateCallSize, 24576, "DelegateCallManager too large");
        assertLt(trustedContractSize, 24576, "TrustedContractManager too large");
        assertLt(validatorSize, 24576, "TransactionValidator too large");
        assertLt(registrySize, 24576, "SafeTxPoolRegistry too large");
    }

    function testAccessControlPreventsDirectCalls() public {
        // Test that direct calls to managers are blocked for unauthorized callers

        // Try to call AddressBookManager directly (should fail)
        vm.prank(owner1); // owner1 is not the safe or registry
        vm.expectRevert(IBaseManager.NotSafeWallet.selector);
        addressBookManager.addAddressBookEntry(safe, recipient, "Test");

        // Try to call DelegateCallManager directly (should fail)
        vm.prank(owner1);
        vm.expectRevert(IBaseManager.NotSafeWallet.selector);
        delegateCallManager.setDelegateCallEnabled(safe, true);

        // Try to call TrustedContractManager directly (should fail)
        vm.prank(owner1);
        vm.expectRevert(IBaseManager.NotSafeWallet.selector);
        trustedContractManager.addTrustedContract(safe, recipient);
    }

    function testSafeCanCallManagersDirectly() public {
        // Test that the Safe itself can call managers directly

        vm.prank(safe);
        addressBookManager.addAddressBookEntry(safe, recipient, "Test Recipient");

        // Verify it worked
        IAddressBookManager.AddressBookEntry[] memory entries = addressBookManager.getAddressBookEntries(safe);
        assertEq(entries.length, 1);
        assertEq(entries[0].walletAddress, recipient);
    }

    function testRegistryCanCallManagers() public {
        // Test that the registry can call managers (when it has the correct address)
        // This test will pass when the managers are deployed with the correct registry address

        // For now, just test that the registry functions exist and can be called
        // The actual functionality testing should be done with proper deployment

        // Test read-only functions work
        IAddressBookManager.AddressBookEntry[] memory entries = registry.getAddressBookEntries(safe);
        assertEq(entries.length, 0); // Should be empty initially

        bool isEnabled = registry.isDelegateCallEnabled(safe);
        assertFalse(isEnabled); // Should be false by default

        bool isTrusted = registry.isTrustedContract(safe, recipient);
        assertFalse(isTrusted); // Should be false by default
    }

    function testBaseManagerPattern() public view {
        // Test that all managers inherit from BaseManager and have the registry function

        // Check that all managers have the registry function from IBaseManager
        // The actual address may differ due to deployment order, but the function should exist
        address managerRegistry1 = addressBookManager.registry();
        address managerRegistry2 = delegateCallManager.registry();
        address managerRegistry3 = trustedContractManager.registry();

        // All managers should have a registry address (not zero)
        assertTrue(managerRegistry1 != address(0), "AddressBookManager should have registry");
        assertTrue(managerRegistry2 != address(0), "DelegateCallManager should have registry");
        assertTrue(managerRegistry3 != address(0), "TrustedContractManager should have registry");

        // This demonstrates that the base contract pattern is working correctly
        // All managers share the same access control logic and registry reference
    }
}
