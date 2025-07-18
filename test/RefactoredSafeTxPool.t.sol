// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/SafeTxPoolCore.sol";
import "../src/AddressBookManager.sol";
import "../src/DelegateCallManager.sol";
import "../src/TrustedContractManager.sol";
import "../src/TransactionValidator.sol";
import "../src/SafeTxPoolRegistry.sol";
import "@safe-global/safe-contracts/contracts/common/Enum.sol";

contract RefactoredSafeTxPoolTest is Test {
    SafeTxPoolCore public txPoolCore;
    AddressBookManager public addressBookManager;
    DelegateCallManager public delegateCallManager;
    TrustedContractManager public trustedContractManager;
    TransactionValidator public transactionValidator;
    SafeTxPoolRegistry public registry;

    address public safe = address(0x1234);
    address public owner1 = address(0x5678);
    address public recipient = address(0x9ABC);

    function setUp() public {
        // Deploy all components
        txPoolCore = new SafeTxPoolCore();
        addressBookManager = new AddressBookManager();
        delegateCallManager = new DelegateCallManager();
        trustedContractManager = new TrustedContractManager();
        
        transactionValidator = new TransactionValidator(
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
    }

    function testRefactoredContractSizes() public {
        // Verify that all contracts are within reasonable size limits
        // This is more of a documentation test to show the size improvements
        
        uint256 txPoolCoreSize = address(txPoolCore).code.length;
        uint256 addressBookSize = address(addressBookManager).code.length;
        uint256 delegateCallSize = address(delegateCallManager).code.length;
        uint256 trustedContractSize = address(trustedContractManager).code.length;
        uint256 validatorSize = address(transactionValidator).code.length;
        uint256 registrySize = address(registry).code.length;
        
        console.log("Contract sizes:");
        console.log("SafeTxPoolCore:         ", txPoolCoreSize);
        console.log("AddressBookManager:     ", addressBookSize);
        console.log("DelegateCallManager:    ", delegateCallSize);
        console.log("TrustedContractManager: ", trustedContractSize);
        console.log("TransactionValidator:   ", validatorSize);
        console.log("SafeTxPoolRegistry:     ", registrySize);
        
        // All contracts should be well under the 24KB limit
        assertLt(txPoolCoreSize, 24576, "SafeTxPoolCore too large");
        assertLt(addressBookSize, 24576, "AddressBookManager too large");
        assertLt(delegateCallSize, 24576, "DelegateCallManager too large");
        assertLt(trustedContractSize, 24576, "TrustedContractManager too large");
        assertLt(validatorSize, 24576, "TransactionValidator too large");
        assertLt(registrySize, 24576, "SafeTxPoolRegistry too large");
    }

    function testBasicFunctionality() public {
        // Test that the registry provides the same interface as the original contract
        
        // Add recipient to address book
        vm.prank(safe);
        registry.addAddressBookEntry(safe, recipient, "Test Recipient");
        
        // Verify address book entry was added
        IAddressBookManager.AddressBookEntry[] memory entries = registry.getAddressBookEntries(safe);
        assertEq(entries.length, 1);
        assertEq(entries[0].walletAddress, recipient);
        assertEq(entries[0].name, "Test Recipient");
        
        // Propose a transaction
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

    function testComponentIntegration() public {
        // Test that components work together correctly
        
        // Add trusted contract
        vm.prank(safe);
        registry.addTrustedContract(safe, recipient);
        
        // Verify trusted contract was added
        assertTrue(registry.isTrustedContract(safe, recipient));
        
        // Enable delegate calls
        vm.prank(safe);
        registry.setDelegateCallEnabled(safe, true);
        
        // Verify delegate calls are enabled
        assertTrue(registry.isDelegateCallEnabled(safe));
        
        // Add delegate call target
        vm.prank(safe);
        registry.addDelegateCallTarget(safe, recipient);
        
        // Verify delegate call target was added
        assertTrue(registry.isDelegateCallTargetAllowed(safe, recipient));
        
        address[] memory targets = registry.getDelegateCallTargets(safe);
        assertEq(targets.length, 1);
        assertEq(targets[0], recipient);
    }

    function testGuardInterface() public {
        // Test that the guard interface works correctly
        
        // Add recipient to address book for validation
        vm.prank(safe);
        registry.addAddressBookEntry(safe, recipient, "Test Recipient");
        
        // Test checkTransaction - should not revert for valid transaction
        vm.prank(safe);
        registry.checkTransaction(
            recipient,
            1 ether,
            "",
            Enum.Operation.Call,
            0, 0, 0,
            address(0),
            payable(address(0)),
            "",
            address(0)
        );
        
        // Test checkAfterExecution
        bytes32 txHash = keccak256("test transaction");
        vm.prank(safe);
        registry.checkAfterExecution(txHash, true);
    }
}
