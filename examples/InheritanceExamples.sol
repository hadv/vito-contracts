// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../src/InheritanceModule.sol";
import "../src/InheritanceManager.sol";
import "../src/InheritanceOracle.sol";
import "../src/InheritanceAutomation.sol";
import "../src/AssetDistribution.sol";
import "../src/interfaces/IInheritanceModule.sol";

/**
 * @title InheritanceExamples
 * @notice Comprehensive examples for using the Safe Wallet Inheritance Module
 * @dev This contract demonstrates various inheritance scenarios and patterns
 */
contract InheritanceExamples {
    
    InheritanceManager public manager;
    InheritanceOracle public oracle;
    InheritanceAutomation public automation;
    AssetDistribution public assetDistribution;
    
    // Example Safe addresses
    address public constant EXAMPLE_SAFE = 0x1234567890123456789012345678901234567890;
    address public constant SPOUSE = 0x2345678901234567890123456789012345678901;
    address public constant CHILD1 = 0x3456789012345678901234567890123456789012;
    address public constant CHILD2 = 0x4567890123456789012345678901234567890123;
    address public constant CHARITY = 0x5678901234567890123456789012345678901234;
    
    constructor(
        address _manager,
        address _oracle,
        address _automation,
        address _assetDistribution
    ) {
        manager = InheritanceManager(_manager);
        oracle = InheritanceOracle(_oracle);
        automation = InheritanceAutomation(_automation);
        assetDistribution = AssetDistribution(_assetDistribution);
    }
    
    /**
     * @notice Example 1: Simple Family Inheritance
     * @dev Sets up inheritance for a family with spouse and children
     */
    function setupFamilyInheritance() external {
        // Deploy inheritance module for the Safe
        address module = manager.deployInheritanceModule(
            EXAMPLE_SAFE,
            180 days,       // 6 months inactivity period
            14 days,        // 2 weeks cooldown period
            false,          // no oracle verification required
            address(0)      // no oracle needed
        );
        
        // Enable the module on the Safe
        manager.enableInheritanceModule(EXAMPLE_SAFE, module);
        
        // Add beneficiaries with traditional family distribution
        InheritanceModule(module).addBeneficiary(EXAMPLE_SAFE, SPOUSE, 5000);  // 50% to spouse
        InheritanceModule(module).addBeneficiary(EXAMPLE_SAFE, CHILD1, 2500);  // 25% to first child
        InheritanceModule(module).addBeneficiary(EXAMPLE_SAFE, CHILD2, 2500);  // 25% to second child
    }
    
    /**
     * @notice Example 2: Charitable Inheritance with Oracle Verification
     * @dev Sets up inheritance that includes charitable donations with death certificate verification
     */
    function setupCharitableInheritance() external {
        // Deploy inheritance module with oracle verification
        address module = manager.deployInheritanceModule(
            EXAMPLE_SAFE,
            90 days,        // 3 months inactivity period
            7 days,         // 1 week cooldown period
            true,           // oracle verification required
            address(oracle) // oracle address
        );
        
        manager.enableInheritanceModule(EXAMPLE_SAFE, module);
        
        // Add beneficiaries including charity
        InheritanceModule(module).addBeneficiary(EXAMPLE_SAFE, SPOUSE, 4000);   // 40% to spouse
        InheritanceModule(module).addBeneficiary(EXAMPLE_SAFE, CHILD1, 3000);   // 30% to child
        InheritanceModule(module).addBeneficiary(EXAMPLE_SAFE, CHARITY, 3000);  // 30% to charity
    }
    
    /**
     * @notice Example 3: Vesting Inheritance for Minor Children
     * @dev Sets up inheritance with vesting schedules for minor beneficiaries
     */
    function setupVestingInheritance() external {
        address module = manager.deployInheritanceModule(
            EXAMPLE_SAFE,
            365 days,       // 1 year inactivity period
            30 days,        // 1 month cooldown period
            true,           // oracle verification required
            address(oracle)
        );
        
        manager.enableInheritanceModule(EXAMPLE_SAFE, module);
        
        // Add beneficiaries
        InheritanceModule(module).addBeneficiary(EXAMPLE_SAFE, SPOUSE, 5000);   // 50% immediate
        InheritanceModule(module).addBeneficiary(EXAMPLE_SAFE, CHILD1, 2500);   // 25% vested
        InheritanceModule(module).addBeneficiary(EXAMPLE_SAFE, CHILD2, 2500);   // 25% vested
        
        // Create vesting schedules for children (release over 10 years starting at age 18)
        assetDistribution.createVestingSchedule(
            EXAMPLE_SAFE,
            CHILD1,
            1000000,        // 1M tokens
            10 * 365 days,  // 10 years vesting
            0,              // no cliff
            false           // non-revocable
        );
        
        assetDistribution.createVestingSchedule(
            EXAMPLE_SAFE,
            CHILD2,
            1000000,        // 1M tokens
            10 * 365 days,  // 10 years vesting
            0,              // no cliff
            false           // non-revocable
        );
    }
    
    /**
     * @notice Example 4: Automated Inheritance Execution
     * @dev Sets up automated inheritance execution using the automation service
     */
    function setupAutomatedInheritance() external payable {
        address module = manager.deployInheritanceModule(
            EXAMPLE_SAFE,
            180 days,       // 6 months inactivity
            7 days,         // 1 week cooldown
            false,          // no oracle required
            address(0)
        );
        
        manager.enableInheritanceModule(EXAMPLE_SAFE, module);
        
        // Add beneficiaries
        InheritanceModule(module).addBeneficiary(EXAMPLE_SAFE, SPOUSE, 10000); // 100% to spouse
        
        // Prepare asset allocations
        IInheritanceModule.AssetAllocation[] memory assets = 
            new IInheritanceModule.AssetAllocation[](1);
        assets[0] = IInheritanceModule.AssetAllocation({
            assetType: 0,           // ETH
            assetAddress: address(0),
            tokenId: 0,
            amount: 10000,          // 100%
            isPercentage: true
        });
        
        // Create automation job for 6 months from now
        automation.createAutomationJob{value: msg.value}(
            EXAMPLE_SAFE,
            module,
            SPOUSE,
            assets,
            "",                     // no oracle proof
            block.timestamp + 180 days
        );
    }
    
    /**
     * @notice Example 5: Complex Multi-Asset Inheritance
     * @dev Demonstrates inheritance of multiple asset types with different distributions
     */
    function setupMultiAssetInheritance() external {
        address module = manager.deployInheritanceModule(
            EXAMPLE_SAFE,
            90 days,        // 3 months inactivity
            14 days,        // 2 weeks cooldown
            true,           // oracle verification
            address(oracle)
        );
        
        manager.enableInheritanceModule(EXAMPLE_SAFE, module);
        
        // Add beneficiaries
        InheritanceModule(module).addBeneficiary(EXAMPLE_SAFE, SPOUSE, 4000);   // 40%
        InheritanceModule(module).addBeneficiary(EXAMPLE_SAFE, CHILD1, 3000);   // 30%
        InheritanceModule(module).addBeneficiary(EXAMPLE_SAFE, CHILD2, 3000);   // 30%
        
        // Set up different distribution patterns for different assets
        
        // Equal split for ETH
        assetDistribution.setDistributionRule(
            EXAMPLE_SAFE,
            SPOUSE,
            AssetDistribution.DistributionPattern.EQUAL_SPLIT,
            new uint256[](0),
            0,
            0,
            ""
        );
        
        // Weighted distribution for ERC20 tokens
        uint256[] memory weights = new uint256[](3);
        weights[0] = 4000; // 40% to spouse
        weights[1] = 3000; // 30% to child1
        weights[2] = 3000; // 30% to child2
        
        assetDistribution.setDistributionRule(
            EXAMPLE_SAFE,
            SPOUSE,
            AssetDistribution.DistributionPattern.WEIGHTED,
            weights,
            0,
            0,
            ""
        );
    }
    
    /**
     * @notice Example 6: Emergency Inheritance Setup
     * @dev Quick inheritance setup for emergency situations
     */
    function setupEmergencyInheritance(address emergencyBeneficiary) external {
        address module = manager.deployInheritanceModule(
            EXAMPLE_SAFE,
            7 days,         // 1 week inactivity (emergency)
            1 days,         // 1 day cooldown
            false,          // no oracle required for speed
            address(0)
        );
        
        manager.enableInheritanceModule(EXAMPLE_SAFE, module);
        
        // Single beneficiary gets everything
        InheritanceModule(module).addBeneficiary(EXAMPLE_SAFE, emergencyBeneficiary, 10000);
    }
    
    /**
     * @notice Example 7: Execute Inheritance with Oracle Verification
     * @dev Demonstrates the complete inheritance execution process with oracle
     */
    function executeInheritanceWithOracle(
        address safe,
        address module,
        address beneficiary,
        string calldata documentHash
    ) external {
        // Step 1: Request verification from oracle
        bytes32 requestId = oracle.requestVerification{value: 0.01 ether}(
            safe,
            beneficiary,
            InheritanceOracle.VerificationType.DEATH_CERTIFICATE,
            documentHash,
            0 // use default expiry
        );
        
        // Step 2: Oracle verifies (this would be done by authorized verifier)
        // oracle.completeVerification(requestId, true, "");
        
        // Step 3: Generate proof
        bytes memory proof = oracle.generateVerificationProof(
            requestId,
            safe,
            beneficiary
        );
        
        // Step 4: Prepare asset allocations
        IInheritanceModule.AssetAllocation[] memory assets = 
            new IInheritanceModule.AssetAllocation[](2);
        
        // Inherit all ETH
        assets[0] = IInheritanceModule.AssetAllocation({
            assetType: 0,
            assetAddress: address(0),
            tokenId: 0,
            amount: 10000,
            isPercentage: true
        });
        
        // Inherit all ERC20 tokens (example token address)
        assets[1] = IInheritanceModule.AssetAllocation({
            assetType: 1,
            assetAddress: 0x6B175474E89094C44Da98b954EedeAC495271d0F, // DAI
            tokenId: 0,
            amount: 10000,
            isPercentage: true
        });
        
        // Step 5: Execute inheritance
        InheritanceModule(module).executeInheritance(
            safe,
            beneficiary,
            assets,
            proof
        );
    }
    
    /**
     * @notice Example 8: Batch Operations
     * @dev Demonstrates batch operations for managing multiple Safes
     */
    function batchInheritanceSetup(
        address[] calldata safes,
        address[] calldata beneficiaries,
        uint256[] calldata shares
    ) external {
        // Batch add beneficiaries to multiple Safes
        manager.batchAddBeneficiaries(safes, beneficiaries, shares);
    }
    
    /**
     * @notice Example 9: Activity Recording
     * @dev Shows how to record activity to reset inactivity timer
     */
    function recordSafeActivity(address safe, address module) external {
        // Record activity to reset inactivity timer
        InheritanceModule(module).recordActivity(safe);
    }
    
    /**
     * @notice Example 10: Emergency Controls
     * @dev Demonstrates emergency stop functionality
     */
    function emergencyStop(address safe, address module) external {
        // Activate emergency stop
        InheritanceModule(module).toggleEmergencyStop(safe, true);
        
        // Later, deactivate emergency stop
        // InheritanceModule(module).toggleEmergencyStop(safe, false);
    }
    
    /**
     * @notice Helper function to check inheritance status
     * @dev Utility function to check if inheritance can be executed
     */
    function checkInheritanceStatus(
        address module,
        address safe,
        address beneficiary
    ) external view returns (
        bool canExecute,
        string memory reason,
        uint256 timeRemaining,
        uint256 share
    ) {
        InheritanceModule inheritanceModule = InheritanceModule(module);
        
        (canExecute, reason) = inheritanceModule.canExecuteInheritance(safe, beneficiary);
        timeRemaining = inheritanceModule.getTimeUntilInheritance(safe);
        (, share) = inheritanceModule.isBeneficiary(safe, beneficiary);
    }
    
    /**
     * @notice Helper function to get inheritance configuration
     * @dev Utility function to retrieve inheritance settings
     */
    function getInheritanceInfo(
        address module,
        address safe
    ) external view returns (
        IInheritanceModule.InheritanceConfig memory config,
        IInheritanceModule.Beneficiary[] memory beneficiaries
    ) {
        InheritanceModule inheritanceModule = InheritanceModule(module);
        
        config = inheritanceModule.getInheritanceConfig(safe);
        beneficiaries = inheritanceModule.getBeneficiaries(safe);
    }
}
