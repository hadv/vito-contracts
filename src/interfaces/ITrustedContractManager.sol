// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./IBaseManager.sol";

/**
 * @title ITrustedContractManager
 * @notice Interface for managing trusted contracts for Safe wallets
 */
interface ITrustedContractManager is IBaseManager {
    // Simple struct for trusted contract entries
    struct TrustedContractEntry {
        bytes32 name; // Limited to 32 bytes
        address contractAddress; // Mandatory
    }

    // Events
    event TrustedContractAdded(address indexed safe, address indexed contractAddress, bytes32 name);
    event TrustedContractRemoved(address indexed safe, address indexed contractAddress);

    // Errors (inherited from IBaseManager: InvalidAddress, NotSafeWallet)

    /**
     * @notice Add a trusted contract for a Safe
     * @param safe The Safe wallet address
     * @param contractAddress The contract address to trust
     * @param name Name associated with the contract (32 bytes)
     */
    function addTrustedContract(address safe, address contractAddress, bytes32 name) external;

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

    /**
     * @notice Get all trusted contract entries for a Safe
     * @param safe The Safe wallet address
     * @return entries Array of trusted contract entries
     */
    function getTrustedContracts(address safe) external view returns (TrustedContractEntry[] memory);
}
