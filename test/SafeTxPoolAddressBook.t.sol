// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/SafeTxPoolRegistry.sol";
import "../src/SafeTxPoolCore.sol";
import "../src/AddressBookManager.sol";
import "../src/DelegateCallManager.sol";
import "../src/TrustedContractManager.sol";
import "../src/TransactionValidator.sol";
import "../src/interfaces/IAddressBookManager.sol";

contract SafeTxPoolAddressBookTest is Test {
    SafeTxPoolRegistry public registry;
    AddressBookManager public addressBookManager;

    address public safe = address(0x1234);
    address public recipient1 = address(0x5678);
    address public recipient2 = address(0x9ABC);
    address public recipient3 = address(0xDEF0);

    function setUp() public {
        // Deploy components
        SafeTxPoolRegistry tempRegistry = new SafeTxPoolRegistry(
            address(0), address(0), address(0), address(0), address(0)
        );
        address registryAddress = address(tempRegistry);

        SafeTxPoolCore txPoolCore = new SafeTxPoolCore();
        addressBookManager = new AddressBookManager(registryAddress);
        DelegateCallManager delegateCallManager = new DelegateCallManager(registryAddress);
        TrustedContractManager trustedContractManager = new TrustedContractManager(registryAddress);
        
        TransactionValidator transactionValidator = new TransactionValidator(
            address(addressBookManager),
            address(trustedContractManager)
        );
        
        registry = new SafeTxPoolRegistry(
            address(txPoolCore),
            address(addressBookManager),
            address(delegateCallManager),
            address(trustedContractManager),
            address(transactionValidator)
        );
    }

    function testAddAddressBookEntry() public {
        vm.prank(safe);
        registry.addAddressBookEntry(safe, recipient1, "Alice");
        
        IAddressBookManager.AddressBookEntry[] memory entries = registry.getAddressBookEntries(safe);
        assertEq(entries.length, 1);
        assertEq(entries[0].walletAddress, recipient1);
        assertEq(entries[0].name, "Alice");
    }

    function testAddMultipleAddressBookEntries() public {
        vm.prank(safe);
        registry.addAddressBookEntry(safe, recipient1, "Alice");
        
        vm.prank(safe);
        registry.addAddressBookEntry(safe, recipient2, "Bob");
        
        vm.prank(safe);
        registry.addAddressBookEntry(safe, recipient3, "Charlie");
        
        IAddressBookManager.AddressBookEntry[] memory entries = registry.getAddressBookEntries(safe);
        assertEq(entries.length, 3);
        
        // Check all entries
        assertEq(entries[0].walletAddress, recipient1);
        assertEq(entries[0].name, "Alice");
        assertEq(entries[1].walletAddress, recipient2);
        assertEq(entries[1].name, "Bob");
        assertEq(entries[2].walletAddress, recipient3);
        assertEq(entries[2].name, "Charlie");
    }

    function testUpdateExistingAddressBookEntry() public {
        // Add entry
        vm.prank(safe);
        registry.addAddressBookEntry(safe, recipient1, "Alice");
        
        // Update same address with new name
        vm.prank(safe);
        registry.addAddressBookEntry(safe, recipient1, "Alice Updated");
        
        IAddressBookManager.AddressBookEntry[] memory entries = registry.getAddressBookEntries(safe);
        assertEq(entries.length, 1); // Should still be 1 entry
        assertEq(entries[0].walletAddress, recipient1);
        assertEq(entries[0].name, "Alice Updated");
    }

    function testRemoveAddressBookEntry() public {
        // Add multiple entries
        vm.prank(safe);
        registry.addAddressBookEntry(safe, recipient1, "Alice");
        
        vm.prank(safe);
        registry.addAddressBookEntry(safe, recipient2, "Bob");
        
        // Remove one entry
        vm.prank(safe);
        registry.removeAddressBookEntry(safe, recipient1);
        
        IAddressBookManager.AddressBookEntry[] memory entries = registry.getAddressBookEntries(safe);
        assertEq(entries.length, 1);
        assertEq(entries[0].walletAddress, recipient2);
        assertEq(entries[0].name, "Bob");
    }

    function testRemoveNonExistentEntry() public {
        vm.prank(safe);
        vm.expectRevert(IAddressBookManager.AddressNotFound.selector);
        registry.removeAddressBookEntry(safe, recipient1);
    }

    function testHasAddressBookEntry() public {
        // Initially should not have entry
        bool hasEntry = addressBookManager.hasAddressBookEntry(safe, recipient1);
        assertFalse(hasEntry);
        
        // Add entry
        vm.prank(safe);
        registry.addAddressBookEntry(safe, recipient1, "Alice");
        
        // Should now have entry
        hasEntry = addressBookManager.hasAddressBookEntry(safe, recipient1);
        assertTrue(hasEntry);
        
        // Remove entry
        vm.prank(safe);
        registry.removeAddressBookEntry(safe, recipient1);
        
        // Should no longer have entry
        hasEntry = addressBookManager.hasAddressBookEntry(safe, recipient1);
        assertFalse(hasEntry);
    }

    function testFindAddressBookEntry() public {
        // Add multiple entries
        vm.prank(safe);
        registry.addAddressBookEntry(safe, recipient1, "Alice");
        
        vm.prank(safe);
        registry.addAddressBookEntry(safe, recipient2, "Bob");
        
        // Find entries
        int256 index1 = addressBookManager.findAddressBookEntry(safe, recipient1);
        int256 index2 = addressBookManager.findAddressBookEntry(safe, recipient2);
        int256 indexNotFound = addressBookManager.findAddressBookEntry(safe, recipient3);
        
        assertEq(index1, 0);
        assertEq(index2, 1);
        assertEq(indexNotFound, -1);
    }

    function testOnlySafeCanModifyAddressBook() public {
        address unauthorized = address(0x9999);
        
        // Try to add entry as unauthorized user
        vm.prank(unauthorized);
        vm.expectRevert();
        registry.addAddressBookEntry(safe, recipient1, "Alice");
        
        // Add entry as safe
        vm.prank(safe);
        registry.addAddressBookEntry(safe, recipient1, "Alice");
        
        // Try to remove entry as unauthorized user
        vm.prank(unauthorized);
        vm.expectRevert();
        registry.removeAddressBookEntry(safe, recipient1);
    }

    function testInvalidAddressRejected() public {
        vm.prank(safe);
        vm.expectRevert();
        registry.addAddressBookEntry(safe, address(0), "Invalid");
    }

    function testAddressBookIsolatedBetweenSafes() public {
        address safe2 = address(0x2468);
        
        // Add entry to safe1
        vm.prank(safe);
        registry.addAddressBookEntry(safe, recipient1, "Alice");
        
        // Add entry to safe2
        vm.prank(safe2);
        registry.addAddressBookEntry(safe2, recipient2, "Bob");
        
        // Check safe1 only has its entry
        IAddressBookManager.AddressBookEntry[] memory entries1 = registry.getAddressBookEntries(safe);
        assertEq(entries1.length, 1);
        assertEq(entries1[0].walletAddress, recipient1);
        
        // Check safe2 only has its entry
        IAddressBookManager.AddressBookEntry[] memory entries2 = registry.getAddressBookEntries(safe2);
        assertEq(entries2.length, 1);
        assertEq(entries2[0].walletAddress, recipient2);
    }

    function testEmptyAddressBookReturnsEmptyArray() public {
        IAddressBookManager.AddressBookEntry[] memory entries = registry.getAddressBookEntries(safe);
        assertEq(entries.length, 0);
    }

    function testAddressBookEntryEvents() public {
        // Test add event
        vm.expectEmit(true, true, false, true);
        emit IAddressBookManager.AddressBookEntryAdded(safe, recipient1, "Alice");
        
        vm.prank(safe);
        registry.addAddressBookEntry(safe, recipient1, "Alice");
        
        // Test remove event
        vm.expectEmit(true, true, false, false);
        emit IAddressBookManager.AddressBookEntryRemoved(safe, recipient1);
        
        vm.prank(safe);
        registry.removeAddressBookEntry(safe, recipient1);
    }

    function testLargeAddressBook() public {
        // Test with many entries to ensure gas efficiency
        uint256 numEntries = 50;
        
        for (uint256 i = 0; i < numEntries; i++) {
            address addr = address(uint160(0x1000 + i));
            bytes32 name = bytes32(abi.encodePacked("User", i));
            
            vm.prank(safe);
            registry.addAddressBookEntry(safe, addr, name);
        }
        
        IAddressBookManager.AddressBookEntry[] memory entries = registry.getAddressBookEntries(safe);
        assertEq(entries.length, numEntries);
        
        // Verify first and last entries
        assertEq(entries[0].walletAddress, address(0x1000));
        assertEq(entries[numEntries - 1].walletAddress, address(uint160(0x1000 + numEntries - 1)));
    }
}
