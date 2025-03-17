// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {SafeTxPool} from "../src/SafeTxPool.sol";
import {Enum} from "@safe-global/safe-contracts/contracts/common/Enum.sol";

contract SafeTxPoolTest is Test {
    event TransactionDeleted(bytes32 indexed txHash, address indexed safe, address indexed proposer);

    SafeTxPool public pool;
    address public safe;
    address public owner1;
    address public owner2;
    address public recipient;
    uint256 public owner1Key;
    uint256 public owner2Key;

    function setUp() public {
        // Setup test accounts
        owner1Key = 0xA11CE;
        owner2Key = 0xB0B;
        owner1 = vm.addr(owner1Key);
        owner2 = vm.addr(owner2Key);
        safe = address(0x1234); // Mock Safe address
        recipient = address(0x5678);

        // Deploy SafeTxPool
        pool = new SafeTxPool();
    }

    function testProposeTransaction() public {
        // Prepare transaction data
        bytes32 txHash = keccak256("test transaction");
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 100 ether);

        // Propose transaction
        vm.prank(owner1);
        pool.proposeTx(
            txHash,
            safe,
            recipient,
            0,
            data,
            Enum.Operation.Call,
            0 // nonce
        );

        // Verify transaction details
        (
            address txSafe,
            address txTo,
            uint256 txValue,
            bytes memory txData,
            Enum.Operation txOperation,
            address txProposer,
            uint256 txNonce
        ) = pool.getTxDetails(txHash);

        assertEq(txSafe, safe);
        assertEq(txTo, recipient);
        assertEq(txValue, 0);
        assertEq(txData, data);
        assertEq(uint256(txOperation), uint256(Enum.Operation.Call));
        assertEq(txProposer, owner1);
        assertEq(txNonce, 0);

        // Verify pending transactions for this Safe
        bytes32[] memory pendingTxs = pool.getPendingTxHashes(safe, 0, 1);
        assertEq(pendingTxs.length, 1);
        assertEq(pendingTxs[0], txHash);
    }

    function testSignTransaction() public {
        // Prepare and propose transaction
        bytes32 txHash = keccak256("test transaction");
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 100 ether);

        vm.prank(owner1);
        pool.proposeTx(txHash, safe, recipient, 0, data, Enum.Operation.Call, 0);

        // Create signature
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(owner1Key, txHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        // Sign transaction
        vm.prank(owner1);
        pool.signTx(txHash, signature);

        // Verify signature
        assertTrue(pool.hasSignedTx(txHash, owner1));
        bytes[] memory signatures = pool.getSignatures(txHash);
        assertEq(signatures.length, 1);
        assertEq(signatures[0], signature);
    }

    function testMarkAsExecuted() public {
        // Prepare and propose transaction
        bytes32 txHash = keccak256("test transaction");
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 100 ether);

        vm.prank(owner1);
        pool.proposeTx(txHash, safe, recipient, 0, data, Enum.Operation.Call, 0);

        // Mark as executed
        vm.prank(safe);
        pool.markAsExecuted(txHash);

        // Verify removed from pending
        bytes32[] memory pendingTxs = pool.getPendingTxHashes(safe, 0, 1);
        assertEq(pendingTxs.length, 0);
    }

    function test_RevertWhen_SigningExecutedTransaction() public {
        // Prepare and propose transaction
        bytes32 txHash = keccak256("test transaction");
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 100 ether);

        vm.prank(owner1);
        pool.proposeTx(txHash, safe, recipient, 0, data, Enum.Operation.Call, 0);

        // Mark as executed
        vm.prank(safe);
        pool.markAsExecuted(txHash);

        // Try to sign executed transaction
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(owner1Key, txHash);
        bytes memory signature = abi.encodePacked(r, s, v);

        vm.prank(owner1);
        vm.expectRevert(SafeTxPool.TransactionNotFound.selector);
        pool.signTx(txHash, signature);
    }

    function test_RevertWhen_NonSafeMarkingAsExecuted() public {
        // Prepare and propose transaction
        bytes32 txHash = keccak256("test transaction");
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 100 ether);

        vm.prank(owner1);
        pool.proposeTx(txHash, safe, recipient, 0, data, Enum.Operation.Call, 0);

        // Try to mark as executed by non-safe address
        vm.prank(owner1);
        vm.expectRevert(SafeTxPool.NotSafeWallet.selector);
        pool.markAsExecuted(txHash);
    }

    function test_RevertWhen_ProposingDuplicateTransaction() public {
        // Prepare transaction data
        bytes32 txHash = keccak256("test transaction");
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 100 ether);

        // Propose transaction first time
        vm.prank(owner1);
        pool.proposeTx(txHash, safe, recipient, 0, data, Enum.Operation.Call, 0);

        // Try to propose same transaction again
        vm.prank(owner2);
        vm.expectRevert("Transaction already proposed");
        pool.proposeTx(txHash, safe, recipient, 0, data, Enum.Operation.Call, 0);
    }

    function testMultipleSafes() public {
        // Create another Safe
        address safe2 = address(0x8765);

        // Prepare transaction data for first Safe
        bytes32 txHash1 = keccak256("test transaction 1");
        bytes memory data1 = abi.encodeWithSignature("transfer(address,uint256)", recipient, 100 ether);

        // Prepare transaction data for second Safe
        bytes32 txHash2 = keccak256("test transaction 2");
        bytes memory data2 = abi.encodeWithSignature("transfer(address,uint256)", recipient, 200 ether);

        // Propose transactions for both Safes
        vm.prank(owner1);
        pool.proposeTx(txHash1, safe, recipient, 0, data1, Enum.Operation.Call, 0);

        vm.prank(owner2);
        pool.proposeTx(txHash2, safe2, recipient, 0, data2, Enum.Operation.Call, 0);

        // Verify pending transactions for each Safe
        bytes32[] memory pendingTxs1 = pool.getPendingTxHashes(safe, 0, 1);
        bytes32[] memory pendingTxs2 = pool.getPendingTxHashes(safe2, 0, 1);

        assertEq(pendingTxs1.length, 1);
        assertEq(pendingTxs2.length, 1);
        assertEq(pendingTxs1[0], txHash1);
        assertEq(pendingTxs2[0], txHash2);
    }

    function testDeleteTx() public {
        // Prepare and propose transaction
        bytes32 txHash = keccak256("test transaction");
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 100 ether);

        vm.prank(owner1);
        pool.proposeTx(txHash, safe, recipient, 0, data, Enum.Operation.Call, 0);

        // Delete transaction
        vm.prank(owner1);
        pool.deleteTx(txHash);

        // Verify removed from pending
        bytes32[] memory pendingTxs = pool.getPendingTxHashes(safe, 0, 1);
        assertEq(pendingTxs.length, 0);
    }

    function test_RevertWhen_NonProposerDeletingTx() public {
        // Prepare and propose transaction
        bytes32 txHash = keccak256("test transaction");
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 100 ether);

        vm.prank(owner1);
        pool.proposeTx(txHash, safe, recipient, 0, data, Enum.Operation.Call, 0);

        // Try to delete transaction by non-proposer
        vm.prank(owner2);
        vm.expectRevert(SafeTxPool.NotProposer.selector);
        pool.deleteTx(txHash);
    }

    function test_RevertWhen_DeletingNonExistentTx() public {
        bytes32 txHash = keccak256("non-existent transaction");

        vm.prank(owner1);
        vm.expectRevert(SafeTxPool.TransactionNotFound.selector);
        pool.deleteTx(txHash);
    }

    function testGetPendingTxHashesPagination() public {
        // Create multiple transactions
        bytes32[] memory txHashes = new bytes32[](5);
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 100 ether);

        for (uint256 i = 0; i < 5; i++) {
            txHashes[i] = keccak256(abi.encodePacked("test transaction", i));
            vm.prank(owner1);
            pool.proposeTx(txHashes[i], safe, recipient, 0, data, Enum.Operation.Call, i);
        }

        // Test first page (2 items)
        bytes32[] memory firstPage = pool.getPendingTxHashes(safe, 0, 2);
        assertEq(firstPage.length, 2);
        assertEq(firstPage[0], txHashes[0]);
        assertEq(firstPage[1], txHashes[1]);

        // Test second page (2 items)
        bytes32[] memory secondPage = pool.getPendingTxHashes(safe, 2, 2);
        assertEq(secondPage.length, 2);
        assertEq(secondPage[0], txHashes[2]);
        assertEq(secondPage[1], txHashes[3]);

        // Test last page (1 item)
        bytes32[] memory lastPage = pool.getPendingTxHashes(safe, 4, 2);
        assertEq(lastPage.length, 1);
        assertEq(lastPage[0], txHashes[4]);

        // Test empty page (beyond array length)
        bytes32[] memory emptyPage = pool.getPendingTxHashes(safe, 5, 2);
        assertEq(emptyPage.length, 0);

        // Test partial last page
        bytes32[] memory partialPage = pool.getPendingTxHashes(safe, 3, 3);
        assertEq(partialPage.length, 2);
        assertEq(partialPage[0], txHashes[3]);
        assertEq(partialPage[1], txHashes[4]);
    }

    function testGetPendingTxHashesPaginationWithExecutedTx() public {
        // Create multiple transactions
        bytes32[] memory txHashes = new bytes32[](3);
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 100 ether);

        for (uint256 i = 0; i < 3; i++) {
            txHashes[i] = keccak256(abi.encodePacked("test transaction", i));
            vm.prank(owner1);
            pool.proposeTx(txHashes[i], safe, recipient, 0, data, Enum.Operation.Call, i);
        }

        // Execute middle transaction
        vm.prank(safe);
        pool.markAsExecuted(txHashes[1]);

        // Test pagination after execution
        bytes32[] memory firstPage = pool.getPendingTxHashes(safe, 0, 2);
        assertEq(firstPage.length, 2);
        assertEq(firstPage[0], txHashes[0]);
        assertEq(firstPage[1], txHashes[2]);

        // Test second page (should be empty)
        bytes32[] memory secondPage = pool.getPendingTxHashes(safe, 2, 2);
        assertEq(secondPage.length, 0);
    }

    function testGetPendingTxHashesPaginationWithMultipleSafes() public {
        // Create another Safe
        address safe2 = address(0x8765);

        // Create transactions for first Safe
        bytes32[] memory txHashes1 = new bytes32[](3);
        bytes memory data1 = abi.encodeWithSignature("transfer(address,uint256)", recipient, 100 ether);

        for (uint256 i = 0; i < 3; i++) {
            txHashes1[i] = keccak256(abi.encodePacked("test transaction 1", i));
            vm.prank(owner1);
            pool.proposeTx(txHashes1[i], safe, recipient, 0, data1, Enum.Operation.Call, i);
        }

        // Create transactions for second Safe
        bytes32[] memory txHashes2 = new bytes32[](2);
        bytes memory data2 = abi.encodeWithSignature("transfer(address,uint256)", recipient, 200 ether);

        for (uint256 i = 0; i < 2; i++) {
            txHashes2[i] = keccak256(abi.encodePacked("test transaction 2", i));
            vm.prank(owner2);
            pool.proposeTx(txHashes2[i], safe2, recipient, 0, data2, Enum.Operation.Call, i);
        }

        // Test pagination for first Safe
        bytes32[] memory firstPage1 = pool.getPendingTxHashes(safe, 0, 2);
        assertEq(firstPage1.length, 2);
        assertEq(firstPage1[0], txHashes1[0]);
        assertEq(firstPage1[1], txHashes1[1]);

        // Test pagination for second Safe
        bytes32[] memory firstPage2 = pool.getPendingTxHashes(safe2, 0, 2);
        assertEq(firstPage2.length, 2);
        assertEq(firstPage2[0], txHashes2[0]);
        assertEq(firstPage2[1], txHashes2[1]);
    }

    function testDeleteTxKeepsSameNonceTxs() public {
        // Prepare and propose first transaction
        bytes32 txHash1 = keccak256("test transaction 1");
        bytes memory data1 = abi.encodeWithSignature("transfer(address,uint256)", recipient, 100 ether);

        vm.prank(owner1);
        pool.proposeTx(txHash1, safe, recipient, 0, data1, Enum.Operation.Call, 1); // nonce 1

        // Prepare and propose second transaction with same nonce
        bytes32 txHash2 = keccak256("test transaction 2");
        bytes memory data2 = abi.encodeWithSignature("transfer(address,uint256)", recipient, 200 ether);

        vm.prank(owner2);
        pool.proposeTx(txHash2, safe, recipient, 0, data2, Enum.Operation.Call, 1); // same nonce 1

        // Delete first transaction
        vm.prank(owner1);
        vm.expectEmit(true, true, true, true);
        emit TransactionDeleted(txHash1, safe, owner1);
        pool.deleteTx(txHash1);

        // Verify second transaction still exists
        bytes32[] memory pendingTxs = pool.getPendingTxHashes(safe, 0, 2);
        assertEq(pendingTxs.length, 1);
        assertEq(pendingTxs[0], txHash2);

        // Verify first transaction data is deleted
        (address txSafe,,,,, address txProposer,) = pool.getTxDetails(txHash1);
        assertEq(txProposer, address(0));
        assertEq(txSafe, address(0));

        // Verify second transaction data is intact
        (address safe_,,,,, address proposer_, uint256 nonce_) = pool.getTxDetails(txHash2);
        assertEq(proposer_, owner2);
        assertEq(safe_, safe);
        assertEq(nonce_, 1);
    }

    function testDeleteTxWithMultiplePendingTxs() public {
        // Propose multiple transactions with different nonces
        bytes32[] memory txHashes = new bytes32[](3);
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 100 ether);

        for (uint256 i = 0; i < 3; i++) {
            txHashes[i] = keccak256(abi.encodePacked("test transaction", i));
            vm.prank(owner1);
            pool.proposeTx(txHashes[i], safe, recipient, 0, data, Enum.Operation.Call, i);
        }

        // Delete middle transaction
        vm.prank(owner1);
        pool.deleteTx(txHashes[1]);

        // Verify remaining transactions
        bytes32[] memory pendingTxs = pool.getPendingTxHashes(safe, 0, 3);
        assertEq(pendingTxs.length, 2);
        assertEq(pendingTxs[0], txHashes[0]);
        assertEq(pendingTxs[1], txHashes[2]);

        // Verify middle transaction is properly deleted
        (address txSafe,,,,, address txProposer,) = pool.getTxDetails(txHashes[1]);
        assertEq(txProposer, address(0));
        assertEq(txSafe, address(0));
    }

    function testDeleteLastPendingTx() public {
        // Propose multiple transactions
        bytes32[] memory txHashes = new bytes32[](3);
        bytes memory data = abi.encodeWithSignature("transfer(address,uint256)", recipient, 100 ether);

        for (uint256 i = 0; i < 3; i++) {
            txHashes[i] = keccak256(abi.encodePacked("test transaction", i));
            vm.prank(owner1);
            pool.proposeTx(txHashes[i], safe, recipient, 0, data, Enum.Operation.Call, i);
        }

        // Delete last transaction
        vm.prank(owner1);
        pool.deleteTx(txHashes[2]);

        // Verify remaining transactions
        bytes32[] memory pendingTxs = pool.getPendingTxHashes(safe, 0, 3);
        assertEq(pendingTxs.length, 2);
        assertEq(pendingTxs[0], txHashes[0]);
        assertEq(pendingTxs[1], txHashes[1]);

        // Try to get details of deleted transaction
        (address txSafe,,,,, address txProposer,) = pool.getTxDetails(txHashes[2]);
        assertEq(txProposer, address(0));
        assertEq(txSafe, address(0));
    }
}
