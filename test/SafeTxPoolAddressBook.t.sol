// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {SafeTxPool} from "../src/SafeTxPool.sol";

contract SafeTxPoolAddressBookTest is Test {
    event AddressBookEntryAdded(address indexed safe, address indexed walletAddress, bytes32 name);
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
        bytes32 name = bytes32("Alice");
        vm.prank(safe);
        vm.expectEmit(true, true, true, true);
        emit AddressBookEntryAdded(safe, walletAddress1, name);
        pool.addAddressBookEntry(safe, walletAddress1, name);

        // Get all entries and verify
        SafeTxPool.AddressBookEntry[] memory entries = pool.getAddressBookEntries(safe);
        assertEq(entries.length, 1);
        assertEq(entries[0].walletAddress, walletAddress1);
        assertEq(entries[0].name, name);
    }

    function testUpdateExistingAddressBookEntry() public {
        // Add initial entry
        bytes32 name1 = bytes32("Alice");
        vm.prank(safe);
        pool.addAddressBookEntry(safe, walletAddress1, name1);

        // Update the entry
        bytes32 name2 = bytes32("Alice Updated");
        vm.prank(safe);
        vm.expectEmit(true, true, true, true);
        emit AddressBookEntryAdded(safe, walletAddress1, name2);
        pool.addAddressBookEntry(safe, walletAddress1, name2);

        // Get all entries and verify update
        SafeTxPool.AddressBookEntry[] memory entries = pool.getAddressBookEntries(safe);
        assertEq(entries.length, 1);
        assertEq(entries[0].walletAddress, walletAddress1);
        assertEq(entries[0].name, name2);
    }

    function testAddMultipleAddressBookEntries() public {
        // Add multiple entries
        bytes32 name1 = bytes32("Alice");
        bytes32 name2 = bytes32("Bob");
        bytes32 name3 = bytes32("Carol");
        vm.startPrank(safe);
        pool.addAddressBookEntry(safe, walletAddress1, name1);
        pool.addAddressBookEntry(safe, walletAddress2, name2);
        pool.addAddressBookEntry(safe, walletAddress3, name3);
        vm.stopPrank();

        // Get all entries and verify
        SafeTxPool.AddressBookEntry[] memory entries = pool.getAddressBookEntries(safe);
        assertEq(entries.length, 3);

        // Verify each entry by address - order may vary based on implementation
        bool foundWallet1 = false;
        bool foundWallet2 = false;
        bool foundWallet3 = false;

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].walletAddress == walletAddress1) {
                assertEq(entries[i].name, name1);
                foundWallet1 = true;
            } else if (entries[i].walletAddress == walletAddress2) {
                assertEq(entries[i].name, name2);
                foundWallet2 = true;
            } else if (entries[i].walletAddress == walletAddress3) {
                assertEq(entries[i].name, name3);
                foundWallet3 = true;
            }
        }

        assertTrue(foundWallet1);
        assertTrue(foundWallet2);
        assertTrue(foundWallet3);
    }

    function testRemoveAddressBookEntry() public {
        // Add entries
        vm.startPrank(safe);
        pool.addAddressBookEntry(safe, walletAddress1, bytes32("Alice"));
        pool.addAddressBookEntry(safe, walletAddress2, bytes32("Bob"));

        // Remove one entry
        vm.expectEmit(true, true, true, true);
        emit AddressBookEntryRemoved(safe, walletAddress1);
        pool.removeAddressBookEntry(safe, walletAddress1);
        vm.stopPrank();

        // Get entries and verify
        SafeTxPool.AddressBookEntry[] memory entries = pool.getAddressBookEntries(safe);
        assertEq(entries.length, 1);
        assertEq(entries[0].walletAddress, walletAddress2);
    }

    function testRemoveLastAddressBookEntry() public {
        // Add an entry
        vm.prank(safe);
        pool.addAddressBookEntry(safe, walletAddress1, bytes32("Alice"));

        // Remove the entry
        vm.prank(safe);
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
        bytes32 name1 = bytes32("Alice");
        bytes32 name2 = bytes32("Bob");
        vm.prank(safe);
        pool.addAddressBookEntry(safe, walletAddress1, name1);
        vm.prank(safe);
        pool.addAddressBookEntry(safe, walletAddress2, name2);

        // Add entries to second Safe
        bytes32 name3 = bytes32("Alice at Safe2");
        bytes32 name4 = bytes32("Carol at Safe2");
        vm.prank(safe2);
        pool.addAddressBookEntry(safe2, walletAddress1, name3);
        vm.prank(safe2);
        pool.addAddressBookEntry(safe2, walletAddress3, name4);

        // Get entries for first Safe and verify
        SafeTxPool.AddressBookEntry[] memory entries1 = pool.getAddressBookEntries(safe);
        assertEq(entries1.length, 2);

        // Get entries for second Safe and verify
        SafeTxPool.AddressBookEntry[] memory entries2 = pool.getAddressBookEntries(safe2);
        assertEq(entries2.length, 2);

        // Verify addresses in first Safe
        bool foundWallet1InSafe1 = false;
        bool foundWallet2InSafe1 = false;

        for (uint256 i = 0; i < entries1.length; i++) {
            if (entries1[i].walletAddress == walletAddress1) {
                assertEq(entries1[i].name, name1);
                foundWallet1InSafe1 = true;
            } else if (entries1[i].walletAddress == walletAddress2) {
                assertEq(entries1[i].name, name2);
                foundWallet2InSafe1 = true;
            }
        }

        assertTrue(foundWallet1InSafe1);
        assertTrue(foundWallet2InSafe1);

        // Verify addresses in second Safe
        bool foundWallet1InSafe2 = false;
        bool foundWallet3InSafe2 = false;

        for (uint256 i = 0; i < entries2.length; i++) {
            if (entries2[i].walletAddress == walletAddress1) {
                assertEq(entries2[i].name, name3);
                foundWallet1InSafe2 = true;
            } else if (entries2[i].walletAddress == walletAddress3) {
                assertEq(entries2[i].name, name4);
                foundWallet3InSafe2 = true;
            }
        }

        assertTrue(foundWallet1InSafe2);
        assertTrue(foundWallet3InSafe2);
    }

    function test_RevertWhen_AddingInvalidAddress() public {
        vm.prank(safe);
        vm.expectRevert(SafeTxPool.InvalidAddress.selector);
        pool.addAddressBookEntry(safe, address(0), bytes32("Invalid"));
    }

    function test_RevertWhen_RemovingNonExistentEntry() public {
        vm.prank(safe);
        vm.expectRevert(SafeTxPool.AddressNotFound.selector);
        pool.removeAddressBookEntry(safe, walletAddress1);
    }
}
