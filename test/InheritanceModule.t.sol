// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {InheritanceModule} from "../src/InheritanceModule.sol";
import {InheritanceManager} from "../src/InheritanceManager.sol";
import {IInheritanceModule} from "../src/interfaces/IInheritanceModule.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract MockSafe {
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

    function execTransactionFromModule(address to, uint256 value, bytes memory data, uint8 operation)
        external
        returns (bool success)
    {
        // Mock implementation - just return true
        return true;
    }

    receive() external payable {}
}

contract InheritanceModuleTest is Test {
    InheritanceModule public inheritanceModule;
    InheritanceManager public inheritanceManager;
    MockSafe public safe;
    MockERC20 public token;

    address public owner;
    address public beneficiary1;
    address public beneficiary2;
    address public nonOwner;
    address public manager;

    // Test constants
    uint256 constant INACTIVITY_PERIOD = 180 days;
    uint256 constant COOLDOWN_PERIOD = 7 days;
    uint256 constant BENEFICIARY1_SHARE = 6000; // 60%
    uint256 constant BENEFICIARY2_SHARE = 4000; // 40%

    event InheritanceConfigured(address indexed safe, address indexed owner, uint256 inactivityPeriod);

    event BeneficiaryAdded(address indexed safe, address indexed beneficiary, uint256 share);

    event InheritanceExecuted(address indexed safe, address indexed beneficiary, address indexed executor);

    function setUp() public {
        // Setup addresses
        owner = makeAddr("owner");
        beneficiary1 = makeAddr("beneficiary1");
        beneficiary2 = makeAddr("beneficiary2");
        nonOwner = makeAddr("nonOwner");
        manager = makeAddr("manager");

        // Deploy mock contracts
        address[] memory owners = new address[](1);
        owners[0] = owner;
        safe = new MockSafe(owners);
        token = new MockERC20("Test Token", "TEST", 18, 0);

        // Deploy inheritance contracts
        inheritanceModule = new InheritanceModule(manager);

        // Fund the safe with ETH and tokens
        vm.deal(address(safe), 10 ether);
        token.mint(address(safe), 1000e18);
    }

    function test_ConfigureInheritance() public {
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit InheritanceConfigured(address(safe), owner, INACTIVITY_PERIOD);

        inheritanceModule.configureInheritance(address(safe), INACTIVITY_PERIOD, COOLDOWN_PERIOD, false, address(0));

        IInheritanceModule.InheritanceConfig memory config = inheritanceModule.getInheritanceConfig(address(safe));

        assertEq(config.owner, owner);
        assertTrue(config.isActive);
        assertEq(config.inactivityPeriod, INACTIVITY_PERIOD);
        assertEq(config.cooldownPeriod, COOLDOWN_PERIOD);
        assertFalse(config.requiresOracle);
        assertEq(config.oracleAddress, address(0));
        assertFalse(config.emergencyStop);
    }

    function test_ConfigureInheritance_OnlyOwner() public {
        vm.prank(nonOwner);
        vm.expectRevert("Not a Safe owner");

        inheritanceModule.configureInheritance(address(safe), INACTIVITY_PERIOD, COOLDOWN_PERIOD, false, address(0));
    }

    function test_ConfigureInheritance_InvalidPeriods() public {
        // Test invalid inactivity period (too short)
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("InvalidInactivityPeriod()"));
        inheritanceModule.configureInheritance(
            address(safe),
            1 days, // Too short
            COOLDOWN_PERIOD,
            false,
            address(0)
        );

        // Test invalid cooldown period (too short)
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("InvalidCooldownPeriod()"));
        inheritanceModule.configureInheritance(
            address(safe),
            INACTIVITY_PERIOD,
            1 days, // Too short
            false,
            address(0)
        );
    }

    function test_AddBeneficiary() public {
        // First configure inheritance
        vm.prank(owner);
        inheritanceModule.configureInheritance(address(safe), INACTIVITY_PERIOD, COOLDOWN_PERIOD, false, address(0));

        // Add beneficiary
        vm.prank(owner);
        vm.expectEmit(true, true, false, true);
        emit BeneficiaryAdded(address(safe), beneficiary1, BENEFICIARY1_SHARE);

        inheritanceModule.addBeneficiary(address(safe), beneficiary1, BENEFICIARY1_SHARE);

        // Verify beneficiary was added
        (bool isBeneficiary, uint256 share) = inheritanceModule.isBeneficiary(address(safe), beneficiary1);
        assertTrue(isBeneficiary);
        assertEq(share, BENEFICIARY1_SHARE);
    }

    function test_AddBeneficiary_InvalidShare() public {
        vm.prank(owner);
        inheritanceModule.configureInheritance(address(safe), INACTIVITY_PERIOD, COOLDOWN_PERIOD, false, address(0));

        // Test zero share
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("InvalidShare()"));
        inheritanceModule.addBeneficiary(address(safe), beneficiary1, 0);

        // Test share > 100%
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("InvalidShare()"));
        inheritanceModule.addBeneficiary(address(safe), beneficiary1, 10001);
    }

    function test_AddBeneficiary_SharesExceedMaximum() public {
        vm.prank(owner);
        inheritanceModule.configureInheritance(address(safe), INACTIVITY_PERIOD, COOLDOWN_PERIOD, false, address(0));

        // Add first beneficiary with 60%
        vm.prank(owner);
        inheritanceModule.addBeneficiary(address(safe), beneficiary1, 6000);

        // Try to add second beneficiary with 50% (total would be 110%)
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSignature("SharesExceedMaximum()"));
        inheritanceModule.addBeneficiary(address(safe), beneficiary2, 5000);
    }

    function test_RemoveBeneficiary() public {
        // Setup inheritance and add beneficiary
        vm.prank(owner);
        inheritanceModule.configureInheritance(address(safe), INACTIVITY_PERIOD, COOLDOWN_PERIOD, false, address(0));

        vm.prank(owner);
        inheritanceModule.addBeneficiary(address(safe), beneficiary1, BENEFICIARY1_SHARE);

        // Remove beneficiary
        vm.prank(owner);
        inheritanceModule.removeBeneficiary(address(safe), beneficiary1);

        // Verify beneficiary was removed
        (bool isBeneficiary,) = inheritanceModule.isBeneficiary(address(safe), beneficiary1);
        assertFalse(isBeneficiary);
    }

    function test_UpdateBeneficiaryShare() public {
        // Setup inheritance and add beneficiary
        vm.prank(owner);
        inheritanceModule.configureInheritance(address(safe), INACTIVITY_PERIOD, COOLDOWN_PERIOD, false, address(0));

        vm.prank(owner);
        inheritanceModule.addBeneficiary(address(safe), beneficiary1, BENEFICIARY1_SHARE);

        // Update share
        uint256 newShare = 8000;
        vm.prank(owner);
        inheritanceModule.updateBeneficiaryShare(address(safe), beneficiary1, newShare);

        // Verify share was updated
        (, uint256 share) = inheritanceModule.isBeneficiary(address(safe), beneficiary1);
        assertEq(share, newShare);
    }

    function test_RecordActivity() public {
        // Setup inheritance
        vm.prank(owner);
        inheritanceModule.configureInheritance(address(safe), INACTIVITY_PERIOD, COOLDOWN_PERIOD, false, address(0));

        uint256 initialActivity = inheritanceModule.getInheritanceConfig(address(safe)).lastActivity;

        // Fast forward time
        vm.warp(block.timestamp + 1 days);

        // Record activity
        vm.prank(owner);
        inheritanceModule.recordActivity(address(safe));

        uint256 newActivity = inheritanceModule.getInheritanceConfig(address(safe)).lastActivity;
        assertGt(newActivity, initialActivity);
    }

    function test_CanExecuteInheritance() public {
        // Setup inheritance and beneficiary
        vm.prank(owner);
        inheritanceModule.configureInheritance(address(safe), INACTIVITY_PERIOD, COOLDOWN_PERIOD, false, address(0));

        vm.prank(owner);
        inheritanceModule.addBeneficiary(address(safe), beneficiary1, BENEFICIARY1_SHARE);

        // Should not be able to execute immediately
        (bool canExecute, string memory reason) = inheritanceModule.canExecuteInheritance(address(safe), beneficiary1);
        assertFalse(canExecute);
        assertEq(reason, "Inactivity period not met");

        // Fast forward past inactivity period
        vm.warp(block.timestamp + INACTIVITY_PERIOD + 1);

        // Should now be able to execute
        (canExecute, reason) = inheritanceModule.canExecuteInheritance(address(safe), beneficiary1);
        assertTrue(canExecute);
        assertEq(reason, "");
    }

    function test_GetTimeUntilInheritance() public {
        // Setup inheritance
        vm.prank(owner);
        inheritanceModule.configureInheritance(address(safe), INACTIVITY_PERIOD, COOLDOWN_PERIOD, false, address(0));

        uint256 timeRemaining = inheritanceModule.getTimeUntilInheritance(address(safe));
        assertEq(timeRemaining, INACTIVITY_PERIOD);

        // Fast forward halfway
        vm.warp(block.timestamp + INACTIVITY_PERIOD / 2);
        timeRemaining = inheritanceModule.getTimeUntilInheritance(address(safe));
        assertEq(timeRemaining, INACTIVITY_PERIOD / 2);

        // Fast forward past the period
        vm.warp(block.timestamp + INACTIVITY_PERIOD);
        timeRemaining = inheritanceModule.getTimeUntilInheritance(address(safe));
        assertEq(timeRemaining, 0);
    }

    function test_EmergencyStop() public {
        // Setup inheritance
        vm.prank(owner);
        inheritanceModule.configureInheritance(address(safe), INACTIVITY_PERIOD, COOLDOWN_PERIOD, false, address(0));

        // Activate emergency stop
        vm.prank(owner);
        inheritanceModule.toggleEmergencyStop(address(safe), true);

        IInheritanceModule.InheritanceConfig memory config = inheritanceModule.getInheritanceConfig(address(safe));
        assertTrue(config.emergencyStop);

        // Deactivate emergency stop
        vm.prank(owner);
        inheritanceModule.toggleEmergencyStop(address(safe), false);

        config = inheritanceModule.getInheritanceConfig(address(safe));
        assertFalse(config.emergencyStop);
    }

    function test_GetBeneficiaries() public {
        // Setup inheritance
        vm.prank(owner);
        inheritanceModule.configureInheritance(address(safe), INACTIVITY_PERIOD, COOLDOWN_PERIOD, false, address(0));

        // Add multiple beneficiaries
        vm.prank(owner);
        inheritanceModule.addBeneficiary(address(safe), beneficiary1, BENEFICIARY1_SHARE);

        vm.prank(owner);
        inheritanceModule.addBeneficiary(address(safe), beneficiary2, BENEFICIARY2_SHARE);

        // Get all beneficiaries
        IInheritanceModule.Beneficiary[] memory beneficiaries = inheritanceModule.getBeneficiaries(address(safe));

        assertEq(beneficiaries.length, 2);
        assertEq(beneficiaries[0].beneficiary, beneficiary1);
        assertEq(beneficiaries[0].share, BENEFICIARY1_SHARE);
        assertEq(beneficiaries[1].beneficiary, beneficiary2);
        assertEq(beneficiaries[1].share, BENEFICIARY2_SHARE);
    }
}
