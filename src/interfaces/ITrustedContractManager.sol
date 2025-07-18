// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./IBaseManager.sol";

/**
 * @title ITrustedContractManager
 * @notice Interface for managing trusted contracts for Safe wallets
 */
interface ITrustedContractManager is IBaseManager {
    // Events
    event TrustedContractAdded(address indexed safe, address indexed contractAddress);
    event TrustedContractRemoved(address indexed safe, address indexed contractAddress);

    // Errors (inherited from IBaseManager: InvalidAddress, NotSafeWallet)

    /**
     * @notice Add a trusted contract for a Safe
     * @param safe The Safe wallet address
     * @param contractAddress The contract address to trust
     */
    function addTrustedContract(address safe, address contractAddress) external;

    /**
     * @notice Remove a trusted contract for a Safe
     * @param safe The Safe wallet address
     * @param contractAddress The contract address to remove from trusted list
     */
    function removeTrustedContract(address safe, address contractAddress) external;

    /**
     * @notice Check if a contract is trusted by a Safe
     * @param safe The Safe wallet address
     * @param contractAddress The contract address to check
     * @return isTrusted Whether the contract is trusted
     */
    function isTrustedContract(address safe, address contractAddress) external view returns (bool);
}
