// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./interfaces/ITrustedContractManager.sol";

/**
 * @title TrustedContractManager
 * @notice Manages trusted contracts for Safe wallets
 */
contract TrustedContractManager is ITrustedContractManager {
    // Contract whitelist for trusted contracts (like token contracts)
    mapping(address => mapping(address => bool)) private trustedContracts;

    // No access control - the registry will handle validation
    // This allows the registry to call these functions after validating the caller

    /**
     * @notice Add a trusted contract for a Safe
     * @param safe The Safe wallet address
     * @param contractAddress The contract address to trust
     */
    function addTrustedContract(address safe, address contractAddress) external {
        // Validate contract address
        if (contractAddress == address(0)) revert InvalidAddress();

        trustedContracts[safe][contractAddress] = true;
        emit TrustedContractAdded(safe, contractAddress);
    }

    /**
     * @notice Remove a trusted contract for a Safe
     * @param safe The Safe wallet address
     * @param contractAddress The contract address to remove from trusted list
     */
    function removeTrustedContract(address safe, address contractAddress) external {
        trustedContracts[safe][contractAddress] = false;
        emit TrustedContractRemoved(safe, contractAddress);
    }

    /**
     * @notice Check if a contract is trusted by a Safe
     * @param safe The Safe wallet address
     * @param contractAddress The contract address to check
     * @return isTrusted Whether the contract is trusted
     */
    function isTrustedContract(address safe, address contractAddress) external view returns (bool) {
        return trustedContracts[safe][contractAddress];
    }
}
