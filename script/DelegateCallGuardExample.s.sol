// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Script.sol";
import "../src/SafeTxPool.sol";
import "@safe-global/safe-contracts/contracts/common/Enum.sol";

/**
 * @title DelegateCallGuardExample
 * @dev Example script demonstrating how to use the SafeTxPool delegate call guard functionality
 */
contract DelegateCallGuardExample is Script {
    SafeTxPool public pool;
    address public safe;
    address public targetContract;

    function setUp() public {
        // Deploy SafeTxPool
        pool = new SafeTxPool();
        
        // For this example, we'll use the deployer as the "Safe"
        safe = msg.sender;
        targetContract = address(0x1234567890123456789012345678901234567890);
    }

    function run() public {
        vm.startBroadcast();

        // Deploy the SafeTxPool
        pool = new SafeTxPool();
        
        console.log("SafeTxPool deployed at:", address(pool));
        console.log("Example Safe address:", safe);
        console.log("Target contract address:", targetContract);

        // Example 1: Check initial state (delegate calls disabled by default)
        console.log("\n=== Initial State ===");
        console.log("Delegate calls enabled:", pool.isDelegateCallEnabled(safe));
        console.log("Target allowed:", pool.isDelegateCallTargetAllowed(safe, targetContract));

        // Example 2: Enable delegate calls for the Safe
        console.log("\n=== Enabling Delegate Calls ===");
        pool.setDelegateCallEnabled(safe, true);
        console.log("Delegate calls enabled:", pool.isDelegateCallEnabled(safe));

        // Example 3: Add a specific target for delegate calls
        console.log("\n=== Adding Allowed Target ===");
        pool.addDelegateCallTarget(safe, targetContract);
        console.log("Target allowed:", pool.isDelegateCallTargetAllowed(safe, targetContract));

        // Example 4: Add target to address book (required for the guard to allow transactions)
        console.log("\n=== Adding to Address Book ===");
        pool.addAddressBookEntry(safe, targetContract, "Example Target Contract");
        
        // Get address book entries to verify
        SafeTxPool.AddressBookEntry[] memory entries = pool.getAddressBookEntries(safe);
        console.log("Address book entries count:", entries.length);
        if (entries.length > 0) {
            console.log("First entry address:", entries[0].walletAddress);
        }

        // Example 5: Simulate a delegate call check (this would normally be called by the Safe)
        console.log("\n=== Testing Delegate Call Check ===");
        try pool.checkTransaction(
            targetContract,
            0,
            "",
            Enum.Operation.DelegateCall,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            "",
            safe
        ) {
            console.log("Delegate call check passed!");
        } catch Error(string memory reason) {
            console.log("Delegate call check failed:", reason);
        }

        // Example 6: Test with unauthorized target
        address unauthorizedTarget = address(0x9999999999999999999999999999999999999999);
        console.log("\n=== Testing Unauthorized Target ===");
        console.log("Unauthorized target:", unauthorizedTarget);
        
        // Add to address book first
        pool.addAddressBookEntry(safe, unauthorizedTarget, "Unauthorized Target");
        
        try pool.checkTransaction(
            unauthorizedTarget,
            0,
            "",
            Enum.Operation.DelegateCall,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            "",
            safe
        ) {
            console.log("Unauthorized delegate call unexpectedly passed!");
        } catch {
            console.log("Unauthorized delegate call correctly failed: DelegateCallTargetNotAllowed");
        }

        // Example 7: Disable delegate calls
        console.log("\n=== Disabling Delegate Calls ===");
        pool.setDelegateCallEnabled(safe, false);
        console.log("Delegate calls enabled:", pool.isDelegateCallEnabled(safe));

        try pool.checkTransaction(
            targetContract,
            0,
            "",
            Enum.Operation.DelegateCall,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            "",
            safe
        ) {
            console.log("Delegate call unexpectedly passed when disabled!");
        } catch {
            console.log("Delegate call correctly failed when disabled: DelegateCallDisabled");
        }

        // Example 8: Test normal call (should still work)
        console.log("\n=== Testing Normal Call ===");
        try pool.checkTransaction(
            targetContract,
            0,
            "",
            Enum.Operation.Call,
            0,
            0,
            0,
            address(0),
            payable(address(0)),
            "",
            safe
        ) {
            console.log("Normal call check passed!");
        } catch Error(string memory reason) {
            console.log("Normal call check failed:", reason);
        }

        vm.stopBroadcast();

        console.log("\n=== Example Complete ===");
        console.log("The SafeTxPool delegate call guard is now configured and tested!");
    }
}
