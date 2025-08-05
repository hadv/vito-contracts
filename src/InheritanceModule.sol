// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./interfaces/IInheritanceModule.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

// Safe interface for module execution
interface ISafe {
    function execTransactionFromModule(address to, uint256 value, bytes memory data, uint8 operation)
        external
        returns (bool success);

    function getOwners() external view returns (address[] memory);
    function isOwner(address owner) external view returns (bool);
}

/**
 * @title InheritanceModule
 * @notice Safe wallet module for comprehensive inheritance functionality
 * @dev Implements inheritance with multiple trigger types and asset distribution patterns
 */
contract InheritanceModule is IInheritanceModule, ReentrancyGuard {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    // Constants
    uint256 public constant MAX_BENEFICIARIES = 50;
    uint256 public constant MAX_SHARE = 10000; // 100% in basis points
    uint256 public constant MIN_INACTIVITY_PERIOD = 30 days;
    uint256 public constant MAX_INACTIVITY_PERIOD = 10 * 365 days; // 10 years
    uint256 public constant MIN_COOLDOWN_PERIOD = 7 days;

    // Storage
    mapping(address => InheritanceConfig) public inheritanceConfigs;
    mapping(address => Beneficiary[]) public beneficiaries;
    mapping(address => mapping(address => uint256)) public beneficiaryIndex;
    mapping(address => bool) public trustedOracles;

    // Manager address for access control
    address public manager;

    // Global settings
    uint256 public minInactivityPeriod = MIN_INACTIVITY_PERIOD;
    uint256 public maxInactivityPeriod = MAX_INACTIVITY_PERIOD;
    uint256 public defaultCooldownPeriod = MIN_COOLDOWN_PERIOD;

    modifier onlyManager() {
        require(msg.sender == manager, "Only manager can call this function");
        _;
    }

    modifier onlySafeOwner(address safe) {
        require(ISafe(safe).isOwner(msg.sender), "Not a Safe owner");
        _;
    }

    modifier inheritanceActive(address safe) {
        if (!inheritanceConfigs[safe].isActive) revert InheritanceNotActive();
        _;
    }

    modifier notEmergencyStopped(address safe) {
        if (inheritanceConfigs[safe].emergencyStop) revert EmergencyStopActive();
        _;
    }

    constructor(address _manager) {
        manager = _manager;
    }

    /**
     * @notice Configure inheritance for a Safe wallet
     */
    function configureInheritance(
        address safe,
        uint256 inactivityPeriod,
        uint256 cooldownPeriod,
        bool requiresOracle,
        address oracleAddress
    ) external onlySafeOwner(safe) {
        if (inactivityPeriod < minInactivityPeriod || inactivityPeriod > maxInactivityPeriod) {
            revert InvalidInactivityPeriod();
        }
        if (cooldownPeriod < MIN_COOLDOWN_PERIOD) {
            revert InvalidCooldownPeriod();
        }
        if (requiresOracle && !trustedOracles[oracleAddress]) {
            revert InvalidOracle();
        }

        InheritanceConfig storage config = inheritanceConfigs[safe];

        // Check cooldown period for existing configurations
        if (config.isActive && block.timestamp < config.lastConfigChange + config.cooldownPeriod) {
            revert CooldownPeriodNotMet();
        }

        config.owner = msg.sender;
        config.isActive = true;
        config.inactivityPeriod = inactivityPeriod;
        config.lastActivity = block.timestamp;
        config.cooldownPeriod = cooldownPeriod;
        config.lastConfigChange = block.timestamp;
        config.requiresOracle = requiresOracle;
        config.oracleAddress = oracleAddress;
        config.emergencyStop = false;

        emit InheritanceConfigured(safe, msg.sender, inactivityPeriod);
    }

    /**
     * @notice Add a beneficiary to the inheritance
     */
    function addBeneficiary(address safe, address beneficiary, uint256 share)
        external
        onlySafeOwner(safe)
        inheritanceActive(safe)
    {
        if (beneficiary == address(0) || beneficiary == safe) revert InvalidBeneficiary();
        if (share == 0 || share > MAX_SHARE) revert InvalidShare();
        if (beneficiaries[safe].length >= MAX_BENEFICIARIES) revert InvalidBeneficiary();

        // Check if beneficiary already exists
        if (beneficiaryIndex[safe][beneficiary] != 0) revert InvalidBeneficiary();

        // Check total shares don't exceed 100%
        uint256 totalShares = _getTotalShares(safe) + share;
        if (totalShares > MAX_SHARE) revert SharesExceedMaximum();

        beneficiaries[safe].push(
            Beneficiary({beneficiary: beneficiary, share: share, isActive: true, addedAt: block.timestamp})
        );

        beneficiaryIndex[safe][beneficiary] = beneficiaries[safe].length;

        emit BeneficiaryAdded(safe, beneficiary, share);
    }

    /**
     * @notice Remove a beneficiary from the inheritance
     */
    function removeBeneficiary(address safe, address beneficiary)
        external
        onlySafeOwner(safe)
        inheritanceActive(safe)
    {
        uint256 index = beneficiaryIndex[safe][beneficiary];
        if (index == 0) revert BeneficiaryNotFound();

        // Convert to array index (stored index is 1-based)
        index--;

        // Move last element to deleted spot to maintain array density
        uint256 lastIndex = beneficiaries[safe].length - 1;
        if (index != lastIndex) {
            beneficiaries[safe][index] = beneficiaries[safe][lastIndex];
            beneficiaryIndex[safe][beneficiaries[safe][index].beneficiary] = index + 1;
        }

        beneficiaries[safe].pop();
        delete beneficiaryIndex[safe][beneficiary];

        emit BeneficiaryRemoved(safe, beneficiary);
    }

    /**
     * @notice Update beneficiary share
     */
    function updateBeneficiaryShare(address safe, address beneficiary, uint256 newShare)
        external
        onlySafeOwner(safe)
        inheritanceActive(safe)
    {
        uint256 index = beneficiaryIndex[safe][beneficiary];
        if (index == 0) revert BeneficiaryNotFound();
        if (newShare == 0 || newShare > MAX_SHARE) revert InvalidShare();

        index--; // Convert to array index
        uint256 oldShare = beneficiaries[safe][index].share;

        // Check total shares don't exceed 100%
        uint256 totalShares = _getTotalShares(safe) - oldShare + newShare;
        if (totalShares > MAX_SHARE) revert SharesExceedMaximum();

        beneficiaries[safe][index].share = newShare;

        emit BeneficiaryShareUpdated(safe, beneficiary, oldShare, newShare);
    }

    /**
     * @notice Execute inheritance for a beneficiary
     */
    function executeInheritance(
        address safe,
        address beneficiary,
        AssetAllocation[] calldata assets,
        bytes calldata oracleProof
    ) external nonReentrant inheritanceActive(safe) notEmergencyStopped(safe) {
        InheritanceConfig storage config = inheritanceConfigs[safe];

        // Check inactivity period
        if (block.timestamp < config.lastActivity + config.inactivityPeriod) {
            revert InactivityPeriodNotMet();
        }

        // Verify beneficiary exists and is active
        uint256 index = beneficiaryIndex[safe][beneficiary];
        if (index == 0) revert BeneficiaryNotFound();
        index--; // Convert to array index

        Beneficiary storage ben = beneficiaries[safe][index];
        if (!ben.isActive) revert BeneficiaryNotFound();

        // Oracle verification if required
        if (config.requiresOracle) {
            _verifyOracleProof(safe, beneficiary, oracleProof, config.oracleAddress);
        }

        // Execute asset transfers
        _executeAssetTransfers(safe, beneficiary, assets, ben.share);

        emit InheritanceExecuted(safe, beneficiary, msg.sender);
    }

    /**
     * @notice Record activity for a Safe wallet (resets inactivity timer)
     */
    function recordActivity(address safe) external {
        // Only Safe itself or its owners can record activity
        require(msg.sender == safe || ISafe(safe).isOwner(msg.sender), "Unauthorized to record activity");

        if (inheritanceConfigs[safe].isActive) {
            inheritanceConfigs[safe].lastActivity = block.timestamp;
            emit ActivityRecorded(safe, block.timestamp);
        }
    }

    /**
     * @notice Toggle emergency stop for inheritance
     */
    function toggleEmergencyStop(address safe, bool stop) external onlySafeOwner(safe) inheritanceActive(safe) {
        inheritanceConfigs[safe].emergencyStop = stop;
        emit EmergencyStopToggled(safe, stop);
    }

    // Internal functions

    function _getTotalShares(address safe) internal view returns (uint256 total) {
        Beneficiary[] storage safeBeneficiaries = beneficiaries[safe];
        for (uint256 i = 0; i < safeBeneficiaries.length; i++) {
            if (safeBeneficiaries[i].isActive) {
                total += safeBeneficiaries[i].share;
            }
        }
    }

    function _verifyOracleProof(address safe, address beneficiary, bytes calldata proof, address oracle)
        internal
        view
    {
        if (!trustedOracles[oracle]) revert InvalidOracle();

        // Decode oracle signature
        if (proof.length != 65) revert OracleVerificationRequired();

        bytes32 message = keccak256(abi.encodePacked(safe, beneficiary, block.timestamp / 1 days));
        bytes32 ethSignedMessage = message.toEthSignedMessageHash();

        address signer = ethSignedMessage.recover(proof);
        if (signer != oracle) revert OracleVerificationRequired();
    }

    function _executeAssetTransfers(
        address safe,
        address beneficiary,
        AssetAllocation[] calldata assets,
        uint256 beneficiaryShare
    ) internal {
        for (uint256 i = 0; i < assets.length; i++) {
            AssetAllocation memory asset = assets[i];
            uint256 transferAmount;

            if (asset.assetType == 0) {
                // ETH
                uint256 balance = safe.balance;
                transferAmount = asset.isPercentage
                    ? (balance * asset.amount * beneficiaryShare) / (MAX_SHARE * MAX_SHARE)
                    : (asset.amount * beneficiaryShare) / MAX_SHARE;

                if (transferAmount > 0) {
                    _executeTransaction(safe, beneficiary, transferAmount, "", 0);
                }
            } else if (asset.assetType == 1) {
                // ERC20
                IERC20 token = IERC20(asset.assetAddress);
                uint256 balance = token.balanceOf(safe);
                transferAmount = asset.isPercentage
                    ? (balance * asset.amount * beneficiaryShare) / (MAX_SHARE * MAX_SHARE)
                    : (asset.amount * beneficiaryShare) / MAX_SHARE;

                if (transferAmount > 0) {
                    bytes memory data = abi.encodeWithSelector(token.transfer.selector, beneficiary, transferAmount);
                    _executeTransaction(safe, asset.assetAddress, 0, data, 0);
                }
            }
            // Additional asset types (ERC721, ERC1155) can be implemented here
        }
    }

    function _executeTransaction(address safe, address to, uint256 value, bytes memory data, uint8 operation)
        internal
    {
        bool success = ISafe(safe).execTransactionFromModule(to, value, data, operation);
        if (!success) revert TransferFailed();
    }

    // View Functions

    /**
     * @notice Get inheritance configuration for a Safe
     */
    function getInheritanceConfig(address safe) external view returns (InheritanceConfig memory config) {
        return inheritanceConfigs[safe];
    }

    /**
     * @notice Get all beneficiaries for a Safe
     */
    function getBeneficiaries(address safe) external view returns (Beneficiary[] memory) {
        return beneficiaries[safe];
    }

    /**
     * @notice Check if inheritance can be executed for a beneficiary
     */
    function canExecuteInheritance(address safe, address beneficiary)
        external
        view
        returns (bool canExecute, string memory reason)
    {
        InheritanceConfig memory config = inheritanceConfigs[safe];

        if (!config.isActive) {
            return (false, "Inheritance not active");
        }

        if (config.emergencyStop) {
            return (false, "Emergency stop active");
        }

        uint256 index = beneficiaryIndex[safe][beneficiary];
        if (index == 0) {
            return (false, "Not a beneficiary");
        }

        if (!beneficiaries[safe][index - 1].isActive) {
            return (false, "Beneficiary not active");
        }

        if (block.timestamp < config.lastActivity + config.inactivityPeriod) {
            return (false, "Inactivity period not met");
        }

        return (true, "");
    }

    /**
     * @notice Get time remaining until inheritance can be claimed
     */
    function getTimeUntilInheritance(address safe) external view returns (uint256 timeRemaining) {
        InheritanceConfig memory config = inheritanceConfigs[safe];

        if (!config.isActive) {
            return type(uint256).max;
        }

        uint256 inheritanceTime = config.lastActivity + config.inactivityPeriod;

        if (block.timestamp >= inheritanceTime) {
            return 0;
        }

        return inheritanceTime - block.timestamp;
    }

    /**
     * @notice Check if an address is a beneficiary
     */
    function isBeneficiary(address safe, address beneficiary)
        external
        view
        returns (bool isValidBeneficiary, uint256 share)
    {
        uint256 index = beneficiaryIndex[safe][beneficiary];
        if (index == 0) {
            return (false, 0);
        }

        Beneficiary memory ben = beneficiaries[safe][index - 1];
        return (ben.isActive, ben.share);
    }

    // Manager Functions

    /**
     * @notice Register a trusted oracle (only manager)
     */
    function registerOracle(address oracle, bool isActive) external onlyManager {
        trustedOracles[oracle] = isActive;
    }

    /**
     * @notice Update global settings (only manager)
     */
    function updateGlobalSettings(
        uint256 _minInactivityPeriod,
        uint256 _maxInactivityPeriod,
        uint256 _defaultCooldownPeriod
    ) external onlyManager {
        require(_minInactivityPeriod >= 1 days, "Min period too short");
        require(_maxInactivityPeriod <= 20 * 365 days, "Max period too long");
        require(_minInactivityPeriod <= _maxInactivityPeriod, "Invalid period range");
        require(_defaultCooldownPeriod >= 1 days, "Cooldown too short");

        minInactivityPeriod = _minInactivityPeriod;
        maxInactivityPeriod = _maxInactivityPeriod;
        defaultCooldownPeriod = _defaultCooldownPeriod;
    }

    /**
     * @notice Check if an oracle is trusted
     */
    function isTrustedOracle(address oracle) external view returns (bool) {
        return trustedOracles[oracle];
    }
}
