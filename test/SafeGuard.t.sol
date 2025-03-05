// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {SafeGuard} from "../src/SafeGuard.sol";
import {Enum} from "@safe-global/safe-contracts/contracts/common/Enum.sol";

contract SafeGuardTest is Test {
    address constant ADDRESS_ZERO = address(0);
    SafeGuard public guard;
    address public owner;
    address public unauthorizedTarget;

    function setUp() public {
        // Setup owner
        owner = address(this);
        unauthorizedTarget = makeAddr("unauthorizedTarget");

        // Deploy guard with no allowed targets
        address[] memory targets = new address[](0);
        guard = new SafeGuard(targets);
    }

    function test_AddAllowedTarget() public {
        // Add target as owner
        guard.addAllowedTarget(unauthorizedTarget);

        // Verify target was added
        assertTrue(guard.allowedTargets(unauthorizedTarget), "Target should be added");
    }

    function test_RemoveAllowedTarget() public {
        // Add target first
        guard.addAllowedTarget(unauthorizedTarget);

        // Remove target as owner
        guard.removeAllowedTarget(unauthorizedTarget);

        // Verify target was removed
        assertFalse(guard.allowedTargets(unauthorizedTarget), "Target should be removed");
    }

    function test_OnlyOwnerCanManageTargets() public {
        // Try to add target from unauthorized address
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert(abi.encodeWithSelector(SafeGuard.OnlyOwner.selector));
        guard.addAllowedTarget(unauthorizedTarget);

        // Try to remove target from unauthorized address
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert(abi.encodeWithSelector(SafeGuard.OnlyOwner.selector));
        guard.removeAllowedTarget(unauthorizedTarget);
    }

    function test_AllowedTarget() public view {
        // Check that the allowed target is set correctly
        assertFalse(guard.allowedTargets(unauthorizedTarget), "Target should not be allowed");
    }

    function test_CheckTransactionDelegateCall() public {
        // Prepare transaction data
        bytes memory callData = abi.encodeWithSelector(bytes4(0), ADDRESS_ZERO);

        // Test delegate call to unauthorized target
        vm.expectRevert(abi.encodeWithSelector(SafeGuard.DelegateCallRestricted.selector));
        guard.checkTransaction(
            unauthorizedTarget,
            0,
            callData,
            Enum.Operation.DelegateCall,
            0,
            0,
            0,
            ADDRESS_ZERO,
            payable(ADDRESS_ZERO),
            bytes(""),
            msg.sender
        );

        // Add target as allowed
        guard.addAllowedTarget(unauthorizedTarget);

        // Test delegate call to authorized target
        guard.checkTransaction(
            unauthorizedTarget,
            0,
            callData,
            Enum.Operation.DelegateCall,
            0,
            0,
            0,
            ADDRESS_ZERO,
            payable(ADDRESS_ZERO),
            bytes(""),
            msg.sender
        );
    }

    function test_CheckTransactionNormalCall() public view {
        // Normal call should succeed
        guard.checkTransaction(
            unauthorizedTarget,
            0,
            "",
            Enum.Operation.Call,
            0,
            0,
            0,
            ADDRESS_ZERO,
            payable(ADDRESS_ZERO),
            bytes(""),
            msg.sender
        );
    }

    function test_FallbackWithValue() public payable {
        // Send ETH to the guard
        (bool success,) = address(guard).call{value: 1 ether}("");
        assertFalse(success, "Fallback should not accept ETH");
    }

    function test_FallbackWithoutValue() public {
        // Call without value should succeed
        (bool success,) = address(guard).call("");
        assertTrue(success, "Fallback should accept calls without value");
    }
}
