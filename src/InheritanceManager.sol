// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./base/BaseManager.sol";
import "./interfaces/IInheritanceManager.sol";
import "./interfaces/IInheritanceModule.sol";
import "./InheritanceModule.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// Safe interface for module management
interface ISafe {
    function enableModule(address module) external;
    function disableModule(address prevModule, address module) external;
    function isModuleEnabled(address module) external view returns (bool);
    function getModulesPaginated(address start, uint256 pageSize)
        external
        view
        returns (address[] memory array, address next);
    function isOwner(address owner) external view returns (bool);
}

/**
 * @title InheritanceManager
 * @notice Manager contract for Safe wallet inheritance modules
 * @dev Follows the existing codebase patterns and extends BaseManager
 */
contract InheritanceManager is BaseManager, IInheritanceManager, Ownable {
    using Clones for address;

    // Template contract for cloning inheritance modules
    address public immutable inheritanceModuleTemplate;

    // Storage
    mapping(address => address) public safeToModule;
    mapping(address => bool) public trustedOracles;
    address[] public inheritanceSafes;

    // Global settings
    uint256 public minInactivityPeriod = 30 days;
    uint256 public maxInactivityPeriod = 10 * 365 days;
    uint256 public defaultCooldownPeriod = 7 days;

    // Statistics
    uint256 public totalBeneficiaries;
    uint256 public totalExecutions;

    modifier onlyTrustedOracle() {
        require(trustedOracles[msg.sender], "Not a trusted oracle");
        _;
    }

    constructor(address _inheritanceModuleTemplate) {
        inheritanceModuleTemplate = _inheritanceModuleTemplate;
    }

    /**
     * @notice Deploy and configure inheritance module for a Safe
     */
    function deployInheritanceModule(
        address safe,
        uint256 inactivityPeriod,
        uint256 cooldownPeriod,
        bool requiresOracle,
        address oracleAddress
    ) external onlySafeOrRegistry(safe) returns (address module) {
        if (safeToModule[safe] != address(0)) revert ModuleAlreadyExists();

        // Validate parameters
        if (inactivityPeriod < minInactivityPeriod || inactivityPeriod > maxInactivityPeriod) {
            revert InvalidPeriodRange();
        }
        if (requiresOracle && !trustedOracles[oracleAddress]) {
            revert UnauthorizedOracle();
        }

        // Clone the template
        module = inheritanceModuleTemplate.clone();

        // Store mapping
        safeToModule[safe] = module;
        inheritanceSafes.push(safe);

        // Configure the module
        InheritanceModule(module).configureInheritance(
            safe, inactivityPeriod, cooldownPeriod, requiresOracle, oracleAddress
        );

        emit InheritanceModuleDeployed(safe, module, msg.sender);
        return module;
    }

    /**
     * @notice Enable inheritance module for a Safe
     */
    function enableInheritanceModule(address safe, address module) external onlySafeOrRegistry(safe) {
        if (safeToModule[safe] != module) revert ModuleNotFound();

        ISafe(safe).enableModule(module);
        emit InheritanceModuleEnabled(safe, module);
    }

    /**
     * @notice Disable inheritance module for a Safe
     */
    function disableInheritanceModule(address safe, address module) external onlySafeOrRegistry(safe) {
        if (safeToModule[safe] != module) revert ModuleNotFound();

        // Find previous module in the linked list
        address prevModule = _findPrevModule(safe, module);
        ISafe(safe).disableModule(prevModule, module);

        emit InheritanceModuleDisabled(safe, module);
    }

    /**
     * @notice Batch add beneficiaries to multiple Safes
     */
    function batchAddBeneficiaries(
        address[] calldata safes,
        address[] calldata beneficiaries,
        uint256[] calldata shares
    ) external {
        require(safes.length == beneficiaries.length && beneficiaries.length == shares.length, "Array length mismatch");

        for (uint256 i = 0; i < safes.length; i++) {
            address module = safeToModule[safes[i]];
            if (module != address(0)) {
                InheritanceModule(module).addBeneficiary(safes[i], beneficiaries[i], shares[i]);
                totalBeneficiaries++;
            }
        }
    }

    /**
     * @notice Batch execute inheritance for multiple beneficiaries
     */
    function batchExecuteInheritance(
        address[] calldata safes,
        address[] calldata beneficiaries,
        IInheritanceModule.AssetAllocation[][] calldata assets,
        bytes[] calldata oracleProofs
    ) external {
        require(
            safes.length == beneficiaries.length && beneficiaries.length == assets.length
                && assets.length == oracleProofs.length,
            "Array length mismatch"
        );

        for (uint256 i = 0; i < safes.length; i++) {
            address module = safeToModule[safes[i]];
            if (module != address(0)) {
                InheritanceModule(module).executeInheritance(safes[i], beneficiaries[i], assets[i], oracleProofs[i]);
                totalExecutions++;
            }
        }
    }

    /**
     * @notice Register a trusted oracle
     */
    function registerOracle(address oracle, bool isActive) external onlyOwner {
        trustedOracles[oracle] = isActive;
    }

    /**
     * @notice Update global inheritance settings
     */
    function updateGlobalSettings(
        uint256 _minInactivityPeriod,
        uint256 _maxInactivityPeriod,
        uint256 _defaultCooldownPeriod
    ) external onlyOwner {
        if (_minInactivityPeriod >= _maxInactivityPeriod) revert InvalidPeriodRange();

        minInactivityPeriod = _minInactivityPeriod;
        maxInactivityPeriod = _maxInactivityPeriod;
        defaultCooldownPeriod = _defaultCooldownPeriod;

        emit GlobalSettingsUpdated(_minInactivityPeriod, _maxInactivityPeriod, _defaultCooldownPeriod);
    }

    // View Functions

    /**
     * @notice Get inheritance module address for a Safe
     */
    function getInheritanceModule(address safe) external view returns (address module) {
        return safeToModule[safe];
    }

    /**
     * @notice Check if an oracle is trusted
     */
    function isTrustedOracle(address oracle) external view returns (bool isTrusted) {
        return trustedOracles[oracle];
    }

    /**
     * @notice Get global inheritance settings
     */
    function getGlobalSettings()
        external
        view
        returns (uint256 _minInactivityPeriod, uint256 _maxInactivityPeriod, uint256 _defaultCooldownPeriod)
    {
        return (minInactivityPeriod, maxInactivityPeriod, defaultCooldownPeriod);
    }

    /**
     * @notice Get all Safes with inheritance configured
     */
    function getAllInheritanceSafes() external view returns (address[] memory safes) {
        return inheritanceSafes;
    }

    /**
     * @notice Get inheritance statistics
     */
    function getInheritanceStats()
        external
        view
        returns (uint256 _totalSafes, uint256 _totalBeneficiaries, uint256 _totalExecutions)
    {
        return (inheritanceSafes.length, totalBeneficiaries, totalExecutions);
    }

    // Internal Functions

    /**
     * @notice Find the previous module in the Safe's module linked list
     */
    function _findPrevModule(address safe, address module) internal view returns (address prevModule) {
        address SENTINEL_MODULES = address(0x1);
        (address[] memory modules,) = ISafe(safe).getModulesPaginated(SENTINEL_MODULES, 100);

        prevModule = SENTINEL_MODULES;
        for (uint256 i = 0; i < modules.length; i++) {
            if (modules[i] == module) {
                return prevModule;
            }
            prevModule = modules[i];
        }

        revert ModuleNotFound();
    }
}
