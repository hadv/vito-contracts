// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "../src/SafeTxPool.sol";

contract MockSafe {
    SafeTxPool public pool;

    constructor(SafeTxPool _pool) {
        pool = _pool;
    }

    function setDelegateCallEnabled(bool enabled) external {
        pool.setDelegateCallEnabled(address(this), enabled);
    }

    function addDelegateCallTarget(address target) external {
        pool.addDelegateCallTarget(address(this), target);
    }

    function removeDelegateCallTarget(address target) external {
        pool.removeDelegateCallTarget(address(this), target);
    }
}

contract DelegateCallTargetsTest is Test {
    SafeTxPool public pool;
    MockSafe public mockSafe;

    address public target1 = address(0x1111);
    address public target2 = address(0x2222);
    address public target3 = address(0x3333);

    function setUp() public {
        pool = new SafeTxPool();
        mockSafe = new MockSafe(pool);
    }

    function testGetDelegateCallTargetsEmpty() public {
        address[] memory targets = pool.getDelegateCallTargets(address(mockSafe));
        assertEq(targets.length, 0);
        assertEq(pool.getDelegateCallTargetsCount(address(mockSafe)), 0);
    }

    function testAddSingleTarget() public {
        mockSafe.addDelegateCallTarget(target1);

        address[] memory targets = pool.getDelegateCallTargets(address(mockSafe));
        assertEq(targets.length, 1);
        assertEq(targets[0], target1);
        assertEq(pool.getDelegateCallTargetsCount(address(mockSafe)), 1);
        assertTrue(pool.isDelegateCallTargetAllowed(address(mockSafe), target1));
    }

    function testAddMultipleTargets() public {
        mockSafe.addDelegateCallTarget(target1);
        mockSafe.addDelegateCallTarget(target2);
        mockSafe.addDelegateCallTarget(target3);

        address[] memory targets = pool.getDelegateCallTargets(address(mockSafe));
        assertEq(targets.length, 3);
        assertEq(pool.getDelegateCallTargetsCount(address(mockSafe)), 3);

        // Check all targets are present (order might vary)
        bool found1 = false;
        bool found2 = false;
        bool found3 = false;

        for (uint256 i = 0; i < targets.length; i++) {
            if (targets[i] == target1) found1 = true;
            if (targets[i] == target2) found2 = true;
            if (targets[i] == target3) found3 = true;
        }

        assertTrue(found1);
        assertTrue(found2);
        assertTrue(found3);

        assertTrue(pool.isDelegateCallTargetAllowed(address(mockSafe), target1));
        assertTrue(pool.isDelegateCallTargetAllowed(address(mockSafe), target2));
        assertTrue(pool.isDelegateCallTargetAllowed(address(mockSafe), target3));
    }

    function testRemoveTarget() public {
        // Add targets
        mockSafe.addDelegateCallTarget(target1);
        mockSafe.addDelegateCallTarget(target2);
        mockSafe.addDelegateCallTarget(target3);

        // Remove middle target
        mockSafe.removeDelegateCallTarget(target2);

        address[] memory targets = pool.getDelegateCallTargets(address(mockSafe));
        assertEq(targets.length, 2);
        assertEq(pool.getDelegateCallTargetsCount(address(mockSafe)), 2);

        // Check remaining targets
        assertTrue(pool.isDelegateCallTargetAllowed(address(mockSafe), target1));
        assertFalse(pool.isDelegateCallTargetAllowed(address(mockSafe), target2));
        assertTrue(pool.isDelegateCallTargetAllowed(address(mockSafe), target3));
    }

    function testRemoveAllTargets() public {
        // Add targets
        mockSafe.addDelegateCallTarget(target1);
        mockSafe.addDelegateCallTarget(target2);

        // Remove all targets
        mockSafe.removeDelegateCallTarget(target1);
        mockSafe.removeDelegateCallTarget(target2);

        address[] memory targets = pool.getDelegateCallTargets(address(mockSafe));
        assertEq(targets.length, 0);
        assertEq(pool.getDelegateCallTargetsCount(address(mockSafe)), 0);

        assertFalse(pool.isDelegateCallTargetAllowed(address(mockSafe), target1));
        assertFalse(pool.isDelegateCallTargetAllowed(address(mockSafe), target2));
    }

    function testAddDuplicateTarget() public {
        mockSafe.addDelegateCallTarget(target1);
        mockSafe.addDelegateCallTarget(target1); // Duplicate

        address[] memory targets = pool.getDelegateCallTargets(address(mockSafe));
        assertEq(targets.length, 1); // Should not add duplicate
        assertEq(targets[0], target1);
        assertEq(pool.getDelegateCallTargetsCount(address(mockSafe)), 1);
    }

    function testRemoveNonExistentTarget() public {
        mockSafe.addDelegateCallTarget(target1);
        mockSafe.removeDelegateCallTarget(target2); // Target2 was never added

        address[] memory targets = pool.getDelegateCallTargets(address(mockSafe));
        assertEq(targets.length, 1);
        assertEq(targets[0], target1);
        assertTrue(pool.isDelegateCallTargetAllowed(address(mockSafe), target1));
        assertFalse(pool.isDelegateCallTargetAllowed(address(mockSafe), target2));
    }
}
