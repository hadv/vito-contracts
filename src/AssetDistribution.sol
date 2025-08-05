// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./interfaces/IInheritanceModule.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import "@openzeppelin/contracts/token/ERC1155/IERC1155.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";

/**
 * @title AssetDistribution
 * @notice Advanced asset distribution logic for inheritance
 * @dev Supports multiple distribution patterns and asset types
 */
contract AssetDistribution is ReentrancyGuard {
    using SafeMath for uint256;

    // Distribution patterns
    enum DistributionPattern {
        EQUAL_SPLIT, // Equal distribution among beneficiaries
        WEIGHTED, // Distribution based on predefined weights
        CONDITIONAL, // Distribution based on conditions
        TIERED, // Distribution in tiers/levels
        VESTING, // Time-based vesting distribution
        CUSTOM // Custom distribution logic

    }

    // Asset types
    enum AssetType {
        ETH,
        ERC20,
        ERC721,
        ERC1155
    }

    // Distribution rule structure
    struct DistributionRule {
        DistributionPattern pattern;
        uint256[] weights; // For weighted distribution
        uint256[] conditions; // For conditional distribution
        uint256 vestingPeriod; // For vesting distribution
        uint256 vestingCliff; // Cliff period for vesting
        bytes customLogic; // For custom distribution
        bool isActive;
    }

    // Vesting schedule
    struct VestingSchedule {
        uint256 totalAmount;
        uint256 releasedAmount;
        uint256 startTime;
        uint256 duration;
        uint256 cliffDuration;
        bool revocable;
        bool revoked;
    }

    // Conditional distribution
    struct ConditionalDistribution {
        bytes32 conditionHash;
        bool conditionMet;
        uint256 deadline;
        address oracle;
        bytes oracleData;
    }

    // Storage
    mapping(address => mapping(address => DistributionRule)) public distributionRules;
    mapping(address => mapping(address => VestingSchedule)) public vestingSchedules;
    mapping(address => mapping(bytes32 => ConditionalDistribution)) public conditionalDistributions;
    mapping(address => mapping(address => uint256)) public releasableAmounts;

    // Events
    event DistributionRuleSet(address indexed safe, address indexed beneficiary, DistributionPattern pattern);

    event AssetDistributed(
        address indexed safe, address indexed beneficiary, address indexed asset, uint256 amount, AssetType assetType
    );

    event VestingScheduleCreated(
        address indexed safe, address indexed beneficiary, uint256 totalAmount, uint256 duration
    );

    event TokensReleased(address indexed safe, address indexed beneficiary, uint256 amount);

    // Errors
    error InvalidDistributionPattern();
    error InvalidWeights();
    error ConditionNotMet();
    error VestingNotStarted();
    error InsufficientVestedAmount();
    error DistributionRevoked();
    error InvalidAssetType();

    /**
     * @notice Set distribution rule for a beneficiary
     * @param safe Address of the Safe wallet
     * @param beneficiary Address of the beneficiary
     * @param pattern Distribution pattern to use
     * @param weights Array of weights for weighted distribution
     * @param vestingPeriod Vesting period in seconds
     * @param vestingCliff Cliff period in seconds
     * @param customLogic Custom logic for distribution
     */
    function setDistributionRule(
        address safe,
        address beneficiary,
        DistributionPattern pattern,
        uint256[] calldata weights,
        uint256 vestingPeriod,
        uint256 vestingCliff,
        bytes calldata customLogic
    ) external {
        // Validate inputs
        if (pattern == DistributionPattern.WEIGHTED && weights.length == 0) {
            revert InvalidWeights();
        }

        distributionRules[safe][beneficiary] = DistributionRule({
            pattern: pattern,
            weights: weights,
            conditions: new uint256[](0),
            vestingPeriod: vestingPeriod,
            vestingCliff: vestingCliff,
            customLogic: customLogic,
            isActive: true
        });

        emit DistributionRuleSet(safe, beneficiary, pattern);
    }

    /**
     * @notice Distribute assets to beneficiaries
     * @param safe Address of the Safe wallet
     * @param beneficiaries Array of beneficiary addresses
     * @param assets Array of asset allocations
     * @param totalShares Total shares for distribution calculation
     */
    function distributeAssets(
        address safe,
        address[] calldata beneficiaries,
        IInheritanceModule.AssetAllocation[] calldata assets,
        uint256 totalShares
    ) external nonReentrant {
        for (uint256 i = 0; i < assets.length; i++) {
            IInheritanceModule.AssetAllocation memory asset = assets[i];

            if (asset.assetType == 0) {
                // ETH
                _distributeETH(safe, beneficiaries, asset, totalShares);
            } else if (asset.assetType == 1) {
                // ERC20
                _distributeERC20(safe, beneficiaries, asset, totalShares);
            } else if (asset.assetType == 2) {
                // ERC721
                _distributeERC721(safe, beneficiaries, asset);
            } else if (asset.assetType == 3) {
                // ERC1155
                _distributeERC1155(safe, beneficiaries, asset, totalShares);
            } else {
                revert InvalidAssetType();
            }
        }
    }

    /**
     * @notice Create vesting schedule for a beneficiary
     * @param safe Address of the Safe wallet
     * @param beneficiary Address of the beneficiary
     * @param totalAmount Total amount to vest
     * @param duration Vesting duration in seconds
     * @param cliffDuration Cliff duration in seconds
     * @param revocable Whether the vesting is revocable
     */
    function createVestingSchedule(
        address safe,
        address beneficiary,
        uint256 totalAmount,
        uint256 duration,
        uint256 cliffDuration,
        bool revocable
    ) external {
        vestingSchedules[safe][beneficiary] = VestingSchedule({
            totalAmount: totalAmount,
            releasedAmount: 0,
            startTime: block.timestamp,
            duration: duration,
            cliffDuration: cliffDuration,
            revocable: revocable,
            revoked: false
        });

        emit VestingScheduleCreated(safe, beneficiary, totalAmount, duration);
    }

    /**
     * @notice Release vested tokens to beneficiary
     * @param safe Address of the Safe wallet
     * @param beneficiary Address of the beneficiary
     * @param asset Asset to release
     */
    function releaseVestedTokens(address safe, address beneficiary, address asset) external nonReentrant {
        VestingSchedule storage schedule = vestingSchedules[safe][beneficiary];

        if (schedule.revoked) revert DistributionRevoked();
        if (block.timestamp < schedule.startTime + schedule.cliffDuration) {
            revert VestingNotStarted();
        }

        uint256 releasableAmount = _calculateReleasableAmount(safe, beneficiary);
        if (releasableAmount == 0) revert InsufficientVestedAmount();

        schedule.releasedAmount = schedule.releasedAmount.add(releasableAmount);

        // Transfer tokens
        if (asset == address(0)) {
            // ETH transfer
            payable(beneficiary).transfer(releasableAmount);
        } else {
            // ERC20 transfer
            IERC20(asset).transfer(beneficiary, releasableAmount);
        }

        emit TokensReleased(safe, beneficiary, releasableAmount);
    }

    /**
     * @notice Calculate distribution amounts for equal split
     * @param totalAmount Total amount to distribute
     * @param beneficiaryCount Number of beneficiaries
     * @return amounts Array of distribution amounts
     */
    function calculateEqualSplit(uint256 totalAmount, uint256 beneficiaryCount)
        public
        pure
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](beneficiaryCount);
        uint256 amountPerBeneficiary = totalAmount.div(beneficiaryCount);

        for (uint256 i = 0; i < beneficiaryCount; i++) {
            amounts[i] = amountPerBeneficiary;
        }

        // Handle remainder
        uint256 remainder = totalAmount.mod(beneficiaryCount);
        if (remainder > 0) {
            amounts[0] = amounts[0].add(remainder);
        }
    }

    /**
     * @notice Calculate distribution amounts for weighted distribution
     * @param totalAmount Total amount to distribute
     * @param weights Array of weights for each beneficiary
     * @param totalWeight Total weight for normalization
     * @return amounts Array of distribution amounts
     */
    function calculateWeightedDistribution(uint256 totalAmount, uint256[] memory weights, uint256 totalWeight)
        public
        pure
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](weights.length);

        for (uint256 i = 0; i < weights.length; i++) {
            amounts[i] = totalAmount.mul(weights[i]).div(totalWeight);
        }
    }

    /**
     * @notice Calculate tiered distribution
     * @param totalAmount Total amount to distribute
     * @param tiers Array of tier percentages
     * @param beneficiaryTiers Array mapping beneficiaries to tiers
     * @return amounts Array of distribution amounts
     */
    function calculateTieredDistribution(uint256 totalAmount, uint256[] memory tiers, uint256[] memory beneficiaryTiers)
        public
        pure
        returns (uint256[] memory amounts)
    {
        amounts = new uint256[](beneficiaryTiers.length);

        for (uint256 i = 0; i < beneficiaryTiers.length; i++) {
            uint256 tierIndex = beneficiaryTiers[i];
            if (tierIndex < tiers.length) {
                amounts[i] = totalAmount.mul(tiers[tierIndex]).div(10000); // Basis points
            }
        }
    }

    // Internal functions

    function _distributeETH(
        address safe,
        address[] calldata beneficiaries,
        IInheritanceModule.AssetAllocation memory asset,
        uint256 totalShares
    ) internal {
        uint256 totalAmount = safe.balance;
        if (asset.isPercentage) {
            totalAmount = totalAmount.mul(asset.amount).div(10000);
        } else {
            totalAmount = asset.amount;
        }

        for (uint256 i = 0; i < beneficiaries.length; i++) {
            address beneficiary = beneficiaries[i];
            DistributionRule memory rule = distributionRules[safe][beneficiary];

            uint256 amount = _calculateBeneficiaryAmount(totalAmount, rule, i, beneficiaries.length, totalShares);

            if (amount > 0) {
                payable(beneficiary).transfer(amount);
                emit AssetDistributed(safe, beneficiary, address(0), amount, AssetType.ETH);
            }
        }
    }

    function _distributeERC20(
        address safe,
        address[] calldata beneficiaries,
        IInheritanceModule.AssetAllocation memory asset,
        uint256 totalShares
    ) internal {
        IERC20 token = IERC20(asset.assetAddress);
        uint256 totalAmount = token.balanceOf(safe);

        if (asset.isPercentage) {
            totalAmount = totalAmount.mul(asset.amount).div(10000);
        } else {
            totalAmount = asset.amount;
        }

        for (uint256 i = 0; i < beneficiaries.length; i++) {
            address beneficiary = beneficiaries[i];
            DistributionRule memory rule = distributionRules[safe][beneficiary];

            uint256 amount = _calculateBeneficiaryAmount(totalAmount, rule, i, beneficiaries.length, totalShares);

            if (amount > 0) {
                token.transferFrom(safe, beneficiary, amount);
                emit AssetDistributed(safe, beneficiary, asset.assetAddress, amount, AssetType.ERC20);
            }
        }
    }

    function _distributeERC721(
        address safe,
        address[] calldata beneficiaries,
        IInheritanceModule.AssetAllocation memory asset
    ) internal {
        IERC721 nft = IERC721(asset.assetAddress);

        // For NFTs, distribute to the first eligible beneficiary
        for (uint256 i = 0; i < beneficiaries.length; i++) {
            address beneficiary = beneficiaries[i];
            DistributionRule memory rule = distributionRules[safe][beneficiary];

            if (rule.isActive) {
                nft.transferFrom(safe, beneficiary, asset.tokenId);
                emit AssetDistributed(safe, beneficiary, asset.assetAddress, 1, AssetType.ERC721);
                break;
            }
        }
    }

    function _distributeERC1155(
        address safe,
        address[] calldata beneficiaries,
        IInheritanceModule.AssetAllocation memory asset,
        uint256 totalShares
    ) internal {
        IERC1155 token = IERC1155(asset.assetAddress);
        uint256 totalAmount = token.balanceOf(safe, asset.tokenId);

        if (asset.isPercentage) {
            totalAmount = totalAmount.mul(asset.amount).div(10000);
        } else {
            totalAmount = asset.amount;
        }

        for (uint256 i = 0; i < beneficiaries.length; i++) {
            address beneficiary = beneficiaries[i];
            DistributionRule memory rule = distributionRules[safe][beneficiary];

            uint256 amount = _calculateBeneficiaryAmount(totalAmount, rule, i, beneficiaries.length, totalShares);

            if (amount > 0) {
                token.safeTransferFrom(safe, beneficiary, asset.tokenId, amount, "");
                emit AssetDistributed(safe, beneficiary, asset.assetAddress, amount, AssetType.ERC1155);
            }
        }
    }

    function _calculateBeneficiaryAmount(
        uint256 totalAmount,
        DistributionRule memory rule,
        uint256 beneficiaryIndex,
        uint256 totalBeneficiaries,
        uint256 totalShares
    ) internal pure returns (uint256) {
        if (!rule.isActive) return 0;

        if (rule.pattern == DistributionPattern.EQUAL_SPLIT) {
            return totalAmount.div(totalBeneficiaries);
        } else if (rule.pattern == DistributionPattern.WEIGHTED) {
            if (beneficiaryIndex < rule.weights.length) {
                return totalAmount.mul(rule.weights[beneficiaryIndex]).div(totalShares);
            }
        }

        return 0;
    }

    function _calculateReleasableAmount(address safe, address beneficiary) internal view returns (uint256) {
        VestingSchedule memory schedule = vestingSchedules[safe][beneficiary];

        if (block.timestamp < schedule.startTime + schedule.cliffDuration) {
            return 0;
        }

        uint256 elapsedTime = block.timestamp.sub(schedule.startTime);
        if (elapsedTime >= schedule.duration) {
            return schedule.totalAmount.sub(schedule.releasedAmount);
        }

        uint256 vestedAmount = schedule.totalAmount.mul(elapsedTime).div(schedule.duration);
        return vestedAmount.sub(schedule.releasedAmount);
    }

    // View functions

    function getDistributionRule(address safe, address beneficiary) external view returns (DistributionRule memory) {
        return distributionRules[safe][beneficiary];
    }

    function getVestingSchedule(address safe, address beneficiary) external view returns (VestingSchedule memory) {
        return vestingSchedules[safe][beneficiary];
    }

    function getReleasableAmount(address safe, address beneficiary) external view returns (uint256) {
        return _calculateReleasableAmount(safe, beneficiary);
    }
}
