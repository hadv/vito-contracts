// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./IBaseManager.sol";

/**
 * @title IDelegateCallManager
 * @notice Interface for managing delegate call permissions for Safe wallets
 */
interface IDelegateCallManager is IBaseManager {
    // Events
    event DelegateCallToggled(address indexed safe, bool enabled);
    event DelegateCallTargetAdded(address indexed safe, address indexed target);
    event DelegateCallTargetRemoved(address indexed safe, address indexed target);

    // Errors (inherited from IBaseManager: InvalidAddress, NotSafeWallet)
    error DelegateCallDisabled();
    error DelegateCallTargetNotAllowed();

    /**
     * @notice Enable or disable delegate calls for a Safe
     * @param safe The Safe wallet address
     * @param enabled Whether delegate calls should be enabled
     */
    function setDelegateCallEnabled(address safe, bool enabled) external;

    /**
     * @notice Add an allowed delegate call target for a Safe
     * @param safe The Safe wallet address
     * @param target The target address to allow for delegate calls
     */
    function addDelegateCallTarget(address safe, address target) external;

    /**
     * @notice Remove an allowed delegate call target for a Safe
     * @param safe The Safe wallet address
     * @param target The target address to remove from allowed delegate calls
     */
    function removeDelegateCallTarget(address safe, address target) external;

    /**
     * @notice Check if delegate calls are enabled for a Safe
     * @param safe The Safe wallet address
     * @return enabled Whether delegate calls are enabled
     */
    function isDelegateCallEnabled(address safe) external view returns (bool);

    /**
     * @notice Check if a target is allowed for delegate calls from a Safe
     * @param safe The Safe wallet address
     * @param target The target address to check
     * @return allowed Whether the target is allowed for delegate calls
     */
    function isDelegateCallTargetAllowed(address safe, address target) external view returns (bool);

    /**
     * @notice Get all allowed delegate call targets for a Safe
     * @param safe The Safe wallet address
     * @return targets Array of allowed target addresses
     */
    function getDelegateCallTargets(address safe) external view returns (address[] memory);

    /**
     * @notice Get the number of allowed delegate call targets for a Safe
     * @param safe The Safe wallet address
     * @return count Number of allowed targets
     */
    function getDelegateCallTargetsCount(address safe) external view returns (uint256);

    /**
     * @notice Check if a Safe has any delegate call target restrictions
     * @param safe The Safe wallet address
     * @return hasRestrictions Whether the Safe has any specific target restrictions
     */
    function hasDelegateCallTargetRestrictions(address safe) external view returns (bool);
}
