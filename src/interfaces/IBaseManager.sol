// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title IBaseManager
 * @notice Base interface for all SafeTxPool manager contracts
 */
interface IBaseManager {
    // Events

    // Errors
    error NotSafeWallet();
    error InvalidAddress();

    /**
     * @notice Get the registry address that can call this manager
     * @return registry The registry contract address
     */
    function registry() external view returns (address);

    /**
     * @notice Update the registry address
     * @param _newRegistry The new registry contract address
     */
    function updateRegistry(address _newRegistry) external;
}
