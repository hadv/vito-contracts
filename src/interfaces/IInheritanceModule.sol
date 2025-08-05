// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title IInheritanceModule
 * @notice Interface for the Safe wallet inheritance module
 * @dev Provides comprehensive inheritance functionality for Safe wallets
 */
interface IInheritanceModule {
    // Structs
    
    /**
     * @notice Represents a beneficiary in the inheritance system
     * @param beneficiary Address of the beneficiary
     * @param share Percentage share of inheritance (basis points, 10000 = 100%)
     * @param isActive Whether the beneficiary is currently active
     * @param addedAt Timestamp when beneficiary was added
     */
    struct Beneficiary {
        address beneficiary;
        uint256 share;
        bool isActive;
        uint256 addedAt;
    }

    /**
     * @notice Inheritance configuration for a Safe wallet
     * @param owner Address of the Safe wallet owner
     * @param isActive Whether inheritance is currently active
     * @param inactivityPeriod Time period of inactivity before inheritance can be claimed
     * @param lastActivity Timestamp of last recorded activity
     * @param cooldownPeriod Minimum time between inheritance configuration changes
     * @param lastConfigChange Timestamp of last configuration change
     * @param requiresOracle Whether oracle verification is required
     * @param oracleAddress Address of the oracle for verification
     * @param emergencyStop Whether inheritance execution is emergency stopped
     */
    struct InheritanceConfig {
        address owner;
        bool isActive;
        uint256 inactivityPeriod;
        uint256 lastActivity;
        uint256 cooldownPeriod;
        uint256 lastConfigChange;
        bool requiresOracle;
        address oracleAddress;
        bool emergencyStop;
    }

    /**
     * @notice Asset allocation for inheritance
     * @param assetType Type of asset (0: ETH, 1: ERC20, 2: ERC721, 3: ERC1155)
     * @param assetAddress Address of the asset contract (zero for ETH)
     * @param tokenId Token ID for NFTs (unused for fungible tokens)
     * @param amount Amount or percentage to inherit
     * @param isPercentage Whether amount represents percentage or absolute value
     */
    struct AssetAllocation {
        uint8 assetType;
        address assetAddress;
        uint256 tokenId;
        uint256 amount;
        bool isPercentage;
    }

    // Events
    
    /**
     * @notice Emitted when inheritance is configured for a Safe
     * @param safe Address of the Safe wallet
     * @param owner Address of the owner configuring inheritance
     * @param inactivityPeriod Inactivity period in seconds
     */
    event InheritanceConfigured(
        address indexed safe,
        address indexed owner,
        uint256 inactivityPeriod
    );

    /**
     * @notice Emitted when a beneficiary is added
     * @param safe Address of the Safe wallet
     * @param beneficiary Address of the beneficiary
     * @param share Inheritance share in basis points
     */
    event BeneficiaryAdded(
        address indexed safe,
        address indexed beneficiary,
        uint256 share
    );

    /**
     * @notice Emitted when a beneficiary is removed
     * @param safe Address of the Safe wallet
     * @param beneficiary Address of the beneficiary
     */
    event BeneficiaryRemoved(
        address indexed safe,
        address indexed beneficiary
    );

    /**
     * @notice Emitted when beneficiary shares are updated
     * @param safe Address of the Safe wallet
     * @param beneficiary Address of the beneficiary
     * @param oldShare Previous share
     * @param newShare New share
     */
    event BeneficiaryShareUpdated(
        address indexed safe,
        address indexed beneficiary,
        uint256 oldShare,
        uint256 newShare
    );

    /**
     * @notice Emitted when inheritance is executed
     * @param safe Address of the Safe wallet
     * @param beneficiary Address of the beneficiary claiming inheritance
     * @param executor Address that executed the inheritance
     */
    event InheritanceExecuted(
        address indexed safe,
        address indexed beneficiary,
        address indexed executor
    );

    /**
     * @notice Emitted when activity is recorded for a Safe
     * @param safe Address of the Safe wallet
     * @param timestamp Timestamp of the activity
     */
    event ActivityRecorded(
        address indexed safe,
        uint256 timestamp
    );

    /**
     * @notice Emitted when inheritance configuration is updated
     * @param safe Address of the Safe wallet
     * @param inactivityPeriod New inactivity period
     * @param requiresOracle Whether oracle verification is required
     * @param oracleAddress Address of the oracle
     */
    event InheritanceConfigUpdated(
        address indexed safe,
        uint256 inactivityPeriod,
        bool requiresOracle,
        address oracleAddress
    );

