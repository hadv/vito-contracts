// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/SafeTxPool.sol";
import "@safe-global/safe-contracts/contracts/common/Enum.sol";

contract MockSafeWithGuard {
    SafeTxPool public guard;

    constructor(SafeTxPool _guard) {
        guard = _guard;
    }

    function executeTransaction(address to, uint256 value, bytes calldata data, Enum.Operation operation) external {
        // Call checkTransaction on the guard
        guard.checkTransaction(
            to,
            value,
            data,
            operation,
            0, // safeTxGas
            0, // baseGas
            0, // gasPrice
            address(0), // gasToken
            payable(address(0)), // refundReceiver
            bytes(""), // signatures
            msg.sender // msgSender
        );

        // If the guard doesn't revert, the transaction would execute
    }
}

contract SafeTxPoolGuardAddressCheckTest is Test {
    SafeTxPool public pool;
    MockSafeWithGuard public mockSafe;
    address public owner;
    address public addressInBook;
    address public addressNotInBook;
    bytes32 public nameInBook;

    function setUp() public {
        // Setup test accounts
        owner = address(0x1234);
        addressInBook = address(0xABCD);
        addressNotInBook = address(0x5678);
        nameInBook = bytes32("AllowedAddress");

        // Deploy SafeTxPool
        pool = new SafeTxPool();

        // Deploy mock Safe with the guard
        mockSafe = new MockSafeWithGuard(pool);

        // Add an address to the address book (prank as the mock Safe since only Safe can manage its address book)
        vm.prank(address(mockSafe));
        pool.addAddressBookEntry(address(mockSafe), addressInBook, nameInBook);
    }

    function testAllowTransactionToAddressInAddressBook() public {
        // This should succeed since addressInBook is in the address book
        mockSafe.executeTransaction(addressInBook, 1 ether, hex"", Enum.Operation.Call);

        // If we got here without reverting, the test passes
        assertTrue(true);
    }

    function testRevertTransactionToAddressNotInAddressBook() public {
        // This should revert since addressNotInBook is not in the address book
        vm.expectRevert(SafeTxPool.AddressNotInAddressBook.selector);
        mockSafe.executeTransaction(addressNotInBook, 1 ether, hex"", Enum.Operation.Call);
    }

    function testAddAddressAndThenAllowTransaction() public {
        // First attempt should revert
        vm.expectRevert(SafeTxPool.AddressNotInAddressBook.selector);
        mockSafe.executeTransaction(addressNotInBook, 1 ether, hex"", Enum.Operation.Call);

        // Add the address to the address book - prank as the mockSafe
        vm.prank(address(mockSafe));
        pool.addAddressBookEntry(address(mockSafe), addressNotInBook, bytes32("NewlyAddedAddress"));

        // Now the transaction should succeed
        mockSafe.executeTransaction(addressNotInBook, 1 ether, hex"", Enum.Operation.Call);

        // If we got here without reverting, the test passes
        assertTrue(true);
    }

    function testRemoveAddressAndThenRevertTransaction() public {
        // First transaction should succeed
        mockSafe.executeTransaction(addressInBook, 1 ether, hex"", Enum.Operation.Call);

        // Remove the address from the address book - prank as the mockSafe
        vm.prank(address(mockSafe));
        pool.removeAddressBookEntry(address(mockSafe), addressInBook);

        // Now the transaction should revert
        vm.expectRevert(SafeTxPool.AddressNotInAddressBook.selector);
        mockSafe.executeTransaction(addressInBook, 1 ether, hex"", Enum.Operation.Call);
    }

    function testRevertWhenNonSafeAddsToAddressBook() public {
        // Try to add an address to the address book as a non-Safe wallet
        vm.expectRevert(SafeTxPool.NotSafeWallet.selector);
        pool.addAddressBookEntry(address(mockSafe), addressNotInBook, bytes32("Unauthorized"));
    }

    function testRevertWhenNonSafeRemovesFromAddressBook() public {
        // Try to remove an address from the address book as a non-Safe wallet
        vm.expectRevert(SafeTxPool.NotSafeWallet.selector);
        pool.removeAddressBookEntry(address(mockSafe), addressInBook);
    }
}
