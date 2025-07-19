// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./interfaces/ITrustedContractManager.sol";
import "./base/BaseManager.sol";

/**
 * @title TrustedContractManager
 * @notice Manages trusted contracts for Safe wallets
 */
contract TrustedContractManager is BaseManager, ITrustedContractManager {
    // Mapping from Safe address to its array of trusted contract entries
    mapping(address => TrustedContractEntry[]) private trustedContracts;

    /**
     * @notice Add a trusted contract for a Safe
     * @param safe The Safe wallet address
     * @param contractAddress The contract address to trust
     * @param name Name associated with the contract (32 bytes)
     */
    function addTrustedContract(address safe, address contractAddress, bytes32 name)
        external
        onlySafeOrRegistry(safe)
    {
        // Validate contract address
        if (contractAddress == address(0)) revert InvalidAddress();

        // Check if entry already exists
        int256 existingIndex = findTrustedContract(safe, contractAddress);
        if (existingIndex >= 0) {
            // Update existing entry
            uint256 index = uint256(existingIndex);
            trustedContracts[safe][index].name = name;
        } else {
            // Add new entry
            trustedContracts[safe].push(TrustedContractEntry({name: name, contractAddress: contractAddress}));
        }

        emit TrustedContractAdded(safe, contractAddress, name);
    }

    /**
     * @notice Remove a trusted contract for a Safe
     * @param safe The Safe wallet address
     * @param contractAddress The contract address to remove from trusted list
     */
    function removeTrustedContract(address safe, address contractAddress) external onlySafeOrRegistry(safe) {
        int256 index = findTrustedContract(safe, contractAddress);

        if (index < 0) revert InvalidAddress(); // Contract not found

        // Get the array
        TrustedContractEntry[] storage entries = trustedContracts[safe];
        uint256 entryIndex = uint256(index);

        // Move the last element to the position of the element to delete (if it's not the last)
        if (entryIndex < entries.length - 1) {
            entries[entryIndex] = entries[entries.length - 1];
        }

        // Remove the last element
        entries.pop();

        emit TrustedContractRemoved(safe, contractAddress);
    }

    /**
     * @notice Check if a contract is trusted by a Safe
     * @param safe The Safe wallet address
     * @param contractAddress The contract address to check
     * @return isTrusted Whether the contract is trusted
     */
    function isTrustedContract(address safe, address contractAddress) external view returns (bool) {
        return findTrustedContract(safe, contractAddress) >= 0;
    }

    /**
     * @notice Get all trusted contract entries for a Safe
     * @param safe The Safe wallet address
     * @return entries Array of trusted contract entries
     */
    function getTrustedContracts(address safe) external view returns (TrustedContractEntry[] memory) {
        return trustedContracts[safe];
    }

    /**
     * @notice Find a trusted contract's index in the array
     * @param safe The Safe wallet address
     * @param contractAddress The contract address to find
     * @return index Index of the entry, or -1 if not found
     */
    function findTrustedContract(address safe, address contractAddress) public view returns (int256) {
        TrustedContractEntry[] storage entries = trustedContracts[safe];

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].contractAddress == contractAddress) {
                return int256(i);
            }
        }

        return -1; // Not found
    }
}
