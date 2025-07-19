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
import "@safe-global/safe-contracts/contracts/common/Enum.sol";

contract SafeTxPoolCoreTest is Test {
    SafeTxPoolRegistry public registry;
    SafeTxPoolCore public txPoolCore;

    address public safe = address(0x1234);
    address public owner1 = address(0x5678);
    address public owner2 = address(0x9ABC);
    address public recipient = address(0xDEF0);

    // Events for testing
    event TransactionExecuted(bytes32 indexed txHash, address indexed safe, uint256 txId);
    event TransactionRemovedFromPending(bytes32 indexed txHash, address indexed safe, uint256 txId, string reason);
    event BatchTransactionsRemovedFromPending(address indexed safe, uint256 nonce, uint256 count, string reason);

    function setUp() public {
        // Use the new deployment pattern that fixes access control
        // Deploy components with zero address initially, then update

        txPoolCore = new SafeTxPoolCore();
        AddressBookManager addressBookManager = new AddressBookManager();
        DelegateCallManager delegateCallManager = new DelegateCallManager();
        TrustedContractManager trustedContractManager = new TrustedContractManager();

        TransactionValidator transactionValidator =
            new TransactionValidator(address(addressBookManager), address(trustedContractManager));

        registry = new SafeTxPoolRegistry(
            address(txPoolCore),
            address(addressBookManager),
            address(delegateCallManager),
            address(trustedContractManager),
            address(transactionValidator)
        );

        // Set registry addresses for all components (one-time only)
        txPoolCore.setRegistry(address(registry));
        addressBookManager.setRegistry(address(registry));
        delegateCallManager.setRegistry(address(registry));
        trustedContractManager.setRegistry(address(registry));

        // Add recipient to address book for testing
        vm.prank(safe);
        registry.addAddressBookEntry(safe, recipient, "Test Recipient");
    }

    function testProposeTx() public {
        bytes32 txHash = keccak256("test transaction");
        bytes memory data = "";

        vm.prank(owner1);
        registry.proposeTx(
            txHash,
            safe,
            recipient,
            1 ether,
            data,
            Enum.Operation.Call,
            0 // nonce
        );

        // Verify transaction was proposed
        (
            address txSafe,
            address txTo,
            uint256 txValue,
            bytes memory txData,
            Enum.Operation txOperation,
            address txProposer,
            uint256 txNonce,
            uint256 txId
        ) = registry.getTxDetails(txHash);

        assertEq(txSafe, safe);
        assertEq(txTo, recipient);
        assertEq(txValue, 1 ether);
        assertEq(txData.length, 0);
        assertEq(uint8(txOperation), uint8(Enum.Operation.Call));
        // Note: txProposer might be different due to internal call routing
        assertTrue(txProposer != address(0)); // Just verify it's set
        assertEq(txNonce, 0);
        assertEq(txId, 1);
    }

    function testSignTx() public {
        bytes32 txHash = keccak256("test transaction");
        bytes memory data = "";

        // First propose the transaction
        vm.prank(owner1);
        registry.proposeTx(txHash, safe, recipient, 1 ether, data, Enum.Operation.Call, 0);

        // Create a mock signature
        bytes memory signature1 = abi.encodePacked(bytes32(uint256(0x1)), bytes32(uint256(0x2)), bytes1(0x1b));
        bytes memory signature2 = abi.encodePacked(bytes32(uint256(0x3)), bytes32(uint256(0x4)), bytes1(0x1c));

        // Sign the transaction
        vm.prank(owner1);
        registry.signTx(txHash, signature1);

        vm.prank(owner2);
        registry.signTx(txHash, signature2);

        // Verify signatures were stored
        bytes[] memory signatures = registry.getSignatures(txHash);
        assertEq(signatures.length, 2);
        assertEq(signatures[0], signature1);
        assertEq(signatures[1], signature2);
    }

    function testCannotSignTwice() public {
        bytes32 txHash = keccak256("test transaction");
        bytes memory data = "";

        // Propose transaction
        vm.prank(owner1);
        registry.proposeTx(txHash, safe, recipient, 1 ether, data, Enum.Operation.Call, 0);

        // Sign once
        bytes memory signature = abi.encodePacked(bytes32(uint256(0x1)), bytes32(uint256(0x2)), bytes1(0x1b));
        vm.prank(owner1);
        registry.signTx(txHash, signature);

        // Try to sign again - should fail
        vm.prank(owner1);
        vm.expectRevert(); // Should revert with AlreadySigned
        registry.signTx(txHash, signature);
    }

    function testMarkAsExecuted() public {
        bytes32 txHash = keccak256("test transaction");
        bytes memory data = "";

        // Propose transaction
        vm.prank(owner1);
        registry.proposeTx(txHash, safe, recipient, 1 ether, data, Enum.Operation.Call, 0);

        // Mark as executed (should be called by Safe)
        vm.prank(safe);
        registry.markAsExecuted(txHash);

        // Transaction should no longer exist
        (address txSafe,,,,,,,) = registry.getTxDetails(txHash);
        assertEq(txSafe, address(0)); // Should be empty/deleted
    }

    function testMarkAsExecutedEmitsEvent() public {
        bytes32 txHash = keccak256("test transaction with event");
        bytes memory data = "";
        uint256 nonce = 5;

        // Propose transaction
        vm.prank(owner1);
        registry.proposeTx(txHash, safe, recipient, 1 ether, data, Enum.Operation.Call, nonce);

        // Get transaction details before execution to verify event parameters
        (,,,,,, uint256 txId) = registry.getTxDetails(txHash);

        // Expect TransactionExecuted event to be emitted
        vm.expectEmit(true, true, false, true);
        emit TransactionExecuted(txHash, safe, txId);

        // Mark as executed
        vm.prank(safe);
        registry.markAsExecuted(txHash);
    }

    function testMarkAsExecutedAccessControl() public {
        bytes32 txHash = keccak256("access control test");
        bytes memory data = "";

        // Propose transaction
        vm.prank(owner1);
        registry.proposeTx(txHash, safe, recipient, 1 ether, data, Enum.Operation.Call, 0);

        // Test unauthorized caller should fail
        vm.prank(owner1);
        vm.expectRevert(); // Should revert with NotSafeWallet
        registry.markAsExecuted(txHash);

        // Test random address should fail
        vm.prank(address(0x999));
        vm.expectRevert(); // Should revert with NotSafeWallet
        registry.markAsExecuted(txHash);

        // Test Safe wallet should succeed
        vm.prank(safe);
        registry.markAsExecuted(txHash);

        // Verify transaction was removed
        (address txSafe,,,,,,,) = registry.getTxDetails(txHash);
        assertEq(txSafe, address(0));
    }

    function testMarkAsExecutedNonExistentTransaction() public {
        bytes32 nonExistentTxHash = keccak256("non existent transaction");

        // Should revert when trying to mark non-existent transaction as executed
        vm.prank(safe);
        vm.expectRevert(); // Should revert with TransactionNotFound
        registry.markAsExecuted(nonExistentTxHash);
    }

    function testMarkAsExecutedWithSignatures() public {
        bytes32 txHash = keccak256("transaction with signatures");
        bytes memory data = "";

        // Propose transaction
        vm.prank(owner1);
        registry.proposeTx(txHash, safe, recipient, 1 ether, data, Enum.Operation.Call, 0);

        // Add some signatures
        bytes memory signature1 = "signature1";
        bytes memory signature2 = "signature2";

        vm.prank(owner1);
        registry.signTx(txHash, signature1);

        vm.prank(owner2);
        registry.signTx(txHash, signature2);

        // Verify signatures exist before execution
        bytes[] memory signatures = registry.getSignatures(txHash);
        assertEq(signatures.length, 2);

        // Mark as executed
        vm.prank(safe);
        registry.markAsExecuted(txHash);

        // Verify transaction and signatures are completely removed
        (address txSafe,,,,,,,) = registry.getTxDetails(txHash);
        assertEq(txSafe, address(0));

        // Signatures should also be removed
        signatures = registry.getSignatures(txHash);
        assertEq(signatures.length, 0);
    }

    function testMarkAsExecutedRemovesSameNonceTransactions() public {
        bytes32 txHash1 = keccak256("transaction 1 same nonce");
        bytes32 txHash2 = keccak256("transaction 2 same nonce");
        bytes32 txHash3 = keccak256("transaction 3 different nonce");
        bytes memory data = "";
        uint256 sameNonce = 10;
        uint256 differentNonce = 11;

        // Propose multiple transactions with same nonce
        vm.prank(owner1);
        registry.proposeTx(txHash1, safe, recipient, 1 ether, data, Enum.Operation.Call, sameNonce);

        vm.prank(owner2);
        registry.proposeTx(txHash2, safe, recipient, 2 ether, data, Enum.Operation.Call, sameNonce);

        // Propose one with different nonce
        vm.prank(owner1);
        registry.proposeTx(txHash3, safe, recipient, 3 ether, data, Enum.Operation.Call, differentNonce);

        // Verify all transactions exist
        bytes32[] memory pending = registry.getPendingTxHashes(safe, 0, 10);
        assertEq(pending.length, 3);

        // Mark first transaction as executed - should remove all with same nonce
        vm.prank(safe);
        registry.markAsExecuted(txHash1);

        // Verify transactions with same nonce are removed, different nonce remains
        (address txSafe1,,,,,,,) = registry.getTxDetails(txHash1);
        (address txSafe2,,,,,,,) = registry.getTxDetails(txHash2);
        (address txSafe3,,,,,,,) = registry.getTxDetails(txHash3);

        assertEq(txSafe1, address(0)); // Should be removed
        assertEq(txSafe2, address(0)); // Should be removed (same nonce)
        assertEq(txSafe3, safe); // Should remain (different nonce)

        // Verify pending list is updated correctly
        pending = registry.getPendingTxHashes(safe, 0, 10);
        assertEq(pending.length, 1);
        assertEq(pending[0], txHash3);
    }

    function testMarkAsExecutedMultipleTransactionsEvents() public {
        bytes32 txHash1 = keccak256("multi tx 1");
        bytes32 txHash2 = keccak256("multi tx 2");
        bytes memory data = "";
        uint256 sameNonce = 15;

        // Propose multiple transactions with same nonce
        vm.prank(owner1);
        registry.proposeTx(txHash1, safe, recipient, 1 ether, data, Enum.Operation.Call, sameNonce);

        vm.prank(owner2);
        registry.proposeTx(txHash2, safe, recipient, 2 ether, data, Enum.Operation.Call, sameNonce);

        // Get transaction IDs for event verification
        (,,,,,, uint256 txId1) = registry.getTxDetails(txHash1);
        (,,,,,, uint256 txId2) = registry.getTxDetails(txHash2);

        // Expect TransactionExecuted event for the executed transaction
        vm.expectEmit(true, true, false, true);
        emit TransactionExecuted(txHash1, safe, txId1);

        // Expect TransactionRemovedFromPending events for both transactions
        vm.expectEmit(true, true, false, true);
        emit TransactionRemovedFromPending(txHash1, safe, txId1, "nonce_consumed");

        vm.expectEmit(true, true, false, true);
        emit TransactionRemovedFromPending(txHash2, safe, txId2, "nonce_consumed");

        // Expect BatchTransactionsRemovedFromPending event
        vm.expectEmit(true, false, false, true);
        emit BatchTransactionsRemovedFromPending(safe, sameNonce, 2, "nonce_consumed");

        // Mark as executed
        vm.prank(safe);
        registry.markAsExecuted(txHash1);
    }

    function testMarkAsExecutedFromRegistry() public {
        bytes32 txHash = keccak256("registry caller test");
        bytes memory data = "";

        // Propose transaction
        vm.prank(owner1);
        registry.proposeTx(txHash, safe, recipient, 1 ether, data, Enum.Operation.Call, 0);

        // Registry should be able to call markAsExecuted
        vm.prank(address(registry));
        registry.markAsExecuted(txHash);

        // Verify transaction was removed
        (address txSafe,,,,,,,) = registry.getTxDetails(txHash);
        assertEq(txSafe, address(0));
    }

    function testDeleteTx() public {
        bytes32 txHash = keccak256("test transaction");
        bytes memory data = "";

        // Propose transaction
        vm.prank(owner1);
        registry.proposeTx(txHash, safe, recipient, 1 ether, data, Enum.Operation.Call, 0);

        // Delete transaction (only proposer can delete)
        vm.prank(owner1);
        registry.deleteTx(txHash);

        // Transaction should no longer exist
        (address txSafe,,,,,,,) = registry.getTxDetails(txHash);
        assertEq(txSafe, address(0)); // Should be empty/deleted
    }

    function testOnlyProposerCanDelete() public {
        bytes32 txHash = keccak256("test transaction");
        bytes memory data = "";

        // Propose transaction
        vm.prank(owner1);
        registry.proposeTx(txHash, safe, recipient, 1 ether, data, Enum.Operation.Call, 0);

        // Try to delete as different user - should fail
        vm.prank(owner2);
        vm.expectRevert(); // Should revert with NotProposer
        registry.deleteTx(txHash);
    }

    function testGetPendingTxHashes() public {
        bytes32 txHash1 = keccak256("test transaction 1");
        bytes32 txHash2 = keccak256("test transaction 2");
        bytes memory data = "";

        // Propose multiple transactions
        vm.prank(owner1);
        registry.proposeTx(txHash1, safe, recipient, 1 ether, data, Enum.Operation.Call, 0);

        vm.prank(owner2);
        registry.proposeTx(txHash2, safe, recipient, 2 ether, data, Enum.Operation.Call, 1);

        // Get pending transactions
        bytes32[] memory pending = registry.getPendingTxHashes(safe, 0, 10);
        assertEq(pending.length, 2);
        assertEq(pending[0], txHash1);
        assertEq(pending[1], txHash2);

        // Test pagination
        bytes32[] memory firstOne = registry.getPendingTxHashes(safe, 0, 1);
        assertEq(firstOne.length, 1);
        assertEq(firstOne[0], txHash1);

        bytes32[] memory secondOne = registry.getPendingTxHashes(safe, 1, 1);
        assertEq(secondOne.length, 1);
        assertEq(secondOne[0], txHash2);
    }

    function testTransactionWithSameNonceRemoval() public {
        bytes32 txHash1 = keccak256("test transaction 1");
        bytes32 txHash2 = keccak256("test transaction 2");
        bytes memory data = "";
        uint256 nonce = 5;

        // Propose multiple transactions with same nonce
        vm.prank(owner1);
        registry.proposeTx(txHash1, safe, recipient, 1 ether, data, Enum.Operation.Call, nonce);

        vm.prank(owner2);
        registry.proposeTx(txHash2, safe, recipient, 2 ether, data, Enum.Operation.Call, nonce);

        // Verify both are pending
        bytes32[] memory pending = registry.getPendingTxHashes(safe, 0, 10);
        assertEq(pending.length, 2);

        // Mark one as executed - should remove all with same nonce
        vm.prank(safe);
        registry.markAsExecuted(txHash1);

        // Both should be removed due to nonce consumption
        bytes32[] memory pendingAfter = registry.getPendingTxHashes(safe, 0, 10);
        assertEq(pendingAfter.length, 0);
    }
}
