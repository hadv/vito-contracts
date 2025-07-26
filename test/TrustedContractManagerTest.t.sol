// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/SafeMessagePool.sol";
import "../src/SafePoolRegistry.sol";
import "../src/SafeTxPoolCore.sol";
import "../src/AddressBookManager.sol";
import "../src/DelegateCallManager.sol";
import "../src/TrustedContractManager.sol";
import "../src/TransactionValidator.sol";
import "../src/interfaces/ITrustedContractManager.sol";

contract TrustedContractManagerTest is Test {
    SafePoolRegistry public registry;
    TrustedContractManager public trustedContractManager;

    address public safe = address(0x1234);
    address public contract1 = address(0x5678);
    address public contract2 = address(0x9ABC);
    address public contract3 = address(0xDEF0);

    function setUp() public {
        // Deploy all components
        SafeTxPoolCore txPoolCore = new SafeTxPoolCore();
        AddressBookManager addressBookManager = new AddressBookManager();
        DelegateCallManager delegateCallManager = new DelegateCallManager();
        trustedContractManager = new TrustedContractManager();
        TransactionValidator transactionValidator =
            new TransactionValidator(address(addressBookManager), address(trustedContractManager));

        // Deploy registry
        SafeMessagePool messagePool = new SafeMessagePool();

        registry = new SafePoolRegistry(
            address(txPoolCore),
            address(messagePool),
            address(addressBookManager),
            address(delegateCallManager),
            address(trustedContractManager),
            address(transactionValidator)
        );

        // Set registry addresses for all components (one-time only)
        txPoolCore.setRegistry(address(registry));
        messagePool.setRegistry(address(registry));
        addressBookManager.setRegistry(address(registry));
        delegateCallManager.setRegistry(address(registry));
        trustedContractManager.setRegistry(address(registry));
    }

    function testAddTrustedContract() public {
        vm.prank(safe);
        registry.addTrustedContract(safe, contract1, "Contract 1");

        // Check if contract is trusted
        assertTrue(registry.isTrustedContract(safe, contract1));

        // Get all trusted contracts
        ITrustedContractManager.TrustedContractEntry[] memory contracts = registry.getTrustedContracts(safe);
        assertEq(contracts.length, 1);
        assertEq(contracts[0].contractAddress, contract1);
        assertEq(contracts[0].name, "Contract 1");
    }

    function testAddMultipleTrustedContracts() public {
        vm.prank(safe);
        registry.addTrustedContract(safe, contract1, "Contract 1");

        vm.prank(safe);
        registry.addTrustedContract(safe, contract2, "Contract 2");

        vm.prank(safe);
        registry.addTrustedContract(safe, contract3, "Contract 3");

        // Check all contracts are trusted
        assertTrue(registry.isTrustedContract(safe, contract1));
        assertTrue(registry.isTrustedContract(safe, contract2));
        assertTrue(registry.isTrustedContract(safe, contract3));

        // Get all trusted contracts
        ITrustedContractManager.TrustedContractEntry[] memory contracts = registry.getTrustedContracts(safe);
        assertEq(contracts.length, 3);

        // Check each contract
        bool found1 = false;
        bool found2 = false;
        bool found3 = false;

        for (uint256 i = 0; i < contracts.length; i++) {
            if (contracts[i].contractAddress == contract1 && contracts[i].name == "Contract 1") {
                found1 = true;
            } else if (contracts[i].contractAddress == contract2 && contracts[i].name == "Contract 2") {
                found2 = true;
            } else if (contracts[i].contractAddress == contract3 && contracts[i].name == "Contract 3") {
                found3 = true;
            }
        }

        assertTrue(found1);
        assertTrue(found2);
        assertTrue(found3);
    }

    function testUpdateTrustedContractName() public {
        // Add contract
        vm.prank(safe);
        registry.addTrustedContract(safe, contract1, "Old Name");

        // Update name
        vm.prank(safe);
        registry.addTrustedContract(safe, contract1, "New Name");

        // Check updated name
        ITrustedContractManager.TrustedContractEntry[] memory contracts = registry.getTrustedContracts(safe);
        assertEq(contracts.length, 1);
        assertEq(contracts[0].contractAddress, contract1);
        assertEq(contracts[0].name, "New Name");
    }

    function testRemoveTrustedContract() public {
        // Add contracts
        vm.prank(safe);
        registry.addTrustedContract(safe, contract1, "Contract 1");

        vm.prank(safe);
        registry.addTrustedContract(safe, contract2, "Contract 2");

        // Remove one contract
        vm.prank(safe);
        registry.removeTrustedContract(safe, contract1);

        // Check contract1 is no longer trusted
        assertFalse(registry.isTrustedContract(safe, contract1));
        assertTrue(registry.isTrustedContract(safe, contract2));

        // Check only contract2 remains
        ITrustedContractManager.TrustedContractEntry[] memory contracts = registry.getTrustedContracts(safe);
        assertEq(contracts.length, 1);
        assertEq(contracts[0].contractAddress, contract2);
        assertEq(contracts[0].name, "Contract 2");
    }

    function testEmptyTrustedContractsList() public {
        // Get trusted contracts for safe with no contracts
        ITrustedContractManager.TrustedContractEntry[] memory contracts = registry.getTrustedContracts(safe);
        assertEq(contracts.length, 0);
    }

    function testOnlyAuthorizedCanAddTrustedContract() public {
        address unauthorized = address(0xBAD);

        vm.prank(unauthorized);
        vm.expectRevert();
        registry.addTrustedContract(safe, contract1, "Contract 1");
    }
}
