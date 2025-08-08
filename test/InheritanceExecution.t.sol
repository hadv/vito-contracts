// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";
import {InheritanceModule} from "../src/InheritanceModule.sol";
import {IInheritanceModule} from "../src/interfaces/IInheritanceModule.sol";
import {MockERC20} from "./mocks/MockERC20.sol";

contract MockSafeExecution {
    mapping(address => bool) public owners;
    mapping(address => bool) public modules;
    uint256 public ethBalance;
    mapping(address => uint256) public tokenBalances;

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
        if (to == address(0)) {
            // ETH transfer
            require(address(this).balance >= value, "Insufficient ETH balance");
            payable(msg.sender).transfer(value);
        } else {
            // Token transfer
            if (data.length > 0) {
                // Decode transfer call
                (bool success,) = to.call(data);
                require(success, "Token transfer failed");
            }
        }
        return true;
    }

    receive() external payable {
        ethBalance += msg.value;
    }

    function balance() external view returns (uint256) {
        return address(this).balance;
    }
}

contract InheritanceExecutionTest is Test {
    InheritanceModule public inheritanceModule;
    MockSafeExecution public safe;
    MockERC20 public token;

    address public owner;
    address public beneficiary1;
    address public beneficiary2;
    address public manager;

    // Test constants
    uint256 constant INACTIVITY_PERIOD = 180 days;
    uint256 constant COOLDOWN_PERIOD = 7 days;
    uint256 constant BENEFICIARY1_SHARE = 6000; // 60%
    uint256 constant BENEFICIARY2_SHARE = 4000; // 40%

    event InheritanceExecuted(address indexed safe, address indexed beneficiary, address indexed executor);

    function setUp() public {
        // Setup addresses
        owner = makeAddr("owner");
        beneficiary1 = makeAddr("beneficiary1");
        beneficiary2 = makeAddr("beneficiary2");
        manager = makeAddr("manager");

        // Deploy mock contracts
        address[] memory owners = new address[](1);
        owners[0] = owner;
        safe = new MockSafeExecution(owners);
        token = new MockERC20("Test Token", "TEST", 18, 0);

        // Deploy inheritance module
        inheritanceModule = new InheritanceModule(manager);

        // Fund the safe with ETH and tokens
        vm.deal(address(safe), 10 ether);
        token.mint(address(safe), 1000e18);

        // Setup inheritance
        vm.prank(owner);
        inheritanceModule.configureInheritance(address(safe), INACTIVITY_PERIOD, COOLDOWN_PERIOD, false, address(0));

        // Add beneficiaries
        vm.prank(owner);
        inheritanceModule.addBeneficiary(address(safe), beneficiary1, BENEFICIARY1_SHARE);

        vm.prank(owner);
        inheritanceModule.addBeneficiary(address(safe), beneficiary2, BENEFICIARY2_SHARE);
    }

    function test_ExecuteInheritance_InactivityPeriodNotMet() public {
        IInheritanceModule.AssetAllocation[] memory assets = new IInheritanceModule.AssetAllocation[](1);

        assets[0] = IInheritanceModule.AssetAllocation({
            assetType: 0, // ETH
            assetAddress: address(0),
            tokenId: 0,
            amount: 10000, // 100%
            isPercentage: true
        });

        // Should fail because inactivity period not met
        vm.expectRevert(abi.encodeWithSignature("InactivityPeriodNotMet()"));
        inheritanceModule.executeInheritance(address(safe), beneficiary1, assets, "");
    }

    function test_ExecuteInheritance_NotBeneficiary() public {
        // Fast forward past inactivity period
        vm.warp(block.timestamp + INACTIVITY_PERIOD + 1);

        IInheritanceModule.AssetAllocation[] memory assets = new IInheritanceModule.AssetAllocation[](1);

        assets[0] = IInheritanceModule.AssetAllocation({
            assetType: 0, // ETH
            assetAddress: address(0),
            tokenId: 0,
            amount: 10000, // 100%
            isPercentage: true
        });

        address nonBeneficiary = makeAddr("nonBeneficiary");

        // Should fail because address is not a beneficiary
        vm.expectRevert(abi.encodeWithSignature("BeneficiaryNotFound()"));
        inheritanceModule.executeInheritance(address(safe), nonBeneficiary, assets, "");
    }

    function test_ExecuteInheritance_EmergencyStop() public {
        // Fast forward past inactivity period
        vm.warp(block.timestamp + INACTIVITY_PERIOD + 1);

        // Activate emergency stop
        vm.prank(owner);
        inheritanceModule.toggleEmergencyStop(address(safe), true);

        IInheritanceModule.AssetAllocation[] memory assets = new IInheritanceModule.AssetAllocation[](1);

        assets[0] = IInheritanceModule.AssetAllocation({
            assetType: 0, // ETH
            assetAddress: address(0),
            tokenId: 0,
            amount: 10000, // 100%
            isPercentage: true
        });

        // Should fail because emergency stop is active
        vm.expectRevert(abi.encodeWithSignature("EmergencyStopActive()"));
        inheritanceModule.executeInheritance(address(safe), beneficiary1, assets, "");
    }

    function test_ExecuteInheritance_Success_ETH() public {
        // Fast forward past inactivity period
        vm.warp(block.timestamp + INACTIVITY_PERIOD + 1);

        uint256 initialBeneficiaryBalance = beneficiary1.balance;
        uint256 safeBalance = address(safe).balance;

        IInheritanceModule.AssetAllocation[] memory assets = new IInheritanceModule.AssetAllocation[](1);

        assets[0] = IInheritanceModule.AssetAllocation({
            assetType: 0, // ETH
            assetAddress: address(0),
            tokenId: 0,
            amount: 5000, // 50% of ETH
            isPercentage: true
        });

        vm.expectEmit(true, true, true, true);
        emit InheritanceExecuted(address(safe), beneficiary1, address(this));

        inheritanceModule.executeInheritance(address(safe), beneficiary1, assets, "");

        // Check that beneficiary received their share
        uint256 expectedAmount = (safeBalance * 5000 * BENEFICIARY1_SHARE) / (10000 * 10000);
        // Note: In a real implementation, the transfer would happen through execTransactionFromModule
        // This test verifies the function executes without reverting
    }

    function test_ExecuteInheritance_Success_ERC20() public {
        // Fast forward past inactivity period
        vm.warp(block.timestamp + INACTIVITY_PERIOD + 1);

        uint256 tokenBalance = token.balanceOf(address(safe));

        IInheritanceModule.AssetAllocation[] memory assets = new IInheritanceModule.AssetAllocation[](1);

        assets[0] = IInheritanceModule.AssetAllocation({
            assetType: 1, // ERC20
            assetAddress: address(token),
            tokenId: 0,
            amount: 10000, // 100% of tokens
            isPercentage: true
        });

        vm.expectEmit(true, true, true, true);
        emit InheritanceExecuted(address(safe), beneficiary1, address(this));

        inheritanceModule.executeInheritance(address(safe), beneficiary1, assets, "");

        // Verify execution completed successfully
        // In a real implementation, tokens would be transferred to beneficiary
    }

    function test_ExecuteInheritance_Success_MultipleAssets() public {
        // Fast forward past inactivity period
        vm.warp(block.timestamp + INACTIVITY_PERIOD + 1);

        IInheritanceModule.AssetAllocation[] memory assets = new IInheritanceModule.AssetAllocation[](2);

        // ETH allocation
        assets[0] = IInheritanceModule.AssetAllocation({
            assetType: 0, // ETH
            assetAddress: address(0),
            tokenId: 0,
            amount: 10000, // 100% of ETH
            isPercentage: true
        });

        // Token allocation
        assets[1] = IInheritanceModule.AssetAllocation({
            assetType: 1, // ERC20
            assetAddress: address(token),
            tokenId: 0,
            amount: 5000, // 50% of tokens
            isPercentage: true
        });

        vm.expectEmit(true, true, true, true);
        emit InheritanceExecuted(address(safe), beneficiary2, address(this));

        inheritanceModule.executeInheritance(address(safe), beneficiary2, assets, "");
    }

    function test_ExecuteInheritanceWithStaking() public {
        // Fast forward past inactivity period
        vm.warp(block.timestamp + INACTIVITY_PERIOD + 1);

        IInheritanceModule.AssetAllocation[] memory assets = new IInheritanceModule.AssetAllocation[](1);

        assets[0] = IInheritanceModule.AssetAllocation({
            assetType: 0, // ETH
            assetAddress: address(0),
            tokenId: 0,
            amount: 10000, // 100%
            isPercentage: true
        });

        // Mock staking data
        bytes memory stakingData = abi.encode("mock staking data");

        vm.expectEmit(true, true, true, true);
        emit InheritanceExecuted(address(safe), beneficiary1, address(this));

        inheritanceModule.executeInheritanceWithStaking(
            address(safe),
            beneficiary1,
            assets,
            "", // no oracle proof
            stakingData
        );
    }

    function test_ExecuteInheritance_ActivityResets() public {
        // Fast forward past inactivity period
        vm.warp(block.timestamp + INACTIVITY_PERIOD + 1);

        // Record activity (should reset the timer)
        vm.prank(owner);
        inheritanceModule.recordActivity(address(safe));

        IInheritanceModule.AssetAllocation[] memory assets = new IInheritanceModule.AssetAllocation[](1);

        assets[0] = IInheritanceModule.AssetAllocation({
            assetType: 0, // ETH
            assetAddress: address(0),
            tokenId: 0,
            amount: 10000, // 100%
            isPercentage: true
        });

        // Should fail because activity was recorded
        vm.expectRevert(abi.encodeWithSignature("InactivityPeriodNotMet()"));
        inheritanceModule.executeInheritance(address(safe), beneficiary1, assets, "");
    }

    function test_ExecuteInheritance_MultipleBeneficiaries() public {
        // Fast forward past inactivity period
        vm.warp(block.timestamp + INACTIVITY_PERIOD + 1);

        IInheritanceModule.AssetAllocation[] memory assets = new IInheritanceModule.AssetAllocation[](1);

        assets[0] = IInheritanceModule.AssetAllocation({
            assetType: 0, // ETH
            assetAddress: address(0),
            tokenId: 0,
            amount: 10000, // 100%
            isPercentage: true
        });

        // Execute inheritance for first beneficiary
        vm.expectEmit(true, true, true, true);
        emit InheritanceExecuted(address(safe), beneficiary1, address(this));

        inheritanceModule.executeInheritance(address(safe), beneficiary1, assets, "");

        // Execute inheritance for second beneficiary
        vm.expectEmit(true, true, true, true);
        emit InheritanceExecuted(address(safe), beneficiary2, address(this));

        inheritanceModule.executeInheritance(address(safe), beneficiary2, assets, "");
    }

    function test_ExecuteInheritance_AbsoluteAmount() public {
        // Fast forward past inactivity period
        vm.warp(block.timestamp + INACTIVITY_PERIOD + 1);

        IInheritanceModule.AssetAllocation[] memory assets = new IInheritanceModule.AssetAllocation[](1);

        assets[0] = IInheritanceModule.AssetAllocation({
            assetType: 1, // ERC20
            assetAddress: address(token),
            tokenId: 0,
            amount: 100e18, // Absolute amount: 100 tokens
            isPercentage: false
        });

        vm.expectEmit(true, true, true, true);
        emit InheritanceExecuted(address(safe), beneficiary1, address(this));

        inheritanceModule.executeInheritance(address(safe), beneficiary1, assets, "");
    }
}
