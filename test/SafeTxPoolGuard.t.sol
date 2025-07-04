// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/SafeTxPool.sol";
import "@safe-global/safe-contracts/contracts/common/Enum.sol";

contract MockSafe {
    bytes32 public lastTxHash;
    bool public txSuccess;
    SafeTxPool public txPool;

    constructor(SafeTxPool _txPool) {
        txPool = _txPool;
    }

    // Mock function to simulate a Safe calling checkAfterExecution
    function executeTransaction(bytes32 _txHash, bool _success) external {
        lastTxHash = _txHash;
        txSuccess = _success;

        // Call checkAfterExecution on the guard
        txPool.checkAfterExecution(_txHash, _success);
    }
}

contract SafeTxPoolGuardTest is Test {
    event TransactionExecuted(bytes32 indexed txHash, address indexed safe, uint256 txId);
    event SelfCallAllowed(address indexed safe, address indexed to);
    event GuardCallAllowed(address indexed safe, address indexed guard);

    SafeTxPool public pool;
    MockSafe public mockSafe;
    MockSafe public mockSafe2;
    address public owner;
    address public owner2;
    address public recipient;
    uint256 public ownerKey;
    uint256 public owner2Key;

    function setUp() public {
        // Setup test accounts
        ownerKey = 0xA11CE;
        owner2Key = 0xB0B;
        owner = vm.addr(ownerKey);
        owner2 = vm.addr(owner2Key);
        recipient = address(0x5678);

        // Deploy SafeTxPool
        pool = new SafeTxPool();

        // Deploy mock Safes
        mockSafe = new MockSafe(pool);
        mockSafe2 = new MockSafe(pool);

        // Fund the owners
        vm.deal(owner, 10 ether);
        vm.deal(owner2, 10 ether);
    }

    function testGuardAutoMarkExecution() public {
        // Prepare transaction data
        bytes32 txHash = keccak256("test transaction");
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 1 ether);

        // Propose transaction in the pool
        vm.prank(owner);
        pool.proposeTx(
            txHash,
            address(mockSafe),
            recipient,
            1 ether,
            data,
            Enum.Operation.Call,
            0 // nonce
        );

        // Verify transaction exists in pool
        bytes32[] memory pendingTxs = pool.getPendingTxHashes(address(mockSafe), 0, 1);
        assertEq(pendingTxs.length, 1);
        assertEq(pendingTxs[0], txHash);

        // Simulate Safe executing the transaction and calling the guard's checkAfterExecution
        mockSafe.executeTransaction(txHash, true);

        // Verify transaction was removed from pool
        pendingTxs = pool.getPendingTxHashes(address(mockSafe), 0, 1);
        assertEq(pendingTxs.length, 0);

        // Verify transaction data is deleted
        (address txSafe,,,,, address txProposer,,) = pool.getTxDetails(txHash);
        assertEq(txProposer, address(0));
        assertEq(txSafe, address(0));
    }

    function testGuardDoesNotMarkFailedTransactions() public {
        // Prepare transaction data
        bytes32 txHash = keccak256("test transaction");
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 1 ether);

        // Propose transaction in the pool
        vm.prank(owner);
        pool.proposeTx(
            txHash,
            address(mockSafe),
            recipient,
            1 ether,
            data,
            Enum.Operation.Call,
            0 // nonce
        );

        // Simulate Safe executing the transaction but fails
        mockSafe.executeTransaction(txHash, false);

        // Verify transaction still exists in pool (not marked as executed)
        bytes32[] memory pendingTxs = pool.getPendingTxHashes(address(mockSafe), 0, 1);
        assertEq(pendingTxs.length, 1);
        assertEq(pendingTxs[0], txHash);
    }

    function testGuardIgnoresUnknownTransactions() public {
        // Prepare transaction data
        bytes32 txHash = keccak256("test transaction");
        bytes32 unknownTxHash = keccak256("unknown transaction hash");
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 1 ether);

        // Propose transaction in the pool
        vm.prank(owner);
        pool.proposeTx(
            txHash,
            address(mockSafe),
            recipient,
            1 ether,
            data,
            Enum.Operation.Call,
            0 // nonce
        );

        // Simulate Safe executing a different transaction
        mockSafe.executeTransaction(unknownTxHash, true);

        // Verify transaction still exists in pool (not marked as executed)
        bytes32[] memory pendingTxs = pool.getPendingTxHashes(address(mockSafe), 0, 1);
        assertEq(pendingTxs.length, 1);
        assertEq(pendingTxs[0], txHash);
    }

    function testGuardEmitsTransactionExecutedEvent() public {
        // Prepare transaction data
        bytes32 txHash = keccak256("test transaction");
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 1 ether);

        // Propose transaction in the pool
        vm.prank(owner);
        pool.proposeTx(
            txHash,
            address(mockSafe),
            recipient,
            1 ether,
            data,
            Enum.Operation.Call,
            0 // nonce
        );

        // Get transaction ID for event verification
        (,,,,,,, uint256 txId) = pool.getTxDetails(txHash);

        // Expect TransactionExecuted event to be emitted
        vm.expectEmit(true, true, true, true);
        emit TransactionExecuted(txHash, address(mockSafe), txId);

        // Simulate Safe executing the transaction
        mockSafe.executeTransaction(txHash, true);
    }

    function testGuardWithMultiplePendingTransactions() public {
        // Prepare multiple transaction data
        bytes32[] memory txHashes = new bytes32[](3);
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 1 ether);

        // Propose multiple transactions
        for (uint256 i = 0; i < 3; i++) {
            txHashes[i] = keccak256(abi.encodePacked("test transaction", i));
            vm.prank(owner);
            pool.proposeTx(
                txHashes[i],
                address(mockSafe),
                recipient,
                1 ether,
                data,
                Enum.Operation.Call,
                i // nonce
            );
        }

        // Verify all transactions are pending
        bytes32[] memory pendingTxs = pool.getPendingTxHashes(address(mockSafe), 0, 3);
        assertEq(pendingTxs.length, 3);

        // Execute middle transaction via guard
        mockSafe.executeTransaction(txHashes[1], true);

        // Verify only middle transaction was removed
        pendingTxs = pool.getPendingTxHashes(address(mockSafe), 0, 3);
        assertEq(pendingTxs.length, 2);
        assertEq(pendingTxs[0], txHashes[0]);
        assertEq(pendingTxs[1], txHashes[2]);

        // Execute remaining transactions
        mockSafe.executeTransaction(txHashes[0], true);
        mockSafe.executeTransaction(txHashes[2], true);

        // Verify all transactions are removed
        pendingTxs = pool.getPendingTxHashes(address(mockSafe), 0, 3);
        assertEq(pendingTxs.length, 0);
    }

    function testGuardMultipleCallsSameTransaction() public {
        // Prepare transaction data
        bytes32 txHash = keccak256("test transaction");
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 1 ether);

        // Propose transaction in the pool
        vm.prank(owner);
        pool.proposeTx(
            txHash,
            address(mockSafe),
            recipient,
            1 ether,
            data,
            Enum.Operation.Call,
            0 // nonce
        );

        // First execution via guard - should succeed
        mockSafe.executeTransaction(txHash, true);

        // Verify transaction was removed
        bytes32[] memory pendingTxs = pool.getPendingTxHashes(address(mockSafe), 0, 1);
        assertEq(pendingTxs.length, 0);

        // Second execution via guard - should not revert (transaction already gone)
        mockSafe.executeTransaction(txHash, true);

        // Verify still no pending transactions
        pendingTxs = pool.getPendingTxHashes(address(mockSafe), 0, 1);
        assertEq(pendingTxs.length, 0);
    }

    function testGuardWithMultipleSafes() public {
        // Prepare transaction data for both Safes
        bytes32 txHash1 = keccak256("test transaction 1");
        bytes32 txHash2 = keccak256("test transaction 2");
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 1 ether);

        // Propose transactions for both Safes
        vm.prank(owner);
        pool.proposeTx(
            txHash1,
            address(mockSafe),
            recipient,
            1 ether,
            data,
            Enum.Operation.Call,
            0 // nonce
        );

        vm.prank(owner2);
        pool.proposeTx(
            txHash2,
            address(mockSafe2),
            recipient,
            1 ether,
            data,
            Enum.Operation.Call,
            0 // nonce
        );

        // Verify both transactions are pending
        bytes32[] memory pendingTxs1 = pool.getPendingTxHashes(address(mockSafe), 0, 1);
        bytes32[] memory pendingTxs2 = pool.getPendingTxHashes(address(mockSafe2), 0, 1);
        assertEq(pendingTxs1.length, 1);
        assertEq(pendingTxs2.length, 1);

        // Execute transaction from first Safe
        mockSafe.executeTransaction(txHash1, true);

        // Verify only first Safe's transaction was removed
        pendingTxs1 = pool.getPendingTxHashes(address(mockSafe), 0, 1);
        pendingTxs2 = pool.getPendingTxHashes(address(mockSafe2), 0, 1);
        assertEq(pendingTxs1.length, 0);
        assertEq(pendingTxs2.length, 1);

        // Execute transaction from second Safe
        mockSafe2.executeTransaction(txHash2, true);

        // Verify both transactions are now removed
        pendingTxs1 = pool.getPendingTxHashes(address(mockSafe), 0, 1);
        pendingTxs2 = pool.getPendingTxHashes(address(mockSafe2), 0, 1);
        assertEq(pendingTxs1.length, 0);
        assertEq(pendingTxs2.length, 0);
    }

    function testGuardWithSignedTransactions() public {
        // Prepare transaction data
        bytes32 txHash = keccak256("test transaction");
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 1 ether);

        // Propose transaction in the pool
        vm.prank(owner);
        pool.proposeTx(
            txHash,
            address(mockSafe),
            recipient,
            1 ether,
            data,
            Enum.Operation.Call,
            0 // nonce
        );

        // Sign the transaction
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(ownerKey, txHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(owner);
        pool.signTx(txHash, signature);

        // Verify signature exists
        assertTrue(pool.hasSignedTx(txHash, owner));
        bytes[] memory signatures = pool.getSignatures(txHash);
        assertEq(signatures.length, 1);

        // Execute via guard
        mockSafe.executeTransaction(txHash, true);

        // Verify transaction and signatures are removed
        bytes32[] memory pendingTxs = pool.getPendingTxHashes(address(mockSafe), 0, 1);
        assertEq(pendingTxs.length, 0);

        // Verify transaction data is completely deleted
        (address txSafe,,,,, address txProposer,,) = pool.getTxDetails(txHash);
        assertEq(txProposer, address(0));
        assertEq(txSafe, address(0));
    }

    function testGuardStateConsistencyAfterExecution() public {
        // Prepare multiple transactions with different nonces
        bytes32[] memory txHashes = new bytes32[](3);
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 1 ether);

        for (uint256 i = 0; i < 3; i++) {
            txHashes[i] = keccak256(abi.encodePacked("test transaction", i));
            vm.prank(owner);
            pool.proposeTx(
                txHashes[i],
                address(mockSafe),
                recipient,
                1 ether,
                data,
                Enum.Operation.Call,
                i // different nonces
            );
        }

        // Get initial state
        bytes32[] memory initialPending = pool.getPendingTxHashes(address(mockSafe), 0, 3);
        assertEq(initialPending.length, 3);

        // Execute transactions in random order via guard
        mockSafe.executeTransaction(txHashes[1], true); // Execute middle one first
        mockSafe.executeTransaction(txHashes[0], true); // Execute first one
        mockSafe.executeTransaction(txHashes[2], true); // Execute last one

        // Verify all transactions are removed and state is consistent
        bytes32[] memory finalPending = pool.getPendingTxHashes(address(mockSafe), 0, 3);
        assertEq(finalPending.length, 0);

        // Verify all transaction data is deleted
        for (uint256 i = 0; i < 3; i++) {
            (address txSafe,,,,, address txProposer,,) = pool.getTxDetails(txHashes[i]);
            assertEq(txProposer, address(0));
            assertEq(txSafe, address(0));
        }
    }

    function testGuardWithEmptyPool() public {
        // Try to execute a transaction that was never proposed
        bytes32 unknownTxHash = keccak256("unknown transaction");

        // This should not revert - guard should handle gracefully
        mockSafe.executeTransaction(unknownTxHash, true);

        // Verify pool remains empty
        bytes32[] memory pendingTxs = pool.getPendingTxHashes(address(mockSafe), 0, 1);
        assertEq(pendingTxs.length, 0);
    }

    function testGuardFailedTransactionDoesNotAffectOthers() public {
        // Prepare multiple transactions
        bytes32[] memory txHashes = new bytes32[](3);
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 1 ether);

        for (uint256 i = 0; i < 3; i++) {
            txHashes[i] = keccak256(abi.encodePacked("test transaction", i));
            vm.prank(owner);
            pool.proposeTx(
                txHashes[i],
                address(mockSafe),
                recipient,
                1 ether,
                data,
                Enum.Operation.Call,
                i
            );
        }

        // Execute one transaction successfully
        mockSafe.executeTransaction(txHashes[0], true);

        // Execute one transaction with failure
        mockSafe.executeTransaction(txHashes[1], false);

        // Execute another transaction successfully
        mockSafe.executeTransaction(txHashes[2], true);

        // Verify only successful transactions were removed
        bytes32[] memory pendingTxs = pool.getPendingTxHashes(address(mockSafe), 0, 3);
        assertEq(pendingTxs.length, 1);
        assertEq(pendingTxs[0], txHashes[1]); // Only failed transaction remains
    }

    function testGuardDirectCallToCheckAfterExecution() public {
        // Prepare transaction data
        bytes32 txHash = keccak256("test transaction");
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 1 ether);

        // Propose transaction in the pool
        vm.prank(owner);
        pool.proposeTx(
            txHash,
            address(mockSafe),
            recipient,
            1 ether,
            data,
            Enum.Operation.Call,
            0
        );

        // Directly call checkAfterExecution (simulating Safe calling it)
        vm.prank(address(mockSafe));
        pool.checkAfterExecution(txHash, true);

        // Verify transaction was removed
        bytes32[] memory pendingTxs = pool.getPendingTxHashes(address(mockSafe), 0, 1);
        assertEq(pendingTxs.length, 0);
    }

    function testGuardDirectCallToCheckAfterExecutionWithFailure() public {
        // Prepare transaction data
        bytes32 txHash = keccak256("test transaction");
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 1 ether);

        // Propose transaction in the pool
        vm.prank(owner);
        pool.proposeTx(
            txHash,
            address(mockSafe),
            recipient,
            1 ether,
            data,
            Enum.Operation.Call,
            0
        );

        // Directly call checkAfterExecution with failure
        vm.prank(address(mockSafe));
        pool.checkAfterExecution(txHash, false);

        // Verify transaction was NOT removed (failure case)
        bytes32[] memory pendingTxs = pool.getPendingTxHashes(address(mockSafe), 0, 1);
        assertEq(pendingTxs.length, 1);
        assertEq(pendingTxs[0], txHash);
    }

    function testGuardVsDirectCallGasComparison() public {
        // Prepare transaction data
        bytes32 txHash1 = keccak256("test transaction 1");
        bytes32 txHash2 = keccak256("test transaction 2");
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 1 ether);

        // Propose both transactions
        vm.prank(owner);
        pool.proposeTx(txHash1, address(mockSafe), recipient, 1 ether, data, Enum.Operation.Call, 0);

        vm.prank(owner);
        pool.proposeTx(txHash2, address(mockSafe), recipient, 1 ether, data, Enum.Operation.Call, 1);

        // Measure gas for direct call to markAsExecuted
        uint256 gasStart = gasleft();
        vm.prank(address(mockSafe));
        pool.markAsExecuted(txHash1);
        uint256 gasUsedDirect = gasStart - gasleft();

        // Measure gas for guard call (via checkAfterExecution)
        gasStart = gasleft();
        mockSafe.executeTransaction(txHash2, true);
        uint256 gasUsedGuard = gasStart - gasleft();

        // Guard call should use more gas due to external call overhead
        assertGt(gasUsedGuard, gasUsedDirect);

        // Both transactions should be removed
        bytes32[] memory pendingTxs = pool.getPendingTxHashes(address(mockSafe), 0, 2);
        assertEq(pendingTxs.length, 0);
    }

    function testGuardWithLargeNumberOfTransactions() public {
        // Create a large number of transactions to test performance
        uint256 numTxs = 50;
        bytes32[] memory txHashes = new bytes32[](numTxs);
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 1 ether);

        // Propose all transactions
        for (uint256 i = 0; i < numTxs; i++) {
            txHashes[i] = keccak256(abi.encodePacked("test transaction", i));
            vm.prank(owner);
            pool.proposeTx(
                txHashes[i],
                address(mockSafe),
                recipient,
                1 ether,
                data,
                Enum.Operation.Call,
                i
            );
        }

        // Verify all transactions are pending
        bytes32[] memory pendingTxs = pool.getPendingTxHashes(address(mockSafe), 0, numTxs);
        assertEq(pendingTxs.length, numTxs);

        // Execute all transactions via guard in reverse order
        for (uint256 i = numTxs; i > 0; i--) {
            mockSafe.executeTransaction(txHashes[i - 1], true);
        }

        // Verify all transactions are removed
        pendingTxs = pool.getPendingTxHashes(address(mockSafe), 0, numTxs);
        assertEq(pendingTxs.length, 0);
    }

    function testGuardWithMixedSuccessFailurePattern() public {
        // Create transactions with alternating success/failure pattern
        bytes32[] memory txHashes = new bytes32[](10);
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 1 ether);

        // Propose all transactions
        for (uint256 i = 0; i < 10; i++) {
            txHashes[i] = keccak256(abi.encodePacked("test transaction", i));
            vm.prank(owner);
            pool.proposeTx(
                txHashes[i],
                address(mockSafe),
                recipient,
                1 ether,
                data,
                Enum.Operation.Call,
                i
            );
        }

        // Execute with alternating success/failure pattern
        for (uint256 i = 0; i < 10; i++) {
            bool success = (i % 2 == 0); // Even indices succeed, odd indices fail
            mockSafe.executeTransaction(txHashes[i], success);
        }

        // Verify only failed transactions remain (odd indices)
        bytes32[] memory pendingTxs = pool.getPendingTxHashes(address(mockSafe), 0, 10);
        assertEq(pendingTxs.length, 5); // 5 failed transactions should remain

        // Verify the remaining transactions are the failed ones (odd indices: 1, 3, 5, 7, 9)
        // Note: Order may not be preserved due to how _removeFromPending works
        bytes32[] memory expectedFailedTxs = new bytes32[](5);
        expectedFailedTxs[0] = txHashes[1]; // index 1
        expectedFailedTxs[1] = txHashes[3]; // index 3
        expectedFailedTxs[2] = txHashes[5]; // index 5
        expectedFailedTxs[3] = txHashes[7]; // index 7
        expectedFailedTxs[4] = txHashes[9]; // index 9

        // Check that all expected failed transactions are still in the pending list
        for (uint256 i = 0; i < 5; i++) {
            bool found = false;
            for (uint256 j = 0; j < pendingTxs.length; j++) {
                if (pendingTxs[j] == expectedFailedTxs[i]) {
                    found = true;
                    break;
                }
            }
            assertTrue(found, "Failed transaction should still be pending");
        }

        // Verify that successful transactions are not in the pending list
        bytes32[] memory expectedSuccessfulTxs = new bytes32[](5);
        expectedSuccessfulTxs[0] = txHashes[0]; // index 0
        expectedSuccessfulTxs[1] = txHashes[2]; // index 2
        expectedSuccessfulTxs[2] = txHashes[4]; // index 4
        expectedSuccessfulTxs[3] = txHashes[6]; // index 6
        expectedSuccessfulTxs[4] = txHashes[8]; // index 8

        for (uint256 i = 0; i < 5; i++) {
            bool found = false;
            for (uint256 j = 0; j < pendingTxs.length; j++) {
                if (pendingTxs[j] == expectedSuccessfulTxs[i]) {
                    found = true;
                    break;
                }
            }
            assertFalse(found, "Successful transaction should not be pending");
        }
    }

    function testGuardEventEmissionOrder() public {
        // Test that events are emitted in the correct order when multiple transactions are executed
        bytes32[] memory txHashes = new bytes32[](3);
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 1 ether);

        // Propose transactions and get their IDs
        uint256[] memory txIds = new uint256[](3);
        for (uint256 i = 0; i < 3; i++) {
            txHashes[i] = keccak256(abi.encodePacked("test transaction", i));
            vm.prank(owner);
            pool.proposeTx(
                txHashes[i],
                address(mockSafe),
                recipient,
                1 ether,
                data,
                Enum.Operation.Call,
                i
            );
            (,,,,,,, uint256 txId) = pool.getTxDetails(txHashes[i]);
            txIds[i] = txId;
        }

        // Execute transactions and verify events are emitted in correct order
        for (uint256 i = 0; i < 3; i++) {
            vm.expectEmit(true, true, true, true);
            emit TransactionExecuted(txHashes[i], address(mockSafe), txIds[i]);
            mockSafe.executeTransaction(txHashes[i], true);
        }
    }

    function testGuardReentrancyProtection() public {
        // This test ensures that the guard mechanism doesn't cause reentrancy issues
        // when markAsExecuted is called via checkAfterExecution

        bytes32 txHash = keccak256("test transaction");
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 1 ether);

        // Propose transaction
        vm.prank(owner);
        pool.proposeTx(
            txHash,
            address(mockSafe),
            recipient,
            1 ether,
            data,
            Enum.Operation.Call,
            0
        );

        // Execute transaction - this internally calls this.markAsExecuted(txHash)
        // which should not cause reentrancy issues
        mockSafe.executeTransaction(txHash, true);

        // Verify transaction was properly removed
        bytes32[] memory pendingTxs = pool.getPendingTxHashes(address(mockSafe), 0, 1);
        assertEq(pendingTxs.length, 0);

        // Verify transaction data is completely cleaned up
        (address txSafe,,,,, address txProposer,,) = pool.getTxDetails(txHash);
        assertEq(txProposer, address(0));
        assertEq(txSafe, address(0));
    }
}
