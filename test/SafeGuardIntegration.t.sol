// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {SafeGuard} from "../src/SafeGuard.sol";
import {Enum} from "@safe-global/safe-contracts/contracts/common/Enum.sol";
import {Safe} from "@safe-global/safe-contracts/contracts/Safe.sol";
import {SafeProxyFactory} from "@safe-global/safe-contracts/contracts/proxies/SafeProxyFactory.sol";
import {SafeProxy} from "@safe-global/safe-contracts/contracts/proxies/SafeProxy.sol";
import {GuardManager} from "@safe-global/safe-contracts/contracts/base/GuardManager.sol";
import {MockTarget} from "./mocks/MockTarget.sol";

contract SafeGuardIntegrationTest is Test {
    SafeGuard public guard;
    Safe public safe;
    SafeProxyFactory public factory;
    MockTarget public mockTarget;
    address public owner;
    address public unauthorizedTarget;
    uint256 public ownerKey;

    function setUp() public {
        // Setup owner
        ownerKey = 0xA11CE;
        owner = vm.addr(ownerKey);
        unauthorizedTarget = makeAddr("unauthorizedTarget");

        // Deploy mock target
        mockTarget = new MockTarget();

        // Deploy Safe factory
        factory = new SafeProxyFactory();

        // Deploy guard with mock target as allowed target
        address[] memory targets = new address[](1);
        targets[0] = address(mockTarget);
        guard = new SafeGuard(targets);

        // Setup Safe wallet with single owner
        address[] memory owners = new address[](1);
        owners[0] = owner;

        // Deploy Safe with 1/1 threshold and guard
        bytes memory safeSetupData = abi.encodeWithSelector(
            Safe.setup.selector,
            owners, // owners
            1, // threshold
            address(0), // to
            "", // data
            address(guard), // fallbackHandler
            address(0), // paymentToken
            0, // payment
            payable(address(0)) // paymentReceiver
        );

        SafeProxy proxy = factory.createProxyWithNonce(address(new Safe()), safeSetupData, 0);

        safe = Safe(payable(address(proxy)));

        // Fund the Safe with some ETH
        vm.deal(address(safe), 1 ether);

        // Set guard on Safe through a transaction
        bytes memory setGuardData = abi.encodeWithSelector(GuardManager.setGuard.selector, address(guard));
        execTransaction(address(safe), 0, setGuardData, Enum.Operation.Call);
    }

    function getTransactionHash(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        uint256 nonce
    ) internal view returns (bytes32) {
        return keccak256(
            abi.encodePacked(
                bytes1(0x19),
                bytes1(0x01),
                safe.domainSeparator(),
                keccak256(
                    abi.encode(
                        keccak256(
                            "SafeTx(address to,uint256 value,bytes data,uint8 operation,uint256 safeTxGas,uint256 baseGas,uint256 gasPrice,address gasToken,address refundReceiver,uint256 nonce)"
                        ),
                        to,
                        value,
                        keccak256(data),
                        operation,
                        safeTxGas,
                        baseGas,
                        gasPrice,
                        gasToken,
                        refundReceiver,
                        nonce
                    )
                )
            )
        );
    }

    function getSignature(bytes32 txHash, uint256 key) internal pure returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, txHash);
        return abi.encodePacked(r, s, v);
    }

    function execTransaction(address to, uint256 value, bytes memory data, Enum.Operation operation)
        internal
        returns (bool)
    {
        // Get transaction hash
        bytes32 txHash = getTransactionHash(
            to,
            value,
            data,
            operation,
            100000, // safeTxGas
            0, // baseGas
            0, // gasPrice
            address(0),
            payable(address(0)),
            safe.nonce()
        );

        // Get signature from owner
        bytes memory signature = getSignature(txHash, ownerKey);

        // Execute transaction
        return safe.execTransaction(
            to,
            value,
            data,
            operation,
            100000, // safeTxGas
            0, // baseGas
            0, // gasPrice
            address(0),
            payable(address(0)),
            signature
        );
    }

    /// forge-config: default.allow_internal_expect_revert = true
    function test_SafeDelegateCallWithGuard() public {
        // Use the deployed mockTarget contract
        bytes memory callData = abi.encodeWithSelector(MockTarget.delegateCallMe.selector);

        // Test delegate call to authorized target
        bool success = execTransaction(address(mockTarget), 0, callData, Enum.Operation.DelegateCall);
        assertTrue(success, "Delegate call to authorized target should succeed");
    }

    function test_SafeRegularCallWithGuard() public {
        // Regular call should succeed
        bool success = execTransaction(address(mockTarget), 0, "", Enum.Operation.Call);
        assertTrue(success, "Regular call should succeed");
    }

    function test_GuardCanBeRemovedFromSafe() public {
        // Remove guard from Safe through a transaction
        bytes memory setGuardData = abi.encodeWithSelector(GuardManager.setGuard.selector, address(0));
        bool success = execTransaction(address(safe), 0, setGuardData, Enum.Operation.Call);
        assertTrue(success, "Guard should be removed successfully");

        // Delegate call should now succeed without guard
        bytes memory callData = abi.encodeWithSelector(MockTarget.delegateCallMe.selector);
        success = execTransaction(address(mockTarget), 0, callData, Enum.Operation.DelegateCall);
        assertTrue(success, "Delegate call should succeed after guard is removed");
    }

    function test_GuardTarget() public view {
        // Check that the allowed target is set correctly
        assertTrue(guard.allowedTargets(address(mockTarget)), "Mock target should be allowed");
        assertFalse(guard.allowedTargets(unauthorizedTarget), "Unauthorized target should not be allowed");
    }

    function test_OnlyOwnerCanManageTargets() public {
        address newTarget = makeAddr("newTarget");

        // Try to add target from unauthorized address
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert(abi.encodeWithSelector(SafeGuard.OnlyOwner.selector));
        guard.addAllowedTarget(newTarget);

        // Try to remove target from unauthorized address
        vm.prank(makeAddr("unauthorized"));
        vm.expectRevert(abi.encodeWithSelector(SafeGuard.OnlyOwner.selector));
        guard.removeAllowedTarget(address(mockTarget));
    }
}
