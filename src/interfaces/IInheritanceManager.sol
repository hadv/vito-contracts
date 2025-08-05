// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./IBaseManager.sol";
import "./IInheritanceModule.sol";

/**
 * @title IInheritanceManager
 * @notice Interface for managing inheritance configurations across multiple Safe wallets
 * @dev Extends IBaseManager to follow the existing codebase patterns
 */
interface IInheritanceManager is IBaseManager {
    // Additional Events
    
    /**
     * @notice Emitted when a new inheritance module is deployed
     * @param safe Address of the Safe wallet
     * @param module Address of the deployed inheritance module
     * @param owner Address of the Safe owner
     */
    event InheritanceModuleDeployed(
        address indexed safe,
        address indexed module,
        address indexed owner
    );

    /**
     * @notice Emitted when an inheritance module is enabled for a Safe
     * @param safe Address of the Safe wallet
     * @param module Address of the inheritance module
     */
    event InheritanceModuleEnabled(
        address indexed safe,
        address indexed module
    );

    /**
     * @notice Emitted when an inheritance module is disabled for a Safe
     * @param safe Address of the Safe wallet
     * @param module Address of the inheritance module
     */
    event InheritanceModuleDisabled(
        address indexed safe,
        address indexed module
    );

    /**
     * @notice Emitted when global inheritance settings are updated
     * @param minInactivityPeriod Minimum inactivity period allowed
     * @param maxInactivityPeriod Maximum inactivity period allowed
     * @param defaultCooldownPeriod Default cooldown period for configuration changes
     */
    event GlobalSettingsUpdated(
        uint256 minInactivityPeriod,
        uint256 maxInactivityPeriod,
        uint256 defaultCooldownPeriod
    );

    // Additional Errors
    
    error ModuleAlreadyExists();
    error ModuleNotFound();
    error InvalidPeriodRange();
    error UnauthorizedOracle();
    error InvalidModuleAddress();

    // Core Management Functions
    
    /**
     * @notice Deploy and configure inheritance module for a Safe
     * @param safe Address of the Safe wallet
     * @param inactivityPeriod Time period of inactivity before inheritance can be claimed
     * @param cooldownPeriod Minimum time between configuration changes
     * @param requiresOracle Whether oracle verification is required
     * @param oracleAddress Address of the oracle (if required)
     * @return module Address of the deployed inheritance module
     */
    function deployInheritanceModule(
        address safe,
        uint256 inactivityPeriod,
        uint256 cooldownPeriod,
        bool requiresOracle,
        address oracleAddress
    ) external returns (address module);

    /**
     * @notice Enable inheritance module for a Safe
     * @param safe Address of the Safe wallet
     * @param module Address of the inheritance module
     */
    function enableInheritanceModule(
        address safe,
        address module
    ) external;

    /**
     * @notice Disable inheritance module for a Safe
     * @param safe Address of the Safe wallet
     * @param module Address of the inheritance module
     */
    function disableInheritanceModule(
        address safe,
        address module
    ) external;

    /**
     * @notice Batch add beneficiaries to multiple Safes
     * @param safes Array of Safe wallet addresses
     * @param beneficiaries Array of beneficiary addresses
     * @param shares Array of inheritance shares
     */
    function batchAddBeneficiaries(
        address[] calldata safes,
        address[] calldata beneficiaries,
        uint256[] calldata shares
    ) external;

    /**
     * @notice Batch execute inheritance for multiple beneficiaries
     * @param safes Array of Safe wallet addresses
     * @param beneficiaries Array of beneficiary addresses
     * @param assets Array of asset allocation arrays
     * @param oracleProofs Array of oracle proofs
     */
    function batchExecuteInheritance(
        address[] calldata safes,
        address[] calldata beneficiaries,
        IInheritanceModule.AssetAllocation[][] calldata assets,
        bytes[] calldata oracleProofs
    ) external;

    // Oracle Management
    
    /**
     * @notice Register a trusted oracle
     * @param oracle Address of the oracle
     * @param isActive Whether the oracle is active
     */
    function registerOracle(address oracle, bool isActive) external;

    /**
     * @notice Update global inheritance settings
     * @param minInactivityPeriod Minimum allowed inactivity period
     * @param maxInactivityPeriod Maximum allowed inactivity period
     * @param defaultCooldownPeriod Default cooldown period
     */
    function updateGlobalSettings(
        uint256 minInactivityPeriod,
        uint256 maxInactivityPeriod,
        uint256 defaultCooldownPeriod
    ) external;

    // View Functions
    
    /**
     * @notice Get inheritance module address for a Safe
     * @param safe Address of the Safe wallet
     * @return module Address of the inheritance module
     */
    function getInheritanceModule(address safe) 
        external 
        view 
        returns (address module);

    /**
     * @notice Check if an oracle is trusted
     * @param oracle Address of the oracle
     * @return isTrusted Whether the oracle is trusted
     */
    function isTrustedOracle(address oracle) 
        external 
        view 
        returns (bool isTrusted);

    /**
     * @notice Get global inheritance settings
     * @return minInactivityPeriod Minimum allowed inactivity period
     * @return maxInactivityPeriod Maximum allowed inactivity period
     * @return defaultCooldownPeriod Default cooldown period
     */
    function getGlobalSettings() 
        external 
        view 
        returns (
            uint256 minInactivityPeriod,
            uint256 maxInactivityPeriod,
            uint256 defaultCooldownPeriod
        );

    /**
     * @notice Get all Safes with inheritance configured
     * @return safes Array of Safe wallet addresses
     */
    function getAllInheritanceSafes() 
        external 
        view 
        returns (address[] memory safes);

    /**
     * @notice Get inheritance statistics
     * @return totalSafes Total number of Safes with inheritance
     * @return totalBeneficiaries Total number of beneficiaries across all Safes
     * @return totalExecutions Total number of inheritance executions
     */
    function getInheritanceStats() 
        external 
        view 
        returns (
            uint256 totalSafes,
            uint256 totalBeneficiaries,
            uint256 totalExecutions
        );
}
