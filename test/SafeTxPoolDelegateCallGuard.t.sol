// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/SafeTxPool.sol";
import "@safe-global/safe-contracts/contracts/common/Enum.sol";

contract MockSafeForDelegateCall {
    SafeTxPool public guard;

    constructor(SafeTxPool _guard) {
        guard = _guard;
    }

    function executeTransaction(
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation
    ) external {
        // Call checkTransaction on the guard
        guard.checkTransaction(
            to,
            value,
            data,
            operation,
            0, // safeTxGas
            0, // baseGas
            0, // gasPrice
            address(0), // gasToken
            payable(address(0)), // refundReceiver
            bytes(""), // signatures
            msg.sender // msgSender
        );

        // If the guard doesn't revert, the transaction would execute
    }

    function setDelegateCallEnabled(bool enabled) external {
        guard.setDelegateCallEnabled(address(this), enabled);
    }

    function addDelegateCallTarget(address target) external {
        guard.addDelegateCallTarget(address(this), target);
    }

    function removeDelegateCallTarget(address target) external {
        guard.removeDelegateCallTarget(address(this), target);
    }

    function addAddressBookEntry(address walletAddress, bytes32 name) external {
        guard.addAddressBookEntry(address(this), walletAddress, name);
    }
}

contract SafeTxPoolDelegateCallGuardTest is Test {
    SafeTxPool public pool;
    MockSafeForDelegateCall public mockSafe;
    address public targetContract;
    address public unauthorizedTarget;

    function setUp() public {
        // Deploy SafeTxPool
        pool = new SafeTxPool();

        // Deploy mock Safe
        mockSafe = new MockSafeForDelegateCall(pool);

        // Setup target contracts
        targetContract = address(0x1234);
        unauthorizedTarget = address(0x5678);
    }

    function testDelegateCallDisabledByDefault() public {
        // Delegate calls should be disabled by default
        assertFalse(pool.isDelegateCallEnabled(address(mockSafe)));

        // Add target to address book first (required for non-delegate calls)
        mockSafe.addAddressBookEntry(targetContract, "Target Contract");

        // Attempt delegate call - should revert because delegate calls are disabled
        vm.expectRevert(abi.encodeWithSelector(SafeTxPool.DelegateCallDisabled.selector));
        mockSafe.executeTransaction(
            targetContract,
            0,
            bytes(""),
            Enum.Operation.DelegateCall
        );
    }

    function testEnableDelegateCallAllowsAllTargets() public {
        // Add target to address book first
        mockSafe.addAddressBookEntry(targetContract, "Target Contract");

        // Enable delegate calls
        mockSafe.setDelegateCallEnabled(true);
        assertTrue(pool.isDelegateCallEnabled(address(mockSafe)));

        // Delegate call should now succeed (no specific target restrictions)
        mockSafe.executeTransaction(
            targetContract,
            0,
            bytes(""),
            Enum.Operation.DelegateCall
        );
    }

    function testDelegateCallWithTargetRestrictions() public {
        // Add targets to address book first
        mockSafe.addAddressBookEntry(targetContract, "Target Contract");
        mockSafe.addAddressBookEntry(unauthorizedTarget, "Unauthorized Target");

        // Enable delegate calls
        mockSafe.setDelegateCallEnabled(true);

        // Add specific target restriction
        mockSafe.addDelegateCallTarget(targetContract);

        // Delegate call to allowed target should succeed
        mockSafe.executeTransaction(
            targetContract,
            0,
            bytes(""),
            Enum.Operation.DelegateCall
        );

        // Delegate call to unauthorized target should fail
        vm.expectRevert(abi.encodeWithSelector(SafeTxPool.DelegateCallTargetNotAllowed.selector));
        mockSafe.executeTransaction(
            unauthorizedTarget,
            0,
            bytes(""),
            Enum.Operation.DelegateCall
        );
    }

    function testNormalCallsStillWork() public {
        // Add target to address book
        mockSafe.addAddressBookEntry(targetContract, "Target Contract");

        // Normal calls should work regardless of delegate call settings
        mockSafe.executeTransaction(
            targetContract,
            0,
            bytes(""),
            Enum.Operation.Call
        );

        // Enable delegate calls and add restrictions
        mockSafe.setDelegateCallEnabled(true);
        mockSafe.addDelegateCallTarget(targetContract);

        // Normal calls should still work
        mockSafe.executeTransaction(
            targetContract,
            0,
            bytes(""),
            Enum.Operation.Call
        );
    }

    function testSelfCallsAlwaysAllowed() public {
        // Self calls should always be allowed regardless of delegate call settings
        mockSafe.executeTransaction(
            address(mockSafe),
            0,
            bytes(""),
            Enum.Operation.DelegateCall
        );

        // Even with delegate calls disabled
        mockSafe.setDelegateCallEnabled(false);
        mockSafe.executeTransaction(
            address(mockSafe),
            0,
            bytes(""),
            Enum.Operation.DelegateCall
        );
    }

    function testGuardContractCallsAlwaysAllowed() public {
        // Calls to the guard contract should always be allowed
        mockSafe.executeTransaction(
            address(pool),
            0,
            bytes(""),
            Enum.Operation.DelegateCall
        );

        // Even with delegate calls disabled
        mockSafe.setDelegateCallEnabled(false);
        mockSafe.executeTransaction(
            address(pool),
            0,
            bytes(""),
            Enum.Operation.DelegateCall
        );
    }

    function testOnlyOwnerCanModifySettings() public {
        // Only the Safe itself should be able to modify its settings
        vm.expectRevert(abi.encodeWithSelector(SafeTxPool.NotSafeWallet.selector));
        pool.setDelegateCallEnabled(address(mockSafe), true);

        vm.expectRevert(abi.encodeWithSelector(SafeTxPool.NotSafeWallet.selector));
        pool.addDelegateCallTarget(address(mockSafe), targetContract);

        vm.expectRevert(abi.encodeWithSelector(SafeTxPool.NotSafeWallet.selector));
        pool.removeDelegateCallTarget(address(mockSafe), targetContract);
    }

    function testDelegateCallEvents() public {
        // Test DelegateCallToggled event
        vm.expectEmit(true, false, false, true);
        emit SafeTxPool.DelegateCallToggled(address(mockSafe), true);
        mockSafe.setDelegateCallEnabled(true);

        // Test DelegateCallTargetAdded event
        vm.expectEmit(true, true, false, false);
        emit SafeTxPool.DelegateCallTargetAdded(address(mockSafe), targetContract);
        mockSafe.addDelegateCallTarget(targetContract);

        // Test DelegateCallTargetRemoved event
        vm.expectEmit(true, true, false, false);
        emit SafeTxPool.DelegateCallTargetRemoved(address(mockSafe), targetContract);
        mockSafe.removeDelegateCallTarget(targetContract);
    }

    function testGetterFunctions() public {
        // Test initial state
        assertFalse(pool.isDelegateCallEnabled(address(mockSafe)));
        assertFalse(pool.isDelegateCallTargetAllowed(address(mockSafe), targetContract));

        // Enable delegate calls and add target
        mockSafe.setDelegateCallEnabled(true);
        mockSafe.addDelegateCallTarget(targetContract);

        // Test updated state
        assertTrue(pool.isDelegateCallEnabled(address(mockSafe)));
        assertTrue(pool.isDelegateCallTargetAllowed(address(mockSafe), targetContract));
        assertFalse(pool.isDelegateCallTargetAllowed(address(mockSafe), unauthorizedTarget));
    }
}
