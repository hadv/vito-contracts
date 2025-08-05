// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

/**
 * @title InheritanceSecurity
 * @notice Security and access control layer for inheritance system
 * @dev Provides comprehensive security measures and emergency controls
 */
contract InheritanceSecurity is AccessControl, Pausable, ReentrancyGuard {
    // Roles
    bytes32 public constant SECURITY_ADMIN_ROLE = keccak256("SECURITY_ADMIN_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    bytes32 public constant ORACLE_ROLE = keccak256("ORACLE_ROLE");
    bytes32 public constant AUDITOR_ROLE = keccak256("AUDITOR_ROLE");

    // Security configuration
    struct SecurityConfig {
        bool multiSigRequired;
        uint256 minSignatures;
        uint256 timelock;
        bool whitelistEnabled;
        bytes32 merkleRoot;
        uint256 maxDailyTransfers;
        uint256 maxTransferAmount;
    }

    // Rate limiting
    struct RateLimit {
        uint256 dailyTransferred;
        uint256 lastResetTime;
        uint256 transferCount;
    }

    // Suspicious activity tracking
    struct SuspiciousActivity {
        uint256 timestamp;
        address actor;
        string activityType;
        bytes data;
        bool resolved;
    }

    // Storage
    mapping(address => SecurityConfig) public safeSecurityConfigs;
    mapping(address => RateLimit) public rateLimits;
    mapping(address => bool) public blacklistedAddresses;
    mapping(address => bool) public whitelistedAddresses;
    mapping(bytes32 => bool) public executedTransactions;
    mapping(address => uint256) public lastActivityTime;

    SuspiciousActivity[] public suspiciousActivities;
    mapping(address => uint256[]) public safeSuspiciousActivities;

    // Emergency controls
    bool public globalEmergencyStop;
    mapping(address => bool) public safeEmergencyStop;
    mapping(address => uint256) public emergencyStopTime;

    // Timelock for critical operations
    mapping(bytes32 => uint256) public timelockOperations;
    uint256 public constant MIN_TIMELOCK = 24 hours;
    uint256 public constant MAX_TIMELOCK = 30 days;

    // Events
    event SecurityConfigUpdated(address indexed safe, SecurityConfig config);
    event SuspiciousActivityDetected(address indexed safe, address actor, string activityType);
    event EmergencyStopActivated(address indexed safe, address activator);
    event EmergencyStopDeactivated(address indexed safe, address deactivator);
    event AddressBlacklisted(address indexed addr, string reason);
    event AddressWhitelisted(address indexed addr);
    event TimelockOperationScheduled(bytes32 indexed operationId, uint256 executeTime);
    event TimelockOperationExecuted(bytes32 indexed operationId);

    // Errors
    error AddressIsBlacklisted();
    error NotWhitelisted();
    error RateLimitExceeded();
    error TransactionAlreadyExecuted();
    error InsufficientSignatures();
    error TimelockNotMet();
    error EmergencyStopActive();
    error SuspiciousActivityFound();
    error InvalidSecurityConfig();

    constructor() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(SECURITY_ADMIN_ROLE, msg.sender);
        _grantRole(EMERGENCY_ROLE, msg.sender);
    }

    /**
     * @notice Configure security settings for a Safe
     * @param safe Address of the Safe wallet
     * @param config Security configuration
     */
    function configureSecuritySettings(address safe, SecurityConfig calldata config)
        external
        onlyRole(SECURITY_ADMIN_ROLE)
    {
        if (config.minSignatures == 0 || config.timelock < MIN_TIMELOCK || config.timelock > MAX_TIMELOCK) {
            revert InvalidSecurityConfig();
        }

        safeSecurityConfigs[safe] = config;
        emit SecurityConfigUpdated(safe, config);
    }

    /**
     * @notice Check if a transaction is allowed
     * @param safe Address of the Safe wallet
     * @param to Destination address
     * @param value Transaction value
     * @param data Transaction data
     * @param signatures Required signatures
     * @return allowed Whether the transaction is allowed
     */
    function checkTransactionSecurity(
        address safe,
        address to,
        uint256 value,
        bytes calldata data,
        bytes[] calldata signatures
    ) external whenNotPaused nonReentrant returns (bool allowed) {
        // Check global emergency stop
        if (globalEmergencyStop || safeEmergencyStop[safe]) {
            revert EmergencyStopActive();
        }

        // Check blacklist
        if (blacklistedAddresses[to] || blacklistedAddresses[msg.sender]) {
            revert AddressIsBlacklisted();
        }

        SecurityConfig memory config = safeSecurityConfigs[safe];

        // Check whitelist if enabled
        if (config.whitelistEnabled && !whitelistedAddresses[to]) {
            if (config.merkleRoot != bytes32(0)) {
                // Merkle proof verification would go here
                revert NotWhitelisted();
            } else {
                revert NotWhitelisted();
            }
        }

        // Check rate limits
        _checkRateLimit(safe, value);

        // Check multi-sig requirements
        if (config.multiSigRequired) {
            _verifyMultiSig(safe, to, value, data, signatures, config.minSignatures);
        }

        // Check for suspicious activity
        _detectSuspiciousActivity(safe, to, value, data);

        // Update activity tracking
        lastActivityTime[safe] = block.timestamp;

        return true;
    }

    /**
     * @notice Schedule a timelock operation
     * @param operationId Unique identifier for the operation
     * @param delay Delay before execution
     */
    function scheduleTimelockOperation(bytes32 operationId, uint256 delay) external onlyRole(SECURITY_ADMIN_ROLE) {
        require(delay >= MIN_TIMELOCK && delay <= MAX_TIMELOCK, "Invalid delay");

        uint256 executeTime = block.timestamp + delay;
        timelockOperations[operationId] = executeTime;

        emit TimelockOperationScheduled(operationId, executeTime);
    }

    /**
     * @notice Execute a timelock operation
     * @param operationId Unique identifier for the operation
     */
    function executeTimelockOperation(bytes32 operationId) external onlyRole(SECURITY_ADMIN_ROLE) {
        uint256 executeTime = timelockOperations[operationId];
        require(executeTime != 0, "Operation not scheduled");
        require(block.timestamp >= executeTime, "Timelock not met");

        delete timelockOperations[operationId];
        emit TimelockOperationExecuted(operationId);
    }

    /**
     * @notice Activate emergency stop for a specific Safe
     * @param safe Address of the Safe wallet
     * @param reason Reason for emergency stop
     */
    function activateEmergencyStop(address safe, string calldata reason) external onlyRole(EMERGENCY_ROLE) {
        safeEmergencyStop[safe] = true;
        emergencyStopTime[safe] = block.timestamp;

        _reportSuspiciousActivity(safe, msg.sender, "EMERGENCY_STOP", abi.encode(reason));
        emit EmergencyStopActivated(safe, msg.sender);
    }

    /**
     * @notice Deactivate emergency stop for a specific Safe
     * @param safe Address of the Safe wallet
     */
    function deactivateEmergencyStop(address safe) external onlyRole(EMERGENCY_ROLE) {
        safeEmergencyStop[safe] = false;
        emit EmergencyStopDeactivated(safe, msg.sender);
    }

    /**
     * @notice Activate global emergency stop
     */
    function activateGlobalEmergencyStop() external onlyRole(EMERGENCY_ROLE) {
        globalEmergencyStop = true;
        _pause();
    }

    /**
     * @notice Deactivate global emergency stop
     */
    function deactivateGlobalEmergencyStop() external onlyRole(EMERGENCY_ROLE) {
        globalEmergencyStop = false;
        _unpause();
    }

    /**
     * @notice Blacklist an address
     * @param addr Address to blacklist
     * @param reason Reason for blacklisting
     */
    function blacklistAddress(address addr, string calldata reason) external onlyRole(SECURITY_ADMIN_ROLE) {
        blacklistedAddresses[addr] = true;
        emit AddressBlacklisted(addr, reason);
    }

    /**
     * @notice Whitelist an address
     * @param addr Address to whitelist
     */
    function whitelistAddress(address addr) external onlyRole(SECURITY_ADMIN_ROLE) {
        whitelistedAddresses[addr] = true;
        emit AddressWhitelisted(addr);
    }

    /**
     * @notice Report suspicious activity
     * @param safe Address of the Safe wallet
     * @param actor Address of the actor
     * @param activityType Type of suspicious activity
     * @param data Additional data
     */
    function reportSuspiciousActivity(address safe, address actor, string calldata activityType, bytes calldata data)
        external
        onlyRole(AUDITOR_ROLE)
    {
        _reportSuspiciousActivity(safe, actor, activityType, data);
    }

    // Internal functions

    function _checkRateLimit(address safe, uint256 value) internal {
        RateLimit storage limit = rateLimits[safe];
        SecurityConfig memory config = safeSecurityConfigs[safe];

        // Reset daily counter if needed
        if (block.timestamp >= limit.lastResetTime + 1 days) {
            limit.dailyTransferred = 0;
            limit.transferCount = 0;
            limit.lastResetTime = block.timestamp;
        }

        // Check daily transfer limit
        if (limit.dailyTransferred + value > config.maxDailyTransfers) {
            revert RateLimitExceeded();
        }

        // Check single transfer limit
        if (value > config.maxTransferAmount) {
            revert RateLimitExceeded();
        }

        // Update counters
        limit.dailyTransferred += value;
        limit.transferCount++;
    }

    function _verifyMultiSig(
        address safe,
        address to,
        uint256 value,
        bytes calldata data,
        bytes[] calldata signatures,
        uint256 minSignatures
    ) internal view {
        if (signatures.length < minSignatures) {
            revert InsufficientSignatures();
        }

        bytes32 txHash = keccak256(abi.encodePacked(safe, to, value, data, block.timestamp));

        // Verify signatures (simplified - in production would verify against Safe owners)
        // This would integrate with Safe's signature verification
    }

    function _detectSuspiciousActivity(address safe, address to, uint256 value, bytes calldata data) internal {
        // Detect unusual patterns
        bool suspicious = false;
        string memory activityType;

        // Check for large transfers
        SecurityConfig memory config = safeSecurityConfigs[safe];
        if (value > config.maxTransferAmount * 5) {
            suspicious = true;
            activityType = "LARGE_TRANSFER";
        }

        // Check for rapid succession of transfers
        if (block.timestamp - lastActivityTime[safe] < 1 hours) {
            RateLimit memory limit = rateLimits[safe];
            if (limit.transferCount > 10) {
                suspicious = true;
                activityType = "RAPID_TRANSFERS";
            }
        }

        if (suspicious) {
            _reportSuspiciousActivity(safe, msg.sender, activityType, abi.encode(to, value, data));
        }
    }

    function _reportSuspiciousActivity(address safe, address actor, string memory activityType, bytes memory data)
        internal
    {
        uint256 activityId = suspiciousActivities.length;

        suspiciousActivities.push(
            SuspiciousActivity({
                timestamp: block.timestamp,
                actor: actor,
                activityType: activityType,
                data: data,
                resolved: false
            })
        );

        safeSuspiciousActivities[safe].push(activityId);

        emit SuspiciousActivityDetected(safe, actor, activityType);
    }

    // View functions

    function getSuspiciousActivities(address safe) external view returns (SuspiciousActivity[] memory activities) {
        uint256[] memory activityIds = safeSuspiciousActivities[safe];
        activities = new SuspiciousActivity[](activityIds.length);

        for (uint256 i = 0; i < activityIds.length; i++) {
            activities[i] = suspiciousActivities[activityIds[i]];
        }
    }

    function getSecurityConfig(address safe) external view returns (SecurityConfig memory config) {
        return safeSecurityConfigs[safe];
    }

    function getRateLimit(address safe) external view returns (RateLimit memory limit) {
        return rateLimits[safe];
    }
}
