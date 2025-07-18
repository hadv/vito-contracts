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
    
    constructor(SafeTxPoolRegistry _guard) {
        guard = _guard;
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
        bytes32 txHash = keccak256(
            abi.encode(to, value, data, operation, safeTxGas, baseGas, gasPrice, gasToken, refundReceiver, block.chainid)
        );
        
        // Call guard before execution
        guard.checkTransaction(
            to, value, data, operation, safeTxGas, baseGas, gasPrice, gasToken, refundReceiver, signatures, msg.sender
        );
        
        // Simulate transaction execution
        success = true;
        
        // Call guard after execution
        guard.checkAfterExecution(txHash, success);
        
        return success;
    }
}

contract SafeTxPoolGuardTest is Test {
    SafeTxPoolRegistry public registry;
    MockSafe public mockSafe;

    address public safe;
    address public owner1 = address(0x5678);
    address public recipient = address(0x9ABC);

    function setUp() public {
        // Deploy components
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
        registry.checkTransaction(
            recipient,
            1 ether,
            data,
            Enum.Operation.Call,
            0, 0, 0,
            address(0),
            payable(address(0)),
            signatures,
            owner1
        );
    }

    function testGuardRejectsTransactionToUnknownAddress() public {
        address unknownAddress = address(0xDEAD);
        bytes memory data = "";
        bytes memory signatures = "";
        
        // Should revert for transaction to address not in address book
        vm.expectRevert();
        registry.checkTransaction(
            unknownAddress,
            1 ether,
            data,
            Enum.Operation.Call,
            0, 0, 0,
            address(0),
            payable(address(0)),
            signatures,
            owner1
        );
    }

    function testGuardAllowsSelfCall() public {
        bytes memory data = "";
        bytes memory signatures = "";
        
        // Should allow calls to the Safe itself
        registry.checkTransaction(
            safe,
            0,
            data,
            Enum.Operation.Call,
            0, 0, 0,
            address(0),
            payable(address(0)),
            signatures,
            owner1
        );
    }

    function testGuardAllowsGuardCall() public {
        bytes memory data = "";
        bytes memory signatures = "";
        
        // Should allow calls to the guard contract itself
        registry.checkTransaction(
            address(registry),
            0,
            data,
            Enum.Operation.Call,
            0, 0, 0,
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
        registry.proposeTx(
            txHash,
            safe,
            recipient,
            1 ether,
            data,
            Enum.Operation.Call,
            0
        );
        
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
        registry.proposeTx(
            txHash,
            safe,
            recipient,
            1 ether,
            data,
            Enum.Operation.Call,
            0
        );
        
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
        
        // Add delegate call target
        vm.prank(safe);
        registry.addDelegateCallTarget(safe, delegateTarget);
        
        // Should allow delegate call to allowed target
        registry.checkTransaction(
            delegateTarget,
            0,
            data,
            Enum.Operation.DelegateCall,
            0, 0, 0,
            address(0),
            payable(address(0)),
            signatures,
            owner1
        );
        
        // Should reject delegate call to non-allowed target
        address nonAllowedTarget = address(0xDEAD);
        vm.expectRevert();
        registry.checkTransaction(
            nonAllowedTarget,
            0,
            data,
            Enum.Operation.DelegateCall,
            0, 0, 0,
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
        registry.addTrustedContract(safe, trustedContract);
        
        // Should allow calls to trusted contracts even if not in address book
        registry.checkTransaction(
            trustedContract,
            1 ether,
            data,
            Enum.Operation.Call,
            0, 0, 0,
            address(0),
            payable(address(0)),
            signatures,
            owner1
        );
    }

    function testFullTransactionFlow() public {
        bytes32 txHash = keccak256("full flow test");
        bytes memory data = "";
        bytes memory signatures = "";
        
        // 1. Propose transaction
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
        
        // 2. Execute transaction through mock safe (includes guard checks)
        mockSafe.execTransaction(
            recipient,
            1 ether,
            data,
            Enum.Operation.Call,
            0, 0, 0,
            address(0),
            payable(address(0)),
            signatures
        );
        
        // 3. Verify transaction was automatically marked as executed
        (address txSafe,,,,,,,) = registry.getTxDetails(txHash);
        assertEq(txSafe, address(0)); // Should be empty/deleted
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
}
