// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {SafeTxPool} from "../src/SafeTxPool.sol";

contract SafeTxPoolAddressBookTest is Test {
    event AddressBookEntryAdded(address indexed safe, address indexed walletAddress, string name);
    event AddressBookEntryRemoved(address indexed safe, address indexed walletAddress);

    SafeTxPool public pool;
    address public safe;
    address public walletAddress1;
    address public walletAddress2;
    address public walletAddress3;

    function setUp() public {
        // Deploy SafeTxPool
        pool = new SafeTxPool();

        // Setup test addresses
        safe = address(0x1234);
        walletAddress1 = address(0x5678);
        walletAddress2 = address(0xABCD);
        walletAddress3 = address(0xEF01);
    }

    function testAddAddressBookEntry() public {
        // Test adding a new entry
        vm.expectEmit(true, true, true, true);
        emit AddressBookEntryAdded(safe, walletAddress1, "Alice");
        pool.addAddressBookEntry(safe, walletAddress1, "Alice", "Team member");

        // Get all entries and verify
        SafeTxPool.AddressBookEntry[] memory entries = pool.getAddressBookEntries(safe);
        assertEq(entries.length, 1);
        assertEq(entries[0].name, "Alice");
        assertEq(entries[0].walletAddress, walletAddress1);
        assertEq(entries[0].description, "Team member");
    }

    function testUpdateExistingAddressBookEntry() public {
        // Add initial entry
        pool.addAddressBookEntry(safe, walletAddress1, "Alice", "Team member");

        // Update the entry
        vm.expectEmit(true, true, true, true);
        emit AddressBookEntryAdded(safe, walletAddress1, "Alice Updated");
        pool.addAddressBookEntry(safe, walletAddress1, "Alice Updated", "Lead developer");

        // Get all entries and verify update
        SafeTxPool.AddressBookEntry[] memory entries = pool.getAddressBookEntries(safe);
        assertEq(entries.length, 1);
        assertEq(entries[0].name, "Alice Updated");
        assertEq(entries[0].walletAddress, walletAddress1);
        assertEq(entries[0].description, "Lead developer");
    }

    function testAddMultipleAddressBookEntries() public {
        // Add multiple entries
        pool.addAddressBookEntry(safe, walletAddress1, "Alice", "Team member");
        pool.addAddressBookEntry(safe, walletAddress2, "Bob", "Developer");
        pool.addAddressBookEntry(safe, walletAddress3, "Carol", "Designer");

        // Get all entries and verify
        SafeTxPool.AddressBookEntry[] memory entries = pool.getAddressBookEntries(safe);
        assertEq(entries.length, 3);

        // Verify each entry - note that order may vary based on implementation
        bool foundAlice = false;
        bool foundBob = false;
        bool foundCarol = false;

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].walletAddress == walletAddress1) {
                assertEq(entries[i].name, "Alice");
                assertEq(entries[i].description, "Team member");
                foundAlice = true;
            } else if (entries[i].walletAddress == walletAddress2) {
                assertEq(entries[i].name, "Bob");
                assertEq(entries[i].description, "Developer");
                foundBob = true;
            } else if (entries[i].walletAddress == walletAddress3) {
                assertEq(entries[i].name, "Carol");
                assertEq(entries[i].description, "Designer");
                foundCarol = true;
            }
        }

        assertTrue(foundAlice);
        assertTrue(foundBob);
        assertTrue(foundCarol);
    }

    function testRemoveAddressBookEntry() public {
        // Add entries
        pool.addAddressBookEntry(safe, walletAddress1, "Alice", "Team member");
        pool.addAddressBookEntry(safe, walletAddress2, "Bob", "Developer");

        // Remove one entry
        vm.expectEmit(true, true, true, true);
        emit AddressBookEntryRemoved(safe, walletAddress1);
        pool.removeAddressBookEntry(safe, walletAddress1);

        // Get entries and verify
        SafeTxPool.AddressBookEntry[] memory entries = pool.getAddressBookEntries(safe);
        assertEq(entries.length, 1);
        assertEq(entries[0].name, "Bob");
        assertEq(entries[0].walletAddress, walletAddress2);
        assertEq(entries[0].description, "Developer");
    }

    function testRemoveLastAddressBookEntry() public {
        // Add an entry
        pool.addAddressBookEntry(safe, walletAddress1, "Alice", "Team member");

        // Remove the entry
        pool.removeAddressBookEntry(safe, walletAddress1);

        // Get entries and verify it's empty
        SafeTxPool.AddressBookEntry[] memory entries = pool.getAddressBookEntries(safe);
        assertEq(entries.length, 0);
    }

    function testGetAddressBookEntriesForEmptySafe() public view {
        // Get entries for a Safe with no entries
        SafeTxPool.AddressBookEntry[] memory entries = pool.getAddressBookEntries(safe);
        assertEq(entries.length, 0);
    }

    function testMultipleSafesWithAddressBooks() public {
        // Create another Safe
        address safe2 = address(0x9876);

        // Add entries to first Safe
        pool.addAddressBookEntry(safe, walletAddress1, "Alice", "Team member");
        pool.addAddressBookEntry(safe, walletAddress2, "Bob", "Developer");

        // Add entries to second Safe
        pool.addAddressBookEntry(safe2, walletAddress1, "Alice at Safe2", "Contributor");
        pool.addAddressBookEntry(safe2, walletAddress3, "Carol at Safe2", "Advisor");

        // Get entries for first Safe and verify
        SafeTxPool.AddressBookEntry[] memory entries1 = pool.getAddressBookEntries(safe);
        assertEq(entries1.length, 2);

        // Get entries for second Safe and verify
        SafeTxPool.AddressBookEntry[] memory entries2 = pool.getAddressBookEntries(safe2);
        assertEq(entries2.length, 2);

        // Verify first Safe's entries
        bool foundAlice = false;
        bool foundBob = false;

        for (uint256 i = 0; i < entries1.length; i++) {
            if (entries1[i].walletAddress == walletAddress1) {
                assertEq(entries1[i].name, "Alice");
                assertEq(entries1[i].description, "Team member");
                foundAlice = true;
            } else if (entries1[i].walletAddress == walletAddress2) {
                assertEq(entries1[i].name, "Bob");
                assertEq(entries1[i].description, "Developer");
                foundBob = true;
            }
        }

        assertTrue(foundAlice);
        assertTrue(foundBob);

        // Verify second Safe's entries
        bool foundAliceAtSafe2 = false;
        bool foundCarolAtSafe2 = false;

        for (uint256 i = 0; i < entries2.length; i++) {
            if (entries2[i].walletAddress == walletAddress1) {
                assertEq(entries2[i].name, "Alice at Safe2");
                assertEq(entries2[i].description, "Contributor");
                foundAliceAtSafe2 = true;
            } else if (entries2[i].walletAddress == walletAddress3) {
                assertEq(entries2[i].name, "Carol at Safe2");
                assertEq(entries2[i].description, "Advisor");
                foundCarolAtSafe2 = true;
            }
        }

        assertTrue(foundAliceAtSafe2);
        assertTrue(foundCarolAtSafe2);
    }

    function test_RevertWhen_AddingInvalidAddress() public {
        // Try to add entry with zero address
        vm.expectRevert(SafeTxPool.InvalidAddress.selector);
        pool.addAddressBookEntry(safe, address(0), "Invalid", "This should fail");
    }

    function test_RevertWhen_RemovingNonExistentEntry() public {
        // Try to remove non-existent entry
        vm.expectRevert(SafeTxPool.AddressNotFound.selector);
        pool.removeAddressBookEntry(safe, walletAddress1);
    }
}
