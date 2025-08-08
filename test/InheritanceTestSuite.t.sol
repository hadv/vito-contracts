// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {InheritanceModule} from "../src/InheritanceModule.sol";
import {InheritanceManager} from "../src/InheritanceManager.sol";
import {StakedAssetHandler} from "../src/StakedAssetHandler.sol";
import {IInheritanceModule} from "../src/interfaces/IInheritanceModule.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

// Mock Safe that can execute transactions
contract MockSafeIntegration {
    mapping(address => bool) public owners;
    mapping(address => bool) public modules;

    constructor(address[] memory _owners) {
        for (uint256 i = 0; i < _owners.length; i++) {
            owners[_owners[i]] = true;
        }
    }

    function isOwner(address owner) external view returns (bool) {
        return owners[owner];
    }

    function enableModule(address module) external {
        modules[module] = true;
    }

    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes memory data,
        uint8 operation
    ) external returns (bool success) {
        if (to == address(0)) {
            // ETH transfer
            if (value > 0) {
                (bool sent,) = payable(msg.sender).call{value: value}("");
                return sent;
            }
        }
        return true;
    }

    receive() external payable {}
}

/**
 * @title InheritanceTestSuite
 * @notice Comprehensive integration tests for the inheritance system
 * @dev Tests the complete inheritance flow from setup to execution
 */