    /**
     * @notice Emitted when emergency stop is toggled
     * @param safe Address of the Safe wallet
     * @param stopped Whether inheritance is stopped
     */
    event EmergencyStopToggled(
        address indexed safe,
        bool stopped
    );

    // Errors
    
    error NotSafeOwner();
    error InheritanceNotActive();
    error InheritanceAlreadyActive();
    error InvalidBeneficiary();
    error BeneficiaryNotFound();
    error InvalidShare();
    error SharesExceedMaximum();
    error InactivityPeriodNotMet();
    error CooldownPeriodNotMet();
    error OracleVerificationRequired();
    error InvalidOracle();
    error EmergencyStopActive();
    error InvalidAssetType();
    error InsufficientBalance();
    error TransferFailed();
    error InvalidInactivityPeriod();
    error InvalidCooldownPeriod();

    // Core Functions
    
    /**
     * @notice Configure inheritance for a Safe wallet
     * @param safe Address of the Safe wallet
     * @param inactivityPeriod Time period of inactivity before inheritance can be claimed
     * @param cooldownPeriod Minimum time between configuration changes
     * @param requiresOracle Whether oracle verification is required
     * @param oracleAddress Address of the oracle (if required)
     */
    function configureInheritance(
        address safe,
        uint256 inactivityPeriod,
        uint256 cooldownPeriod,
        bool requiresOracle,
        address oracleAddress
    ) external;

    /**
     * @notice Add a beneficiary to the inheritance
     * @param safe Address of the Safe wallet
     * @param beneficiary Address of the beneficiary
     * @param share Inheritance share in basis points (10000 = 100%)
     */
    function addBeneficiary(
        address safe,
        address beneficiary,
        uint256 share
    ) external;

    /**
     * @notice Remove a beneficiary from the inheritance
     * @param safe Address of the Safe wallet
     * @param beneficiary Address of the beneficiary to remove
     */
    function removeBeneficiary(
        address safe,
        address beneficiary
    ) external;

    /**
     * @notice Update beneficiary share
     * @param safe Address of the Safe wallet
     * @param beneficiary Address of the beneficiary
     * @param newShare New inheritance share in basis points
     */
    function updateBeneficiaryShare(
        address safe,
        address beneficiary,
        uint256 newShare
    ) external;

    /**
     * @notice Execute inheritance for a beneficiary
     * @param safe Address of the Safe wallet
     * @param beneficiary Address of the beneficiary
     * @param assets Array of asset allocations to inherit
     * @param oracleProof Proof from oracle if required
     */
    function executeInheritance(
        address safe,
        address beneficiary,
        AssetAllocation[] calldata assets,
        bytes calldata oracleProof
    ) external;

    /**
     * @notice Record activity for a Safe wallet (resets inactivity timer)
     * @param safe Address of the Safe wallet
     */
    function recordActivity(address safe) external;

    /**
     * @notice Toggle emergency stop for inheritance
     * @param safe Address of the Safe wallet
     * @param stop Whether to stop or resume inheritance
     */
    function toggleEmergencyStop(address safe, bool stop) external;

    // View Functions
    
    /**
     * @notice Get inheritance configuration for a Safe
     * @param safe Address of the Safe wallet
     * @return config Inheritance configuration
     */
    function getInheritanceConfig(address safe) 
        external 
        view 
        returns (InheritanceConfig memory config);

    /**
     * @notice Get all beneficiaries for a Safe
     * @param safe Address of the Safe wallet
     * @return beneficiaries Array of beneficiaries
     */
    function getBeneficiaries(address safe) 
        external 
        view 
        returns (Beneficiary[] memory beneficiaries);

    /**
     * @notice Check if inheritance can be executed for a beneficiary
     * @param safe Address of the Safe wallet
     * @param beneficiary Address of the beneficiary
     * @return canExecute Whether inheritance can be executed
     * @return reason Reason if inheritance cannot be executed
     */
    function canExecuteInheritance(address safe, address beneficiary) 
        external 
        view 
        returns (bool canExecute, string memory reason);

    /**
     * @notice Get time remaining until inheritance can be claimed
     * @param safe Address of the Safe wallet
     * @return timeRemaining Time in seconds until inheritance can be claimed
     */
    function getTimeUntilInheritance(address safe) 
        external 
        view 
        returns (uint256 timeRemaining);

    /**
     * @notice Check if an address is a beneficiary
     * @param safe Address of the Safe wallet
     * @param beneficiary Address to check
     * @return isBeneficiary Whether the address is a beneficiary
     * @return share Inheritance share if beneficiary
     */
    function isBeneficiary(address safe, address beneficiary) 
        external 
        view 
        returns (bool isBeneficiary, uint256 share);
}
