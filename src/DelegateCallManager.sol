// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./interfaces/IDelegateCallManager.sol";
import "./base/BaseManager.sol";

/**
 * @title DelegateCallManager
 * @notice Manages delegate call permissions for Safe wallets
 */
contract DelegateCallManager is BaseManager, IDelegateCallManager {
    // Delegate call control mappings
    mapping(address => bool) private delegateCallEnabled;
    mapping(address => mapping(address => bool)) private allowedDelegateCallTargets;
    mapping(address => bool) private hasTargetRestrictions;

    // Arrays to track allowed targets for efficient retrieval
    mapping(address => address[]) private delegateCallTargetsList;
    mapping(address => mapping(address => uint256)) private delegateCallTargetIndex;



    /**
     * @notice Enable or disable delegate calls for a Safe
     * @param safe The Safe wallet address
     * @param enabled Whether delegate calls should be enabled
     */
    function setDelegateCallEnabled(address safe, bool enabled) external onlySafeOrRegistry(safe) {
        delegateCallEnabled[safe] = enabled;
        emit DelegateCallToggled(safe, enabled);
    }

    /**
     * @notice Add an allowed delegate call target for a Safe
     * @param safe The Safe wallet address
     * @param target The target address to allow for delegate calls
     */
    function addDelegateCallTarget(address safe, address target) external onlySafeOrRegistry(safe) {
        // Validate target address
        if (target == address(0)) revert InvalidAddress();

        // Check if target is already allowed to avoid duplicates
        if (allowedDelegateCallTargets[safe][target]) {
            return; // Target already exists, no need to add again
        }

        allowedDelegateCallTargets[safe][target] = true;
        hasTargetRestrictions[safe] = true;

        // Add to the targets list for efficient retrieval
        delegateCallTargetsList[safe].push(target);
        delegateCallTargetIndex[safe][target] = delegateCallTargetsList[safe].length - 1;

        emit DelegateCallTargetAdded(safe, target);
    }

    /**
     * @notice Remove an allowed delegate call target for a Safe
     * @param safe The Safe wallet address
     * @param target The target address to remove from allowed delegate calls
     */
    function removeDelegateCallTarget(address safe, address target) external onlySafeOrRegistry(safe) {
        // Check if target exists
        if (!allowedDelegateCallTargets[safe][target]) {
            return; // Target doesn't exist, nothing to remove
        }

        allowedDelegateCallTargets[safe][target] = false;

        // Remove from the targets list
        uint256 indexToRemove = delegateCallTargetIndex[safe][target];
        uint256 lastIndex = delegateCallTargetsList[safe].length - 1;

        if (indexToRemove != lastIndex) {
            // Move the last element to the position of the element to remove
            address lastTarget = delegateCallTargetsList[safe][lastIndex];
            delegateCallTargetsList[safe][indexToRemove] = lastTarget;
            delegateCallTargetIndex[safe][lastTarget] = indexToRemove;
        }

        // Remove the last element
        delegateCallTargetsList[safe].pop();
        delete delegateCallTargetIndex[safe][target];

        emit DelegateCallTargetRemoved(safe, target);
    }

    /**
     * @notice Check if delegate calls are enabled for a Safe
     * @param safe The Safe wallet address
     * @return enabled Whether delegate calls are enabled
     */
    function isDelegateCallEnabled(address safe) external view returns (bool) {
        return delegateCallEnabled[safe];
    }

    /**
     * @notice Check if a target is allowed for delegate calls from a Safe
     * @param safe The Safe wallet address
     * @param target The target address to check
     * @return allowed Whether the target is allowed for delegate calls
     */
    function isDelegateCallTargetAllowed(address safe, address target) external view returns (bool) {
        return allowedDelegateCallTargets[safe][target];
    }

    /**
     * @notice Get all allowed delegate call targets for a Safe
     * @param safe The Safe wallet address
     * @return targets Array of allowed target addresses
     */
    function getDelegateCallTargets(address safe) external view returns (address[] memory) {
        return delegateCallTargetsList[safe];
    }

    /**
     * @notice Get the number of allowed delegate call targets for a Safe
     * @param safe The Safe wallet address
     * @return count Number of allowed targets
     */
    function getDelegateCallTargetsCount(address safe) external view returns (uint256) {
        return delegateCallTargetsList[safe].length;
    }

    /**
     * @notice Check if a Safe has any delegate call target restrictions
     * @param safe The Safe wallet address
     * @return hasRestrictions Whether the Safe has any specific target restrictions
     */
    function hasDelegateCallTargetRestrictions(address safe) external view returns (bool) {
        return hasTargetRestrictions[safe];
    }
}