contract InheritanceTestSuite is Test {
    InheritanceModule public inheritanceModule;
    InheritanceManager public inheritanceManager;
    StakedAssetHandler public stakedAssetHandler;
    MockERC20 public token;
    MockSafeIntegration public safe;
    
    address public owner;
    address public beneficiary1;
    address public beneficiary2;
    address public manager;
    
    // Test constants
    uint256 constant INACTIVITY_PERIOD = 180 days;
    uint256 constant COOLDOWN_PERIOD = 7 days;
    uint256 constant BENEFICIARY1_SHARE = 6000; // 60%
    uint256 constant BENEFICIARY2_SHARE = 4000; // 40%

    function setUp() public {
        // Setup addresses
        owner = makeAddr("owner");
        beneficiary1 = makeAddr("beneficiary1");
        beneficiary2 = makeAddr("beneficiary2");
        manager = makeAddr("manager");
        
        // Deploy mock safe
        address[] memory owners = new address[](1);
        owners[0] = owner;
        safe = new MockSafeIntegration(owners);
        
        // Deploy token
        token = new MockERC20("Test Token", "TEST", 18, 0);
        
        // Deploy inheritance system
        inheritanceModule = new InheritanceModule(manager);
        inheritanceManager = new InheritanceManager(address(inheritanceModule));
        stakedAssetHandler = new StakedAssetHandler();
        
        // Fund the safe
        vm.deal(address(safe), 10 ether);
        token.mint(address(safe), 1000e18);
        
        // Connect staked asset handler to inheritance module
        vm.prank(manager);
        inheritanceModule.setStakedAssetHandler(address(stakedAssetHandler));
    }

    function test_CompleteInheritanceFlow() public {
        // Step 1: Deploy inheritance module through manager
        vm.prank(owner);
        address module = inheritanceManager.deployInheritanceModule(
            address(safe),
            INACTIVITY_PERIOD,
            COOLDOWN_PERIOD,
            false,
            address(0)
        );
        
        assertEq(module, address(inheritanceModule));
        
        // Step 2: Enable module on Safe
        vm.prank(owner);
        inheritanceManager.enableInheritanceModule(address(safe), module);
        
        assertTrue(safe.modules(module));
        
        // Step 3: Add beneficiaries
        vm.prank(owner);
        inheritanceModule.addBeneficiary(address(safe), beneficiary1, BENEFICIARY1_SHARE);
        
        vm.prank(owner);
        inheritanceModule.addBeneficiary(address(safe), beneficiary2, BENEFICIARY2_SHARE);
        
        // Verify beneficiaries
        (bool isBen1, uint256 share1) = inheritanceModule.isBeneficiary(address(safe), beneficiary1);
        (bool isBen2, uint256 share2) = inheritanceModule.isBeneficiary(address(safe), beneficiary2);
        
        assertTrue(isBen1);
        assertTrue(isBen2);
        assertEq(share1, BENEFICIARY1_SHARE);
        assertEq(share2, BENEFICIARY2_SHARE);
        
        // Step 4: Fast forward past inactivity period
        vm.warp(block.timestamp + INACTIVITY_PERIOD + 1);
        
        // Step 5: Execute inheritance
        IInheritanceModule.AssetAllocation[] memory assets = 
            new IInheritanceModule.AssetAllocation[](2);
        
        // ETH allocation
        assets[0] = IInheritanceModule.AssetAllocation({
            assetType: 0,
            assetAddress: address(0),
            tokenId: 0,
            amount: 10000, // 100%
            isPercentage: true
        });
        
        // Token allocation
        assets[1] = IInheritanceModule.AssetAllocation({
            assetType: 1,
            assetAddress: address(token),
            tokenId: 0,
            amount: 10000, // 100%
            isPercentage: true
        });
        
        uint256 initialBeneficiary1Balance = beneficiary1.balance;
        
        inheritanceModule.executeInheritance(
            address(safe),
            beneficiary1,
            assets,
            ""
        );
        
        // Verify execution completed (in mock, actual transfers would happen)
        // The mock safe doesn't actually transfer, but the function should complete
    }

    function test_InheritanceWithActivityReset() public {
        // Setup inheritance
        vm.prank(owner);
        inheritanceModule.configureInheritance(
            address(safe),
            INACTIVITY_PERIOD,
            COOLDOWN_PERIOD,
            false,
            address(0)
        );
        
        vm.prank(owner);
        inheritanceModule.addBeneficiary(address(safe), beneficiary1, 10000);
        
        // Fast forward halfway through inactivity period
        vm.warp(block.timestamp + INACTIVITY_PERIOD / 2);
        
        // Record activity (resets timer)
        vm.prank(owner);
        inheritanceModule.recordActivity(address(safe));
        
        // Fast forward another half period (should not be enough now)
        vm.warp(block.timestamp + INACTIVITY_PERIOD / 2);
        
        IInheritanceModule.AssetAllocation[] memory assets = 
            new IInheritanceModule.AssetAllocation[](1);
        
        assets[0] = IInheritanceModule.AssetAllocation({
            assetType: 0,
            assetAddress: address(0),
            tokenId: 0,
            amount: 10000,
            isPercentage: true
        });
        
        // Should fail because activity was recorded
        vm.expectRevert(abi.encodeWithSignature("InactivityPeriodNotMet()"));
        inheritanceModule.executeInheritance(
            address(safe),
            beneficiary1,
            assets,
            ""
        );
        
        // Fast forward full period from activity reset
        vm.warp(block.timestamp + INACTIVITY_PERIOD + 1);
        
        // Should now succeed
        inheritanceModule.executeInheritance(
            address(safe),
            beneficiary1,
            assets,
            ""
        );
    }

    function test_EmergencyStopFlow() public {
        // Setup inheritance
        vm.prank(owner);
        inheritanceModule.configureInheritance(
            address(safe),
            INACTIVITY_PERIOD,
            COOLDOWN_PERIOD,
            false,
            address(0)
        );
        
        vm.prank(owner);
        inheritanceModule.addBeneficiary(address(safe), beneficiary1, 10000);
        
        // Fast forward past inactivity period
        vm.warp(block.timestamp + INACTIVITY_PERIOD + 1);
        
        // Activate emergency stop
        vm.prank(owner);
        inheritanceModule.toggleEmergencyStop(address(safe), true);
        
        IInheritanceModule.AssetAllocation[] memory assets = 
            new IInheritanceModule.AssetAllocation[](1);
        
        assets[0] = IInheritanceModule.AssetAllocation({
            assetType: 0,
            assetAddress: address(0),
            tokenId: 0,
            amount: 10000,
            isPercentage: true
        });
        
        // Should fail due to emergency stop
        vm.expectRevert(abi.encodeWithSignature("EmergencyStopActive()"));
        inheritanceModule.executeInheritance(
            address(safe),
            beneficiary1,
            assets,
            ""
        );
        
        // Deactivate emergency stop
        vm.prank(owner);
        inheritanceModule.toggleEmergencyStop(address(safe), false);
        
        // Should now succeed
        inheritanceModule.executeInheritance(
            address(safe),
            beneficiary1,
            assets,
            ""
        );
    }

    function test_MultipleBeneficiaryExecution() public {
        // Setup inheritance
        vm.prank(owner);
        inheritanceModule.configureInheritance(
            address(safe),
            INACTIVITY_PERIOD,
            COOLDOWN_PERIOD,
            false,
            address(0)
        );
        
        vm.prank(owner);
        inheritanceModule.addBeneficiary(address(safe), beneficiary1, BENEFICIARY1_SHARE);
        
        vm.prank(owner);
        inheritanceModule.addBeneficiary(address(safe), beneficiary2, BENEFICIARY2_SHARE);
        
        // Fast forward past inactivity period
        vm.warp(block.timestamp + INACTIVITY_PERIOD + 1);
        
        IInheritanceModule.AssetAllocation[] memory assets = 
            new IInheritanceModule.AssetAllocation[](1);
        
        assets[0] = IInheritanceModule.AssetAllocation({
            assetType: 0,
            assetAddress: address(0),
            tokenId: 0,
            amount: 10000,
            isPercentage: true
        });
        
        // Execute for first beneficiary
        inheritanceModule.executeInheritance(
            address(safe),
            beneficiary1,
            assets,
            ""
        );
        
        // Execute for second beneficiary
        inheritanceModule.executeInheritance(
            address(safe),
            beneficiary2,
            assets,
            ""
        );
        
        // Both executions should succeed
    }

    function test_BeneficiaryManagement() public {
        // Setup inheritance
        vm.prank(owner);
        inheritanceModule.configureInheritance(
            address(safe),
            INACTIVITY_PERIOD,
            COOLDOWN_PERIOD,
            false,
            address(0)
        );
        
        // Add beneficiary
        vm.prank(owner);
        inheritanceModule.addBeneficiary(address(safe), beneficiary1, 5000);
        
        // Update share
        vm.prank(owner);
        inheritanceModule.updateBeneficiaryShare(address(safe), beneficiary1, 7000);
        
        (, uint256 share) = inheritanceModule.isBeneficiary(address(safe), beneficiary1);
        assertEq(share, 7000);
        
        // Add second beneficiary
        vm.prank(owner);
        inheritanceModule.addBeneficiary(address(safe), beneficiary2, 3000);
        
        // Remove first beneficiary
        vm.prank(owner);
        inheritanceModule.removeBeneficiary(address(safe), beneficiary1);
        
        (bool isBen1,) = inheritanceModule.isBeneficiary(address(safe), beneficiary1);
        (bool isBen2,) = inheritanceModule.isBeneficiary(address(safe), beneficiary2);
        
        assertFalse(isBen1);
        assertTrue(isBen2);
    }

    function test_ConfigurationCooldown() public {
        // Initial configuration
        vm.prank(owner);
        inheritanceModule.configureInheritance(
            address(safe),
            INACTIVITY_PERIOD,
            COOLDOWN_PERIOD,
            false,
            address(0)
        );
        
        // Try to reconfigure immediately (should fail)
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("CooldownPeriodNotMet()"));
        inheritanceModule.configureInheritance(
            address(safe),
            INACTIVITY_PERIOD + 30 days,
            COOLDOWN_PERIOD,
            false,
            address(0)
        );
        
        // Fast forward past cooldown period
        vm.warp(block.timestamp + COOLDOWN_PERIOD + 1);
        
        // Should now succeed
        vm.prank(owner);
        inheritanceModule.configureInheritance(
            address(safe),
            INACTIVITY_PERIOD + 30 days,
            COOLDOWN_PERIOD,
            false,
            address(0)
        );
        
        IInheritanceModule.InheritanceConfig memory config = 
            inheritanceModule.getInheritanceConfig(address(safe));
        assertEq(config.inactivityPeriod, INACTIVITY_PERIOD + 30 days);
    }
}
