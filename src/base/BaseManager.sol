// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../interfaces/IBaseManager.sol";

/**
 * @title BaseManager
 * @notice Base contract for all SafeTxPool manager contracts
 * @dev Provides common access control functionality for manager contracts
 */
abstract contract BaseManager is IBaseManager {
    // Registry contract that can call this manager
    address public registry;

    /**
     * @notice Constructor to set the registry address
     * @param _registry The registry contract address that can call this manager
     */
    constructor(address _registry) {
        registry = _registry; // Allow zero address for deployment flexibility
    }

    /**
     * @notice Update the registry address (only callable by current registry or if registry is zero)
     * @param _newRegistry The new registry contract address
     */
    function updateRegistry(address _newRegistry) external {
        if (registry != address(0) && msg.sender != registry) revert NotSafeWallet();
        if (_newRegistry == address(0)) revert InvalidAddress();
        registry = _newRegistry;
    }

    /**
     * @notice Modifier to restrict access to Safe wallet or Registry only
     * @param safe The Safe wallet address that should be validated
     */
    modifier onlySafeOrRegistry(address safe) {
        if (msg.sender != safe && msg.sender != registry) revert NotSafeWallet();
        _;
    }
}
