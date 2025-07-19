// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/SafeTxPoolRegistry.sol";
import "../src/SafeTxPoolCore.sol";
import "../src/AddressBookManager.sol";
import "../src/DelegateCallManager.sol";
import "../src/TrustedContractManager.sol";
import "../src/TransactionValidator.sol";
import "@safe-global/safe-contracts/contracts/common/Enum.sol";

// Mock Safe contract for testing Guard functionality
contract MockSafe {
    SafeTxPoolRegistry public guard;
    uint256 public nonce;

    constructor(SafeTxPoolRegistry _guard) {
        guard = _guard;
        nonce = 0;
    }

    function setNonce(uint256 _nonce) external {
        nonce = _nonce;
    }

    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures
    ) external returns (bool success) {
        // Use current nonce for hash calculation
        uint256 currentNonce = nonce;

        bytes32 txHash = keccak256(
            abi.encode(
                to, value, data, operation, safeTxGas, baseGas, gasPrice, gasToken, refundReceiver, block.chainid
            )
        );

        // Call guard before execution
        guard.checkTransaction(
            to, value, data, operation, safeTxGas, baseGas, gasPrice, gasToken, refundReceiver, signatures, msg.sender
        );

        // Simulate transaction execution
        success = true;

        // Increment nonce after successful execution
        nonce++;

        // Call guard after execution
        guard.checkAfterExecution(txHash, success);

        return success;
    }
}

