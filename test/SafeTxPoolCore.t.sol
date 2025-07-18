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

    address public safe = address(0x1234);
    address public owner1 = address(0x5678);
    address public owner2 = address(0x9ABC);
    address public recipient = address(0xDEF0);

    function setUp() public {
        // Use the deployment script to create a properly configured registry
        // This mirrors the actual deployment and ensures all access control works

        // Deploy using the same pattern as DeploySafeTxPool.s.sol
        SafeTxPoolRegistry tempRegistry = new SafeTxPoolRegistry(
            address(0), address(0), address(0), address(0), address(0)
        );
        address registryAddress = address(tempRegistry);

        SafeTxPoolCore txPoolCore = new SafeTxPoolCore();
        AddressBookManager addressBookManager = new AddressBookManager(registryAddress);
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
        assertEq(txProposer, owner1);
        assertEq(txNonce, 0);
        assertEq(txId, 1);
    }

    function testSignTx() public {
        bytes32 txHash = keccak256("test transaction");
        bytes memory data = "";
        
        // First propose the transaction
        vm.prank(owner1);
        registry.proposeTx(
            txHash,
            safe,
            recipient,
            1 ether,
            data,
            Enum.Operation.Call,
            0
        );
        
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
