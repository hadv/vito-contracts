// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {SafeTxPool} from "../src/SafeTxPool.sol";
import {Enum} from "@safe-global/safe-contracts/contracts/common/Enum.sol";

contract SafeTxPoolTest is Test {
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
        bytes32[] memory pendingTxs = pool.getPendingTxHashes(safe);
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
        bytes32[] memory pendingTxs = pool.getPendingTxHashes(safe);
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
        bytes32[] memory pendingTxs1 = pool.getPendingTxHashes(safe);
        bytes32[] memory pendingTxs2 = pool.getPendingTxHashes(safe2);

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
        bytes32[] memory pendingTxs = pool.getPendingTxHashes(safe);
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
}
