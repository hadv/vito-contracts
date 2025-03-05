// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {SafeGuard} from "../src/SafeGuard.sol";
import {Enum} from "@safe-global/safe-contracts/contracts/common/Enum.sol";

contract SafeGuardTest is Test {
    SafeGuard public guard;
    address public constant ADDRESS_ZERO = address(0);
    address public constant ADDRESS_ONE = address(1);

    // Error selectors
    bytes4 constant CALL_RESTRICTED_SELECTOR = bytes4(keccak256("CallRestricted()"));
    bytes4 constant ONLY_OWNER_SELECTOR = bytes4(keccak256("OnlyOwner()"));

    function setUp() public {
        address[] memory targets = new address[](1);
        targets[0] = ADDRESS_ONE;
        guard = new SafeGuard(targets);
    }

    function test_FallbackWithoutValue() public {
        // Send a transaction with no value and random data
        (bool success,) = address(guard).call("0xbaddad");
        assertTrue(success, "Fallback should not revert without value");
    }

    function test_FallbackWithValue() public {
        // Send a transaction with value and random data
        (bool success,) = address(guard).call{value: 1}("0xbaddad");
        assertFalse(success, "Fallback should revert with value");
    }

    function test_CheckTransactionDelegateCall() public {
        // Prepare transaction data
        bytes memory data = abi.encodeWithSelector(bytes4(0), ADDRESS_ZERO);

        // Attempt delegate call to unauthorized target should revert
        vm.expectRevert(CALL_RESTRICTED_SELECTOR);
        guard.checkTransaction(
            ADDRESS_ZERO, // to
            0, // value
            data, // data
            Enum.Operation.DelegateCall, // operation
            0, // safeTxGas
            0, // baseGas
            0, // gasPrice
            ADDRESS_ZERO, // gasToken
            payable(ADDRESS_ZERO), // refundReceiver
            "", // signatures
            address(this) // msgSender
        );

        // Delegate call to authorized target should not revert
        guard.checkTransaction(
            ADDRESS_ONE, // to
            0, // value
            data, // data
            Enum.Operation.DelegateCall, // operation
            0, // safeTxGas
            0, // baseGas
            0, // gasPrice
            ADDRESS_ZERO, // gasToken
            payable(ADDRESS_ZERO), // refundReceiver
            "", // signatures
            address(this) // msgSender
        );
    }

    function test_CheckTransactionNormalCall() public view {
        // Prepare transaction data
        bytes memory data = abi.encodeWithSelector(bytes4(0), ADDRESS_ZERO);

        // Normal call should not revert
        guard.checkTransaction(
            ADDRESS_ZERO, // to
            0, // value
            data, // data
            Enum.Operation.Call, // operation
            0, // safeTxGas
            0, // baseGas
            0, // gasPrice
            ADDRESS_ZERO, // gasToken
            payable(ADDRESS_ZERO), // refundReceiver
            "", // signatures
            address(this) // msgSender
        );
    }

    function test_AllowedTarget() public view {
        // Check that the allowed target is set correctly
        assertTrue(guard.allowedTargets(ADDRESS_ONE), "ADDRESS_ONE should be allowed");
        assertFalse(guard.allowedTargets(ADDRESS_ZERO), "ADDRESS_ZERO should not be allowed");
    }

    function test_AddAllowedTarget() public {
        address newTarget = makeAddr("newTarget");

        // Add new target
        guard.addAllowedTarget(newTarget);

        // Verify target was added
        assertTrue(guard.allowedTargets(newTarget), "New target should be allowed");
    }

    function test_RemoveAllowedTarget() public {
        // Remove ADDRESS_ONE from allowed targets
        guard.removeAllowedTarget(ADDRESS_ONE);

        // Verify target was removed
        assertFalse(guard.allowedTargets(ADDRESS_ONE), "Target should be removed");

        // Attempt delegate call to removed target should revert
        bytes memory data = abi.encodeWithSelector(bytes4(0), ADDRESS_ZERO);
        vm.expectRevert(CALL_RESTRICTED_SELECTOR);
        guard.checkTransaction(
            ADDRESS_ONE, // to
            0, // value
            data, // data
            Enum.Operation.DelegateCall, // operation
            0, // safeTxGas
            0, // baseGas
            0, // gasPrice
            ADDRESS_ZERO, // gasToken
            payable(ADDRESS_ZERO), // refundReceiver
            "", // signatures
            address(this) // msgSender
        );
    }
}
