// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/SafeTxPoolRegistry.sol";
import "../src/SafeTxPoolCore.sol";
import "../src/AddressBookManager.sol";
import "../src/DelegateCallManager.sol";
import "../src/TrustedContractManager.sol";
import "../src/TransactionValidator.sol";
import "../src/interfaces/IDelegateCallManager.sol";

contract SafeTxPoolDelegateCallTest is Test {
    SafeTxPoolRegistry public registry;
    SafeTxPoolCore public txPoolCore;
    DelegateCallManager public delegateCallManager;

    address public safe = address(0x1234);
    address public target1 = address(0x5678);
    address public target2 = address(0x9ABC);
    address public target3 = address(0xDEF0);

    function setUp() public {
        // Deploy components with new pattern
        txPoolCore = new SafeTxPoolCore();
        AddressBookManager addressBookManager = new AddressBookManager(address(0));
        delegateCallManager = new DelegateCallManager(address(0));
        TrustedContractManager trustedContractManager = new TrustedContractManager(address(0));

        TransactionValidator transactionValidator =
            new TransactionValidator(address(addressBookManager), address(trustedContractManager));

        registry = new SafeTxPoolRegistry(
            address(txPoolCore),
            address(addressBookManager),
            address(delegateCallManager),
            address(trustedContractManager),
            address(transactionValidator)
        );

        // Update all components to use the correct registry address
        txPoolCore.setRegistry(address(registry));
        addressBookManager.updateRegistry(address(registry));
        delegateCallManager.updateRegistry(address(registry));
        trustedContractManager.updateRegistry(address(registry));
    }

    function testSetDelegateCallEnabled() public {
        // Initially should be disabled
        bool enabled = registry.isDelegateCallEnabled(safe);
        assertFalse(enabled);

        // Enable delegate calls
        vm.prank(safe);
        registry.setDelegateCallEnabled(safe, true);

        enabled = registry.isDelegateCallEnabled(safe);
        assertTrue(enabled);

        // Disable delegate calls
        vm.prank(safe);
        registry.setDelegateCallEnabled(safe, false);

        enabled = registry.isDelegateCallEnabled(safe);
        assertFalse(enabled);
    }

    function testAddDelegateCallTarget() public {
        vm.prank(safe);
        registry.addDelegateCallTarget(safe, target1);

        bool allowed = registry.isDelegateCallTargetAllowed(safe, target1);
        assertTrue(allowed);

        address[] memory targets = registry.getDelegateCallTargets(safe);
        assertEq(targets.length, 1);
        assertEq(targets[0], target1);
    }

    function testAddMultipleDelegateCallTargets() public {
        vm.prank(safe);
        registry.addDelegateCallTarget(safe, target1);

        vm.prank(safe);
        registry.addDelegateCallTarget(safe, target2);

        vm.prank(safe);
        registry.addDelegateCallTarget(safe, target3);

        address[] memory targets = registry.getDelegateCallTargets(safe);
        assertEq(targets.length, 3);
        assertEq(targets[0], target1);
        assertEq(targets[1], target2);
        assertEq(targets[2], target3);

        // Check all are allowed
        assertTrue(registry.isDelegateCallTargetAllowed(safe, target1));
        assertTrue(registry.isDelegateCallTargetAllowed(safe, target2));
        assertTrue(registry.isDelegateCallTargetAllowed(safe, target3));
    }

    function testRemoveDelegateCallTarget() public {
        // Add multiple targets
        vm.prank(safe);
        registry.addDelegateCallTarget(safe, target1);

        vm.prank(safe);
        registry.addDelegateCallTarget(safe, target2);

        vm.prank(safe);
        registry.addDelegateCallTarget(safe, target3);

        // Remove middle target
        vm.prank(safe);
        registry.removeDelegateCallTarget(safe, target2);

        address[] memory targets = registry.getDelegateCallTargets(safe);
        assertEq(targets.length, 2);

        // target2 should no longer be allowed
        assertFalse(registry.isDelegateCallTargetAllowed(safe, target2));

        // Other targets should still be allowed
        assertTrue(registry.isDelegateCallTargetAllowed(safe, target1));
        assertTrue(registry.isDelegateCallTargetAllowed(safe, target3));
    }

    function testRemoveNonExistentTarget() public {
        // Should not revert when removing non-existent target
        vm.prank(safe);
        registry.removeDelegateCallTarget(safe, target1);

        // Should still have no targets
        address[] memory targets = registry.getDelegateCallTargets(safe);
        assertEq(targets.length, 0);
    }

    function testAddDuplicateTarget() public {
        // Add target
        vm.prank(safe);
        registry.addDelegateCallTarget(safe, target1);

        // Add same target again - should not create duplicate
        vm.prank(safe);
        registry.addDelegateCallTarget(safe, target1);

        address[] memory targets = registry.getDelegateCallTargets(safe);
        assertEq(targets.length, 1);
        assertEq(targets[0], target1);
    }

    function testGetDelegateCallTargetsCount() public {
        assertEq(registry.getDelegateCallTargetsCount(safe), 0);

        vm.prank(safe);
        registry.addDelegateCallTarget(safe, target1);
        assertEq(registry.getDelegateCallTargetsCount(safe), 1);

        vm.prank(safe);
        registry.addDelegateCallTarget(safe, target2);
        assertEq(registry.getDelegateCallTargetsCount(safe), 2);

        vm.prank(safe);
        registry.removeDelegateCallTarget(safe, target1);
        assertEq(registry.getDelegateCallTargetsCount(safe), 1);
    }

    function testHasDelegateCallTargetRestrictions() public {
        // Initially should have no restrictions
        bool hasRestrictions = delegateCallManager.hasDelegateCallTargetRestrictions(safe);
        assertFalse(hasRestrictions);

        // Add a target - should now have restrictions
        vm.prank(safe);
        registry.addDelegateCallTarget(safe, target1);

        hasRestrictions = delegateCallManager.hasDelegateCallTargetRestrictions(safe);
        assertTrue(hasRestrictions);
    }

    function testOnlySafeCanModifyDelegateCallSettings() public {
        address unauthorized = address(0x9999);

        // Try to enable delegate calls as unauthorized user
        vm.prank(unauthorized);
        vm.expectRevert();
        registry.setDelegateCallEnabled(safe, true);

        // Try to add target as unauthorized user
        vm.prank(unauthorized);
        vm.expectRevert();
        registry.addDelegateCallTarget(safe, target1);

        // Try to remove target as unauthorized user
        vm.prank(unauthorized);
        vm.expectRevert();
        registry.removeDelegateCallTarget(safe, target1);
    }

    function testInvalidTargetAddressRejected() public {
        vm.prank(safe);
        vm.expectRevert();
        registry.addDelegateCallTarget(safe, address(0));
    }

    function testDelegateCallSettingsIsolatedBetweenSafes() public {
        address safe2 = address(0x2468);

        // Enable delegate calls for safe1
        vm.prank(safe);
        registry.setDelegateCallEnabled(safe, true);

        // Add target for safe1
        vm.prank(safe);
        registry.addDelegateCallTarget(safe, target1);

        // Add different target for safe2
        vm.prank(safe2);
        registry.addDelegateCallTarget(safe2, target2);

        // Check safe1 settings
        assertTrue(registry.isDelegateCallEnabled(safe));
        assertTrue(registry.isDelegateCallTargetAllowed(safe, target1));
        assertFalse(registry.isDelegateCallTargetAllowed(safe, target2));

        // Check safe2 settings
        assertFalse(registry.isDelegateCallEnabled(safe2)); // Should be disabled by default
        assertFalse(registry.isDelegateCallTargetAllowed(safe2, target1));
        assertTrue(registry.isDelegateCallTargetAllowed(safe2, target2));
    }

    function testDelegateCallEvents() public {
        // Test enable/disable events
        vm.expectEmit(true, false, false, true);
        emit IDelegateCallManager.DelegateCallToggled(safe, true);

        vm.prank(safe);
        registry.setDelegateCallEnabled(safe, true);

        // Test add target event
        vm.expectEmit(true, true, false, false);
        emit IDelegateCallManager.DelegateCallTargetAdded(safe, target1);

        vm.prank(safe);
        registry.addDelegateCallTarget(safe, target1);

        // Test remove target event
        vm.expectEmit(true, true, false, false);
        emit IDelegateCallManager.DelegateCallTargetRemoved(safe, target1);

        vm.prank(safe);
        registry.removeDelegateCallTarget(safe, target1);
    }

    function testEmptyTargetListReturnsEmptyArray() public {
        address[] memory targets = registry.getDelegateCallTargets(safe);
        assertEq(targets.length, 0);
    }

    function testLargeDelegateCallTargetList() public {
        // Test with many targets to ensure gas efficiency
        uint256 numTargets = 30;

        for (uint256 i = 0; i < numTargets; i++) {
            address target = address(uint160(0x2000 + i));

            vm.prank(safe);
            registry.addDelegateCallTarget(safe, target);
        }

        address[] memory targets = registry.getDelegateCallTargets(safe);
        assertEq(targets.length, numTargets);

        // Verify first and last targets
        assertEq(targets[0], address(0x2000));
        assertEq(targets[numTargets - 1], address(uint160(0x2000 + numTargets - 1)));

        // Test removal from middle
        address middleTarget = address(uint160(0x2000 + numTargets / 2));
        vm.prank(safe);
        registry.removeDelegateCallTarget(safe, middleTarget);

        targets = registry.getDelegateCallTargets(safe);
        assertEq(targets.length, numTargets - 1);
        assertFalse(registry.isDelegateCallTargetAllowed(safe, middleTarget));
    }
}
