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
    SafeTxPool public pool;
    MockSafe public mockSafe;
    address public owner;
    address public recipient;
    uint256 public ownerKey;

    function setUp() public {
        // Setup test accounts
        ownerKey = 0xA11CE;
        owner = vm.addr(ownerKey);
        recipient = address(0x5678);

        // Deploy SafeTxPool
        pool = new SafeTxPool();

        // Deploy mock Safe
        mockSafe = new MockSafe(pool);

        // Fund the owner
        vm.deal(owner, 10 ether);
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
}