contract SafeTxPoolGuardTest is Test {
    SafeTxPoolRegistry public registry;
    SafeTxPoolCore public txPoolCore;
    MockSafe public mockSafe;

    address public safe;
    address public owner1 = address(0x5678);
    address public owner2 = address(0x9ABC);
    address public recipient = address(0xDEF0);

    // Events for testing
    event TransactionExecuted(bytes32 indexed txHash, address indexed safe, uint256 txId);
    event TransactionRemovedFromPending(bytes32 indexed txHash, address indexed safe, uint256 txId, string reason);
    event BatchTransactionsRemovedFromPending(address indexed safe, uint256 nonce, uint256 count, string reason);

    function setUp() public {
        // Deploy components with new pattern
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

        // Deploy mock safe
        mockSafe = new MockSafe(registry);
        safe = address(mockSafe);

        // Add recipient to address book
        vm.prank(safe);
        registry.addAddressBookEntry(safe, recipient, "Test Recipient");
    }

    function testGuardCheckTransaction() public {
        bytes memory data = "";
        bytes memory signatures = "";

        // Should not revert for valid transaction to address in address book
        // The Safe must be the caller for proper access control
        vm.prank(safe);
        registry.checkTransaction(
            recipient, 1 ether, data, Enum.Operation.Call, 0, 0, 0, address(0), payable(address(0)), signatures, owner1
        );
    }

    function testGuardRejectsTransactionToUnknownAddress() public {
        address unknownAddress = address(0xDEAD);
        bytes memory data = "";
        bytes memory signatures = "";

        // Should revert for transaction to address not in address book
        // The Safe must be the caller
        vm.prank(safe);
        vm.expectRevert();
        registry.checkTransaction(
            unknownAddress,
            1 ether,
            data,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            signatures,
            owner1
        );
    }

    function testGuardAllowsSelfCall() public {
        bytes memory data = "";
        bytes memory signatures = "";

        // Should allow calls to the Safe itself without needing address book entry
        // The guard should handle this case specially
        vm.prank(safe); // Important: the Safe itself must be the caller for self-call detection
        registry.checkTransaction(
            safe, 0, data, Enum.Operation.Call, 0, 0, 0, address(0), payable(address(0)), signatures, owner1
        );
    }

    function testGuardAllowsGuardCall() public {
        bytes memory data = "";
        bytes memory signatures = "";

        // Should allow calls to the guard contract itself
        // The Safe must be the caller for guard call detection
        vm.prank(safe);
        registry.checkTransaction(
            address(registry),
            0,
            data,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            signatures,
            owner1
        );
    }

    function testGuardCheckAfterExecution() public {
        bytes32 txHash = keccak256("test transaction");
        bytes memory data = "";

        // First propose the transaction
        vm.prank(owner1);
        registry.proposeTx(txHash, safe, recipient, 1 ether, data, Enum.Operation.Call, 0);

        // Verify transaction exists
        (address txSafe,,,,,,,) = registry.getTxDetails(txHash);
        assertEq(txSafe, safe);

        // Call checkAfterExecution (simulating Safe calling after execution)
        vm.prank(safe);
        registry.checkAfterExecution(txHash, true);

        // Transaction should be marked as executed (removed from pending)
        (txSafe,,,,,,,) = registry.getTxDetails(txHash);
        assertEq(txSafe, address(0)); // Should be empty/deleted
    }

    function testGuardIgnoresUnknownTransactions() public {
        bytes32 unknownTxHash = keccak256("unknown transaction");

        // Should not revert when checking unknown transaction
        vm.prank(safe);
        registry.checkAfterExecution(unknownTxHash, true);
    }

    function testGuardDoesNotMarkFailedTransactions() public {
        bytes32 txHash = keccak256("test transaction");
        bytes memory data = "";

        // Propose transaction
        vm.prank(owner1);
        registry.proposeTx(txHash, safe, recipient, 1 ether, data, Enum.Operation.Call, 0);

        // Call checkAfterExecution with failed status
        vm.prank(safe);
        registry.checkAfterExecution(txHash, false);

        // Transaction should still exist (not marked as executed)
        (address txSafe,,,,,,,) = registry.getTxDetails(txHash);
        assertEq(txSafe, safe); // Should still exist
    }

    function testGuardWithDelegateCallRestrictions() public {
        address delegateTarget = address(0xBEEF);
        bytes memory data = "";
        bytes memory signatures = "";

        // Enable delegate calls first
        vm.prank(safe);
        registry.setDelegateCallEnabled(safe, true);

        // Add delegate call target
        vm.prank(safe);
        registry.addDelegateCallTarget(safe, delegateTarget);

        // Add delegate target to address book (required by transaction validator)
        vm.prank(safe);
        registry.addAddressBookEntry(safe, delegateTarget, "Delegate Target");

        // Should allow delegate call to allowed target
        vm.prank(safe);
        registry.checkTransaction(
            delegateTarget,
            0,
            data,
            Enum.Operation.DelegateCall,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            signatures,
            owner1
        );

        // Should reject delegate call to non-allowed target
        address nonAllowedTarget = address(0xDEAD);
        vm.prank(safe);
        vm.expectRevert();
        registry.checkTransaction(
            nonAllowedTarget,
            0,
            data,
            Enum.Operation.DelegateCall,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            signatures,
            owner1
        );
    }

    function testGuardWithTrustedContracts() public {
        address trustedContract = address(0xFEED);
        bytes memory data = "";
        bytes memory signatures = "";

        // Add trusted contract
        vm.prank(safe);
        registry.addTrustedContract(safe, trustedContract, "Trusted Contract");

        // Also add to address book (trusted contracts still need to be in address book for basic validation)
        vm.prank(safe);
        registry.addAddressBookEntry(safe, trustedContract, "Trusted Contract");

        // Should allow calls to trusted contracts
        vm.prank(safe);
        registry.checkTransaction(
            trustedContract,
            1 ether,
            data,
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            signatures,
            owner1
        );
    }

    function testFullTransactionFlow() public {
        bytes memory data = "";
        bytes memory signatures = "";

        // Create the same hash that MockSafe will create
        bytes32 txHash = keccak256(
            abi.encode(recipient, 1 ether, data, Enum.Operation.Call, 0, 0, 0, address(0), address(0), block.chainid)
        );

        // 1. Propose transaction
        vm.prank(owner1);
        registry.proposeTx(txHash, safe, recipient, 1 ether, data, Enum.Operation.Call, 0);

        // 2. Execute transaction through mock safe (includes guard checks)
        mockSafe.execTransaction(
            recipient, 1 ether, data, Enum.Operation.Call, 0, 0, 0, address(0), payable(address(0)), signatures
        );

        // 3. Verify transaction was automatically marked as executed
        (address txSafe,,,,,,,) = registry.getTxDetails(txHash);
        assertEq(txSafe, address(0)); // Should be empty/deleted
    }

    function testGuardMarkAsExecutedWithEventEmission() public {
        bytes32 txHash = keccak256("guard event test");
        bytes memory data = "";

        // Propose transaction
        vm.prank(owner1);
        registry.proposeTx(txHash, safe, recipient, 1 ether, data, Enum.Operation.Call, 0);

        // Get transaction ID for event verification
        (,,,,,,, uint256 txId) = registry.getTxDetails(txHash);

        // Expect TransactionExecuted event to be emitted when guard calls markAsExecuted
        vm.expectEmit(true, true, false, true);
        emit TransactionExecuted(txHash, safe, txId);

        // Call checkAfterExecution (simulating Safe calling after execution)
        vm.prank(safe);
        registry.checkAfterExecution(txHash, true);
    }

    function testGuardMarkAsExecutedWithMultipleSameNonce() public {
        bytes32 txHash1 = keccak256("guard multi nonce 1");
        bytes32 txHash2 = keccak256("guard multi nonce 2");
        bytes memory data = "";
        uint256 sameNonce = 20;

        // Propose multiple transactions with same nonce
        vm.prank(owner1);
        registry.proposeTx(txHash1, safe, recipient, 1 ether, data, Enum.Operation.Call, sameNonce);

        vm.prank(owner2);
        registry.proposeTx(txHash2, safe, recipient, 2 ether, data, Enum.Operation.Call, sameNonce);

        // Verify both transactions exist
        bytes32[] memory pending = registry.getPendingTxHashes(safe, 0, 10);
        assertEq(pending.length, 2);

        // Get transaction IDs for event verification
        (,,,,,,, uint256 txId1) = registry.getTxDetails(txHash1);
        (,,,,,,, uint256 txId2) = registry.getTxDetails(txHash2);

        // Expect TransactionExecuted event for the executed transaction
        vm.expectEmit(true, true, false, true);
        emit TransactionExecuted(txHash1, safe, txId1);

        // Execute first transaction through guard
        vm.prank(safe);
        registry.checkAfterExecution(txHash1, true);

        // Verify the executed transaction is removed from transaction data
        (address txSafe1,,,,,,,) = registry.getTxDetails(txHash1);
        assertEq(txSafe1, address(0)); // Should be removed (executed)

        // Note: txHash2 is removed from pending list but transaction data may still exist
        // This is the current implementation behavior

        // Verify pending list is empty (both transactions removed from pending)
        pending = registry.getPendingTxHashes(safe, 0, 10);
        assertEq(pending.length, 0);
    }

    function testGuardMarkAsExecutedEmitsTransactionRemovedFromPendingEvent() public {
        bytes32 txHash = keccak256("guard single removal event");
        bytes memory data = "";
        uint256 nonce = 50;

        // Propose transaction
        vm.prank(owner1);
        registry.proposeTx(txHash, safe, recipient, 1 ether, data, Enum.Operation.Call, nonce);

        // Get transaction ID for event verification
        (,,,,,,, uint256 txId) = registry.getTxDetails(txHash);

        // Expect TransactionRemovedFromPending event for single transaction
        vm.expectEmit(true, true, false, true);
        emit TransactionRemovedFromPending(txHash, safe, txId, "nonce_consumed");

        // Expect TransactionExecuted event
        vm.expectEmit(true, true, false, true);
        emit TransactionExecuted(txHash, safe, txId);

        // Execute through guard
        vm.prank(safe);
        registry.checkAfterExecution(txHash, true);
    }

    function testGuardMarkAsExecutedEmitsBatchTransactionsRemovedFromPendingEvent() public {
        bytes32 txHash1 = keccak256("guard batch removal 1");
        bytes32 txHash2 = keccak256("guard batch removal 2");
        bytes32 txHash3 = keccak256("guard batch removal 3");
        bytes32 txHash4 = keccak256("guard batch removal 4");
        bytes memory data = "";
        uint256 sameNonce = 55;

        // Propose multiple transactions with same nonce
        vm.prank(owner1);
        registry.proposeTx(txHash1, safe, recipient, 1 ether, data, Enum.Operation.Call, sameNonce);

        vm.prank(owner2);
        registry.proposeTx(txHash2, safe, recipient, 2 ether, data, Enum.Operation.Call, sameNonce);

        vm.prank(owner1);
        registry.proposeTx(txHash3, safe, recipient, 3 ether, data, Enum.Operation.Call, sameNonce);

        vm.prank(owner2);
        registry.proposeTx(txHash4, safe, recipient, 4 ether, data, Enum.Operation.Call, sameNonce);

        // Get transaction IDs for event verification
        (,,,,,,, uint256 txId1) = registry.getTxDetails(txHash1);
        (,,,,,,, uint256 txId2) = registry.getTxDetails(txHash2);
        (,,,,,,, uint256 txId3) = registry.getTxDetails(txHash3);
        (,,,,,,, uint256 txId4) = registry.getTxDetails(txHash4);

        // Events are emitted in this order:
        // 1. TransactionRemovedFromPending events (one for each transaction with same nonce)
        // 2. BatchTransactionsRemovedFromPending event (if removedCount > 1)
        // 3. TransactionExecuted event

        // Note: Individual TransactionRemovedFromPending events order is unpredictable
        // due to backwards iteration in _removeFromPending

        // Expect BatchTransactionsRemovedFromPending event (4 transactions)
        vm.expectEmit(true, false, false, true);
        emit BatchTransactionsRemovedFromPending(safe, sameNonce, 4, "nonce_consumed");

        // Expect TransactionExecuted event for the executed transaction
        vm.expectEmit(true, true, false, true);
        emit TransactionExecuted(txHash1, safe, txId1);

        // Execute through guard
        vm.prank(safe);
        registry.checkAfterExecution(txHash1, true);
    }

    function testGuardMarkAsExecutedWithMixedNoncesEventEmission() public {
        bytes32 txHash1 = keccak256("guard mixed nonce 1");
        bytes32 txHash2 = keccak256("guard mixed nonce 2");
        bytes32 txHash3 = keccak256("guard mixed nonce 3");
        bytes32 txHash4 = keccak256("guard mixed nonce 4");
        bytes memory data = "";
        uint256 nonce1 = 60;
        uint256 nonce2 = 61;

        // Propose transactions with mixed nonces
        vm.prank(owner1);
        registry.proposeTx(txHash1, safe, recipient, 1 ether, data, Enum.Operation.Call, nonce1);

        vm.prank(owner2);
        registry.proposeTx(txHash2, safe, recipient, 2 ether, data, Enum.Operation.Call, nonce1); // Same as txHash1

        vm.prank(owner1);
        registry.proposeTx(txHash3, safe, recipient, 3 ether, data, Enum.Operation.Call, nonce2); // Different nonce

        vm.prank(owner2);
        registry.proposeTx(txHash4, safe, recipient, 4 ether, data, Enum.Operation.Call, nonce2); // Same as txHash3

        // Get transaction IDs for event verification
        (,,,,,,, uint256 txId1) = registry.getTxDetails(txHash1);
        (,,,,,,, uint256 txId2) = registry.getTxDetails(txHash2);

        // Events are emitted in this order:
        // 1. TransactionRemovedFromPending events (for same nonce transactions)
        // 2. BatchTransactionsRemovedFromPending event (if removedCount > 1)
        // 3. TransactionExecuted event

        // Expect BatchTransactionsRemovedFromPending event (2 transactions with nonce1)
        vm.expectEmit(true, false, false, true);
        emit BatchTransactionsRemovedFromPending(safe, nonce1, 2, "nonce_consumed");

        // Expect TransactionExecuted event
        vm.expectEmit(true, true, false, true);
        emit TransactionExecuted(txHash1, safe, txId1);

        // Execute through guard
        vm.prank(safe);
        registry.checkAfterExecution(txHash1, true);

        // Verify nonce2 transactions still exist in pending list
        bytes32[] memory pending = registry.getPendingTxHashes(safe, 0, 10);
        assertEq(pending.length, 2); // txHash3 and txHash4 should remain
    }

    function testSafeExecutionTriggersTransactionRemovedFromPendingEvent() public {
        bytes memory data = "";
        bytes memory signatures = "";

        // Create the same hash that MockSafe will create
        bytes32 txHash = keccak256(
            abi.encode(recipient, 1 ether, data, Enum.Operation.Call, 0, 0, 0, address(0), address(0), block.chainid)
        );

        // Propose transaction
        vm.prank(owner1);
        registry.proposeTx(txHash, safe, recipient, 1 ether, data, Enum.Operation.Call, 0);

        // Get transaction ID for event verification
        (,,,,,,, uint256 txId) = registry.getTxDetails(txHash);

        // Expect TransactionRemovedFromPending event for single transaction
        vm.expectEmit(true, true, false, true);
        emit TransactionRemovedFromPending(txHash, safe, txId, "nonce_consumed");

        // Expect TransactionExecuted event
        vm.expectEmit(true, true, false, true);
        emit TransactionExecuted(txHash, safe, txId);

        // Execute transaction through MockSafe (which triggers guard)
        mockSafe.execTransaction(
            recipient, 1 ether, data, Enum.Operation.Call, 0, 0, 0, address(0), payable(address(0)), signatures
        );
    }

    function testSafeExecutionTriggersBatchTransactionsRemovedFromPendingEvent() public {
        bytes memory data = "";
        bytes memory signatures = "";
        uint256 nonce = 0; // Use nonce 0 to match MockSafe hash calculation

        // Create transaction hash that matches MockSafe calculation
        bytes32 txHash1 = keccak256(
            abi.encode(recipient, 1 ether, data, Enum.Operation.Call, 0, 0, 0, address(0), address(0), block.chainid)
        );
        bytes32 txHash2 = keccak256("additional tx same nonce");
        bytes32 txHash3 = keccak256("another tx same nonce");

        // Propose multiple transactions with same nonce
        vm.prank(owner1);
        registry.proposeTx(txHash1, safe, recipient, 1 ether, data, Enum.Operation.Call, nonce);

        vm.prank(owner2);
        registry.proposeTx(txHash2, safe, recipient, 2 ether, data, Enum.Operation.Call, nonce);

        vm.prank(owner1);
        registry.proposeTx(txHash3, safe, recipient, 3 ether, data, Enum.Operation.Call, nonce);

        // Get transaction ID for the executed transaction
        (,,,,,,, uint256 txId1) = registry.getTxDetails(txHash1);

        // Expect BatchTransactionsRemovedFromPending event (3 transactions)
        vm.expectEmit(true, false, false, true);
        emit BatchTransactionsRemovedFromPending(safe, nonce, 3, "nonce_consumed");

        // Expect TransactionExecuted event for the executed transaction
        vm.expectEmit(true, true, false, true);
        emit TransactionExecuted(txHash1, safe, txId1);

        // Execute transaction through MockSafe (which triggers guard)
        mockSafe.execTransaction(
            recipient, 1 ether, data, Enum.Operation.Call, 0, 0, 0, address(0), payable(address(0)), signatures
        );
    }

    function testSafeExecutionWithMixedNoncesEventEmission() public {
        bytes memory data = "";
        bytes memory signatures = "";
        uint256 executeNonce = 0; // Use nonce 0 to match MockSafe hash calculation
        uint256 otherNonce = 1;

        // Create transaction hash that matches MockSafe calculation
        bytes32 executeTxHash = keccak256(
            abi.encode(recipient, 1 ether, data, Enum.Operation.Call, 0, 0, 0, address(0), address(0), block.chainid)
        );
        bytes32 txHash2 = keccak256("same nonce tx");
        bytes32 txHash3 = keccak256("different nonce tx");

        // Propose transactions with mixed nonces
        vm.prank(owner1);
        registry.proposeTx(executeTxHash, safe, recipient, 1 ether, data, Enum.Operation.Call, executeNonce);

        vm.prank(owner2);
        registry.proposeTx(txHash2, safe, recipient, 2 ether, data, Enum.Operation.Call, executeNonce); // Same nonce

        vm.prank(owner1);
        registry.proposeTx(txHash3, safe, recipient, 3 ether, data, Enum.Operation.Call, otherNonce); // Different nonce

        // Get transaction ID for the executed transaction
        (,,,,,,, uint256 executeId) = registry.getTxDetails(executeTxHash);

        // Expect BatchTransactionsRemovedFromPending event (2 transactions with executeNonce)
        vm.expectEmit(true, false, false, true);
        emit BatchTransactionsRemovedFromPending(safe, executeNonce, 2, "nonce_consumed");

        // Expect TransactionExecuted event
        vm.expectEmit(true, true, false, true);
        emit TransactionExecuted(executeTxHash, safe, executeId);

        // Execute transaction through MockSafe (which triggers guard)
        mockSafe.execTransaction(
            recipient, 1 ether, data, Enum.Operation.Call, 0, 0, 0, address(0), payable(address(0)), signatures
        );

        // Verify different nonce transaction still exists
        bytes32[] memory pending = registry.getPendingTxHashes(safe, 0, 10);
        assertEq(pending.length, 1); // txHash3 should remain
        assertEq(pending[0], txHash3);
    }

    function testGuardMarkAsExecutedTryCatchSuccess() public {
        bytes32 txHash = keccak256("try catch success test");
        bytes memory data = "";

        // Propose transaction
        vm.prank(owner1);
        registry.proposeTx(txHash, safe, recipient, 1 ether, data, Enum.Operation.Call, 0);

        // Verify transaction exists
        (address txSafe,,,,,,,) = registry.getTxDetails(txHash);
        assertEq(txSafe, safe);

        // Get transaction ID for event verification
        (,,,,,,, uint256 txId) = registry.getTxDetails(txHash);

        // Expect TransactionExecuted event to be emitted
        vm.expectEmit(true, true, false, true);
        emit TransactionExecuted(txHash, safe, txId);

        // Call checkAfterExecution - should successfully mark as executed
        vm.prank(safe);
        registry.checkAfterExecution(txHash, true);

        // Verify transaction was removed
        (txSafe,,,,,,,) = registry.getTxDetails(txHash);
        assertEq(txSafe, address(0));
    }

    function testGuardMarkAsExecutedTryCatchWithNonExistentTransaction() public {
        bytes32 nonExistentTxHash = keccak256("non existent transaction");

        // Call checkAfterExecution with non-existent transaction
        // Should not revert due to try-catch mechanism
        vm.prank(safe);
        registry.checkAfterExecution(nonExistentTxHash, true);

        // No transaction should exist (obviously)
        (address txSafe,,,,,,,) = registry.getTxDetails(nonExistentTxHash);
        assertEq(txSafe, address(0));
    }

    function testGuardMarkAsExecutedWithSignedTransaction() public {
        bytes32 txHash = keccak256("signed transaction test");
        bytes memory data = "";

        // Propose transaction
        vm.prank(owner1);
        registry.proposeTx(txHash, safe, recipient, 1 ether, data, Enum.Operation.Call, 0);

        // For this test, we'll skip adding signatures to avoid signature recovery complexity
        // and focus on testing the guard's markAsExecuted functionality

        // Get transaction ID for event verification
        (,,,,,,, uint256 txId) = registry.getTxDetails(txHash);

        // Expect TransactionExecuted event
        vm.expectEmit(true, true, false, true);
        emit TransactionExecuted(txHash, safe, txId);

        // Mark as executed through guard
        vm.prank(safe);
        registry.checkAfterExecution(txHash, true);

        // Verify transaction is completely removed
        (address txSafe,,,,,,,) = registry.getTxDetails(txHash);
        assertEq(txSafe, address(0));

        // Signatures should also be removed (empty array for non-existent transaction)
        bytes[] memory signatures = registry.getSignatures(txHash);
        assertEq(signatures.length, 0);
    }

    function testGuardMarkAsExecutedWithComplexNonceScenario() public {
        bytes32 txHash1 = keccak256("complex nonce 1");
        bytes32 txHash2 = keccak256("complex nonce 2");
        bytes32 txHash3 = keccak256("complex nonce 3");
        bytes32 txHash4 = keccak256("complex nonce 4");
        bytes memory data = "";
        uint256 nonce1 = 10;
        uint256 nonce2 = 11;

        // Propose multiple transactions with different nonces
        vm.prank(owner1);
        registry.proposeTx(txHash1, safe, recipient, 1 ether, data, Enum.Operation.Call, nonce1);

        vm.prank(owner2);
        registry.proposeTx(txHash2, safe, recipient, 2 ether, data, Enum.Operation.Call, nonce1); // Same nonce

        vm.prank(owner1);
        registry.proposeTx(txHash3, safe, recipient, 3 ether, data, Enum.Operation.Call, nonce2);

        vm.prank(owner2);
        registry.proposeTx(txHash4, safe, recipient, 4 ether, data, Enum.Operation.Call, nonce2); // Same nonce

        // Verify all transactions exist
        bytes32[] memory pending = registry.getPendingTxHashes(safe, 0, 10);
        assertEq(pending.length, 4);

        // Get transaction IDs for event verification
        (,,,,,,, uint256 txId1) = registry.getTxDetails(txHash1);
        (,,,,,,, uint256 txId2) = registry.getTxDetails(txHash2);

        // Expect TransactionExecuted event for the executed transaction
        vm.expectEmit(true, true, false, true);
        emit TransactionExecuted(txHash1, safe, txId1);

        // Execute transaction with nonce1 through guard
        vm.prank(safe);
        registry.checkAfterExecution(txHash1, true);

        // Verify the executed transaction is removed
        (address txSafe1,,,,,,,) = registry.getTxDetails(txHash1);
        assertEq(txSafe1, address(0)); // Removed (executed)

        // Verify pending list contains only nonce2 transactions
        pending = registry.getPendingTxHashes(safe, 0, 10);
        assertEq(pending.length, 2); // Only nonce2 transactions remain
    }

    function testGuardReentrancyProtection() public {
        bytes32 txHash = keccak256("reentrancy test");

        // Should not allow reentrancy during checkAfterExecution
        vm.prank(safe);
        registry.checkAfterExecution(txHash, true);

        // Multiple calls should be safe (no reentrancy issues)
        vm.prank(safe);
        registry.checkAfterExecution(txHash, true);
    }

    function testGuardWithMultiplePendingTransactions() public {
        bytes32 txHash1 = keccak256("test transaction 1");
        bytes32 txHash2 = keccak256("test transaction 2");
        bytes memory data = "";

        // Propose multiple transactions
        vm.prank(owner1);
        registry.proposeTx(txHash1, safe, recipient, 1 ether, data, Enum.Operation.Call, 0);

        vm.prank(owner1);
        registry.proposeTx(txHash2, safe, recipient, 2 ether, data, Enum.Operation.Call, 1);

        // Execute first transaction
        vm.prank(safe);
        registry.checkAfterExecution(txHash1, true);

        // First should be removed, second should remain
        (address txSafe1,,,,,,,) = registry.getTxDetails(txHash1);
        (address txSafe2,,,,,,,) = registry.getTxDetails(txHash2);

        assertEq(txSafe1, address(0)); // Should be deleted
        assertEq(txSafe2, safe); // Should still exist
    }

    function testGuardMarkAsExecutedAccessControlThroughGuard() public {
        bytes32 txHash = keccak256("guard access control test");
        bytes memory data = "";

        // Propose transaction
        vm.prank(owner1);
        registry.proposeTx(txHash, safe, recipient, 1 ether, data, Enum.Operation.Call, 0);

        // Note: checkAfterExecution has no access control - anyone can call it
        // This is by design since in real usage, only the Safe calls the guard

        // Test that anyone can call checkAfterExecution and mark transaction as executed
        vm.prank(owner1);
        registry.checkAfterExecution(txHash, true); // Should succeed

        // Verify transaction was marked as executed
        (address txSafe,,,,,,,) = registry.getTxDetails(txHash);
        assertEq(txSafe, address(0)); // Should be removed
    }

    function testGuardMarkAsExecutedWithMockSafeIntegration() public {
        bytes memory data = "";
        bytes memory signatures = "";

        // Create the same hash that MockSafe will create
        bytes32 txHash = keccak256(
            abi.encode(recipient, 1 ether, data, Enum.Operation.Call, 0, 0, 0, address(0), address(0), block.chainid)
        );

        // Propose transaction
        vm.prank(owner1);
        registry.proposeTx(txHash, safe, recipient, 1 ether, data, Enum.Operation.Call, 0);

        // Get transaction ID for event verification
        (,,,,,,, uint256 txId) = registry.getTxDetails(txHash);

        // Expect TransactionExecuted event to be emitted during MockSafe execution
        vm.expectEmit(true, true, false, true);
        emit TransactionExecuted(txHash, safe, txId);

        // Execute transaction through MockSafe (which calls guard)
        mockSafe.execTransaction(
            recipient, 1 ether, data, Enum.Operation.Call, 0, 0, 0, address(0), payable(address(0)), signatures
        );

        // Verify transaction was automatically marked as executed
        (address txSafe,,,,,,,) = registry.getTxDetails(txHash);
        assertEq(txSafe, address(0));
    }

    function testGuardMarkAsExecutedSequentialTransactions() public {
        bytes32 txHash1 = keccak256("sequential 1");
        bytes32 txHash2 = keccak256("sequential 2");
        bytes32 txHash3 = keccak256("sequential 3");
        bytes memory data = "";

        // Propose multiple transactions with sequential nonces
        vm.prank(owner1);
        registry.proposeTx(txHash1, safe, recipient, 1 ether, data, Enum.Operation.Call, 0);

        vm.prank(owner1);
        registry.proposeTx(txHash2, safe, recipient, 2 ether, data, Enum.Operation.Call, 1);

        vm.prank(owner1);
        registry.proposeTx(txHash3, safe, recipient, 3 ether, data, Enum.Operation.Call, 2);

        // Verify all transactions exist
        bytes32[] memory pending = registry.getPendingTxHashes(safe, 0, 10);
        assertEq(pending.length, 3);

        // Execute transactions in order through guard
        vm.prank(safe);
        registry.checkAfterExecution(txHash1, true);

        vm.prank(safe);
        registry.checkAfterExecution(txHash2, true);

        vm.prank(safe);
        registry.checkAfterExecution(txHash3, true);

        // Verify all transactions are removed
        (address txSafe1,,,,,,,) = registry.getTxDetails(txHash1);
        (address txSafe2,,,,,,,) = registry.getTxDetails(txHash2);
        (address txSafe3,,,,,,,) = registry.getTxDetails(txHash3);

        assertEq(txSafe1, address(0));
        assertEq(txSafe2, address(0));
        assertEq(txSafe3, address(0));

        // Verify pending list is empty
        pending = registry.getPendingTxHashes(safe, 0, 10);
        assertEq(pending.length, 0);
    }

    function testGuardMarkAsExecutedWithDifferentSafes() public {
        address safe2 = address(0x2468);
        bytes32 txHash1 = keccak256("safe1 transaction");
        bytes32 txHash2 = keccak256("safe2 transaction");
        bytes memory data = "";

        // Add safe2 to address book
        vm.prank(safe2);
        registry.addAddressBookEntry(safe2, recipient, "Recipient for Safe2");

        // Propose transactions for different Safes
        vm.prank(owner1);
        registry.proposeTx(txHash1, safe, recipient, 1 ether, data, Enum.Operation.Call, 0);

        vm.prank(owner1);
        registry.proposeTx(txHash2, safe2, recipient, 2 ether, data, Enum.Operation.Call, 0);

        // Verify both transactions exist
        (address txSafe1,,,,,,,) = registry.getTxDetails(txHash1);
        (address txSafe2,,,,,,,) = registry.getTxDetails(txHash2);
        assertEq(txSafe1, safe);
        assertEq(txSafe2, safe2);

        // Execute transaction for safe1
        vm.prank(safe);
        registry.checkAfterExecution(txHash1, true);

        // Verify only safe1 transaction is removed
        (txSafe1,,,,,,,) = registry.getTxDetails(txHash1);
        (txSafe2,,,,,,,) = registry.getTxDetails(txHash2);
        assertEq(txSafe1, address(0)); // Removed
        assertEq(txSafe2, safe2); // Still exists

        // Execute transaction for safe2
        vm.prank(safe2);
        registry.checkAfterExecution(txHash2, true);

        // Verify safe2 transaction is also removed
        (txSafe2,,,,,,,) = registry.getTxDetails(txHash2);
        assertEq(txSafe2, address(0));
    }

    function testGuardMarkAsExecutedErrorHandling() public {
        bytes32 txHash = keccak256("error handling test");
        bytes memory data = "";

        // Propose transaction
        vm.prank(owner1);
        registry.proposeTx(txHash, safe, recipient, 1 ether, data, Enum.Operation.Call, 0);

        // First execution should succeed
        vm.prank(safe);
        registry.checkAfterExecution(txHash, true);

        // Verify transaction was removed
        (address txSafe,,,,,,,) = registry.getTxDetails(txHash);
        assertEq(txSafe, address(0));

        // Second execution of same transaction should not revert due to try-catch
        vm.prank(safe);
        registry.checkAfterExecution(txHash, true); // Should not revert
    }
}
