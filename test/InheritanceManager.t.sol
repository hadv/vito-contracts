// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {InheritanceManager} from "../src/InheritanceManager.sol";
import {InheritanceModule} from "../src/InheritanceModule.sol";
import {IInheritanceManager} from "../src/interfaces/IInheritanceManager.sol";

contract MockSafeManager {
    mapping(address => bool) public owners;
    mapping(address => bool) public modules;
    address[] public modulesList;

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
        modulesList.push(module);
    }

    function disableModule(address prevModule, address module) external {
        modules[module] = false;
        // Remove from list (simplified)
        for (uint256 i = 0; i < modulesList.length; i++) {
            if (modulesList[i] == module) {
                modulesList[i] = modulesList[modulesList.length - 1];
                modulesList.pop();
                break;
            }
        }
    }

    function isModuleEnabled(address module) external view returns (bool) {
        return modules[module];
    }

    function getModulesPaginated(address start, uint256 pageSize)
        external
        view
        returns (address[] memory array, address next)
    {
        // Simplified implementation
        array = new address[](modulesList.length);
        for (uint256 i = 0; i < modulesList.length; i++) {
            array[i] = modulesList[i];
        }
        next = address(0x1); // SENTINEL_MODULES
    }
}

contract InheritanceManagerTest is Test {
    InheritanceManager public inheritanceManager;
    InheritanceModule public inheritanceModuleTemplate;
    MockSafeManager public safe1;
    MockSafeManager public safe2;

    address public owner1;
    address public owner2;
    address public beneficiary1;
    address public beneficiary2;
    address public oracle;

    // Test constants
    uint256 constant INACTIVITY_PERIOD = 180 days;
    uint256 constant COOLDOWN_PERIOD = 7 days;
    uint256 constant BENEFICIARY_SHARE = 10000; // 100%

    event InheritanceModuleDeployed(address indexed safe, address indexed module, address indexed owner);

    event InheritanceModuleEnabled(address indexed safe, address indexed module);

    event GlobalSettingsUpdated(
        uint256 minInactivityPeriod, uint256 maxInactivityPeriod, uint256 defaultCooldownPeriod
    );

    function setUp() public {
        // Setup addresses
        owner1 = makeAddr("owner1");
        owner2 = makeAddr("owner2");
        beneficiary1 = makeAddr("beneficiary1");
        beneficiary2 = makeAddr("beneficiary2");
        oracle = makeAddr("oracle");

        // Deploy template
        inheritanceModuleTemplate = new InheritanceModule(address(this));

        // Deploy manager
        inheritanceManager = new InheritanceManager(address(inheritanceModuleTemplate));

        // Deploy mock safes
        address[] memory owners1 = new address[](1);
        owners1[0] = owner1;
        safe1 = new MockSafeManager(owners1);

        address[] memory owners2 = new address[](1);
        owners2[0] = owner2;
        safe2 = new MockSafeManager(owners2);
    }

    function test_DeployInheritanceModule() public {
        // Calls must be made by the Safe or registry per onlySafeOrRegistry
        vm.prank(address(safe1));
        // Do not assert module address (unknown before call)
        vm.expectEmit(true, false, true, true);
        emit InheritanceModuleDeployed(address(safe1), address(0), address(safe1));

        address module = inheritanceManager.deployInheritanceModule(
            address(safe1), INACTIVITY_PERIOD, COOLDOWN_PERIOD, false, address(0)
        );

        assertNotEq(module, address(0));
        assertEq(inheritanceManager.getInheritanceModule(address(safe1)), module);
    }

    function test_DeployInheritanceModule_AlreadyExists() public {
        // Deploy first module
        vm.prank(address(safe1));
        inheritanceManager.deployInheritanceModule(
            address(safe1), INACTIVITY_PERIOD, COOLDOWN_PERIOD, false, address(0)
        );

        // Try to deploy second module for same safe
        vm.prank(address(safe1));
        vm.expectRevert(abi.encodeWithSignature("ModuleAlreadyExists()"));
        inheritanceManager.deployInheritanceModule(
            address(safe1), INACTIVITY_PERIOD, COOLDOWN_PERIOD, false, address(0)
        );
    }

    function test_DeployInheritanceModule_InvalidPeriod() public {
        vm.prank(address(safe1));
        vm.expectRevert(abi.encodeWithSignature("InvalidPeriodRange()"));
        inheritanceManager.deployInheritanceModule(address(safe1), 1 days, COOLDOWN_PERIOD, false, address(0));
    }

    function test_DeployInheritanceModule_WithOracle() public {
        // Register oracle first
        inheritanceManager.registerOracle(oracle, true);

        vm.prank(owner1);
        address module =
            inheritanceManager.deployInheritanceModule(address(safe1), INACTIVITY_PERIOD, COOLDOWN_PERIOD, true, oracle);

        assertNotEq(module, address(0));
    }

    function test_DeployInheritanceModule_UnauthorizedOracle() public {
        vm.prank(address(safe1));
        vm.expectRevert(abi.encodeWithSignature("UnauthorizedOracle()"));
        inheritanceManager.deployInheritanceModule(address(safe1), INACTIVITY_PERIOD, COOLDOWN_PERIOD, true, oracle);
    }

    function test_EnableInheritanceModule() public {
        // Deploy module first (call as Safe)
        vm.prank(address(safe1));
        address module = inheritanceManager.deployInheritanceModule(
            address(safe1), INACTIVITY_PERIOD, COOLDOWN_PERIOD, false, address(0)
        );

        // Enable module (call as Safe)
        vm.prank(address(safe1));
        vm.expectEmit(true, true, false, true);
        emit InheritanceModuleEnabled(address(safe1), module);

        inheritanceManager.enableInheritanceModule(address(safe1), module);

        assertTrue(safe1.isModuleEnabled(module));
    }

    function test_EnableInheritanceModule_ModuleNotFound() public {
        address fakeModule = makeAddr("fakeModule");

        vm.prank(address(safe1));
        vm.expectRevert(abi.encodeWithSignature("ModuleNotFound()"));
        inheritanceManager.enableInheritanceModule(address(safe1), fakeModule);
    }

    function test_DisableInheritanceModule() public {
        // Deploy and enable module first (call as Safe)
        vm.prank(address(safe1));
        address module = inheritanceManager.deployInheritanceModule(
            address(safe1), INACTIVITY_PERIOD, COOLDOWN_PERIOD, false, address(0)
        );

        vm.prank(address(safe1));
        inheritanceManager.enableInheritanceModule(address(safe1), module);

        // Disable module (call as Safe)
        vm.prank(address(safe1));
        inheritanceManager.disableInheritanceModule(address(safe1), module);

        assertFalse(safe1.isModuleEnabled(module));
    }

    function test_BatchAddBeneficiaries() public {
        // Deploy modules for both safes (call as each Safe)
        vm.prank(address(safe1));
        address module1 = inheritanceManager.deployInheritanceModule(
            address(safe1), INACTIVITY_PERIOD, COOLDOWN_PERIOD, false, address(0)
        );

        vm.prank(address(safe2));
        address module2 = inheritanceManager.deployInheritanceModule(
            address(safe2), INACTIVITY_PERIOD, COOLDOWN_PERIOD, false, address(0)
        );

        // Prepare batch data
        address[] memory safes = new address[](2);
        safes[0] = address(safe1);
        safes[1] = address(safe2);

        address[] memory beneficiaries = new address[](2);
        beneficiaries[0] = beneficiary1;
        beneficiaries[1] = beneficiary2;

        uint256[] memory shares = new uint256[](2);
        shares[0] = BENEFICIARY_SHARE;
        shares[1] = BENEFICIARY_SHARE;

        // Execute batch operation
        inheritanceManager.batchAddBeneficiaries(safes, beneficiaries, shares);

        // Verify beneficiaries were added
        assertGt(inheritanceManager.totalBeneficiaries(), 0);
    }

    function test_RegisterOracle() public {
        inheritanceManager.registerOracle(oracle, true);
        assertTrue(inheritanceManager.isTrustedOracle(oracle));

        inheritanceManager.registerOracle(oracle, false);
        assertFalse(inheritanceManager.isTrustedOracle(oracle));
    }

    function test_RegisterOracle_OnlyOwner() public {
        vm.prank(owner1);
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", owner1));
        inheritanceManager.registerOracle(oracle, true);
    }

    function test_UpdateGlobalSettings() public {
        uint256 newMinPeriod = 60 days;
        uint256 newMaxPeriod = 5 * 365 days;
        uint256 newCooldown = 14 days;

        vm.expectEmit(false, false, false, true);
        emit GlobalSettingsUpdated(newMinPeriod, newMaxPeriod, newCooldown);

        inheritanceManager.updateGlobalSettings(newMinPeriod, newMaxPeriod, newCooldown);

        (uint256 minPeriod, uint256 maxPeriod, uint256 cooldown) = inheritanceManager.getGlobalSettings();

        assertEq(minPeriod, newMinPeriod);
        assertEq(maxPeriod, newMaxPeriod);
        assertEq(cooldown, newCooldown);
    }

    function test_UpdateGlobalSettings_InvalidRange() public {
        vm.expectRevert(abi.encodeWithSignature("InvalidPeriodRange()"));
        inheritanceManager.updateGlobalSettings(
            365 days, // min
            180 days, // max (less than min)
            14 days
        );
    }

    function test_GetAllInheritanceSafes() public {
        // Deploy modules for both safes
        vm.prank(owner1);
        inheritanceManager.deployInheritanceModule(
            address(safe1), INACTIVITY_PERIOD, COOLDOWN_PERIOD, false, address(0)
        );

        vm.prank(owner2);
        inheritanceManager.deployInheritanceModule(
            address(safe2), INACTIVITY_PERIOD, COOLDOWN_PERIOD, false, address(0)
        );

        address[] memory safes = inheritanceManager.getAllInheritanceSafes();
        assertEq(safes.length, 2);
        assertEq(safes[0], address(safe1));
        assertEq(safes[1], address(safe2));
    }

    function test_GetInheritanceStats() public {
        // Deploy module
        vm.prank(owner1);
        inheritanceManager.deployInheritanceModule(
            address(safe1), INACTIVITY_PERIOD, COOLDOWN_PERIOD, false, address(0)
        );

        (uint256 totalSafes, uint256 totalBeneficiaries, uint256 totalExecutions) =
            inheritanceManager.getInheritanceStats();

        assertEq(totalSafes, 1);
        assertEq(totalBeneficiaries, 0); // No beneficiaries added yet
        assertEq(totalExecutions, 0); // No executions yet
    }

    function test_GetInheritanceModule() public {
        // Initially should return zero address
        assertEq(inheritanceManager.getInheritanceModule(address(safe1)), address(0));

        // Deploy module
        vm.prank(owner1);
        address module = inheritanceManager.deployInheritanceModule(
            address(safe1), INACTIVITY_PERIOD, COOLDOWN_PERIOD, false, address(0)
        );

        // Should now return the module address
        assertEq(inheritanceManager.getInheritanceModule(address(safe1)), module);
    }

    function test_IsTrustedOracle() public {
        // Initially should be false
        assertFalse(inheritanceManager.isTrustedOracle(oracle));

        // Register oracle
        inheritanceManager.registerOracle(oracle, true);
        assertTrue(inheritanceManager.isTrustedOracle(oracle));

        // Unregister oracle
        inheritanceManager.registerOracle(oracle, false);
        assertFalse(inheritanceManager.isTrustedOracle(oracle));
    }
}
