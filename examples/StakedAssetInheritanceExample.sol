// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../src/InheritanceModule.sol";
import "../src/StakedAssetHandler.sol";
import "../src/handlers/LidoStakingHandler.sol";
import "../src/handlers/CompoundHandler.sol";

/**
 * @title StakedAssetInheritanceExample
 * @notice Examples for handling staked assets in inheritance
 * @dev Demonstrates various DeFi protocol integrations
 */
contract StakedAssetInheritanceExample {
    
    InheritanceModule public inheritanceModule;
    StakedAssetHandler public stakedAssetHandler;
    LidoStakingHandler public lidoHandler;
    CompoundHandler public compoundHandler;
    
    // Example addresses
    address public constant EXAMPLE_SAFE = 0x1234567890123456789012345678901234567890;
    address public constant BENEFICIARY = 0x2345678901234567890123456789012345678901;
    
    // Protocol addresses (mainnet)
    address public constant LIDO_STETH = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public constant COMPOUND_CETH = 0x4Ddc2D193948926D02f9B1fE9e1daa0718270ED5;
    address public constant COMPOUND_CDAI = 0x5d3a536E4D6DbD6114cc1Ead35777bAB948E3643;
    
    constructor(
        address _inheritanceModule,
        address _stakedAssetHandler,
        address _lidoHandler,
        address _compoundHandler
    ) {
        inheritanceModule = InheritanceModule(_inheritanceModule);
        stakedAssetHandler = StakedAssetHandler(_stakedAssetHandler);
        lidoHandler = LidoStakingHandler(_lidoHandler);
        compoundHandler = CompoundHandler(_compoundHandler);
    }
    
    /**
     * @notice Example 1: Lido stETH Inheritance
     * @dev Shows how to handle Lido liquid staking tokens
     */
    function example1_LidoStETHInheritance() external {
        // Strategy 1: Transfer stETH directly (liquid staking tokens are transferable)
        address[] memory protocols = new address[](1);
        protocols[0] = LIDO_STETH;
        
        uint8[] memory strategies = new uint8[](1);
        strategies[0] = 0; // Transfer receipt tokens
        
        bytes[] memory protocolData = new bytes[](1);
        protocolData[0] = ""; // No additional data needed for stETH transfer
        
        // Execute inheritance with staked assets
        inheritanceModule.executeInheritanceWithStaking(
            EXAMPLE_SAFE,
            BENEFICIARY,
            new IInheritanceModule.AssetAllocation[](0), // No regular assets
            "", // No oracle proof
            protocols,
            strategies,
            protocolData
        );
    }
    
    /**
     * @notice Example 2: Lido Withdrawal Queue
     * @dev Shows how to handle Lido withdrawal requests
     */
    function example2_LidoWithdrawalQueue() external {
        // Strategy 2: Initiate unbonding (withdrawal from Lido)
        address[] memory protocols = new address[](1);
        protocols[0] = LIDO_STETH;
        
        uint8[] memory strategies = new uint8[](1);
        strategies[0] = 1; // Initiate unbonding
        
        bytes[] memory protocolData = new bytes[](1);
        protocolData[0] = abi.encode(1000 ether); // Withdraw 1000 ETH worth
        
        // Execute inheritance with unbonding
        inheritanceModule.executeInheritanceWithStaking(
            EXAMPLE_SAFE,
            BENEFICIARY,
            new IInheritanceModule.AssetAllocation[](0),
            "",
            protocols,
            strategies,
            protocolData
        );
        
        // Later, complete the withdrawal when ready
        _completeWithdrawal();
    }
    
    /**
     * @notice Example 3: Compound cToken Inheritance
     * @dev Shows how to handle Compound lending positions
     */
    function example3_CompoundInheritance() external {
        // Multiple strategies for different cTokens
        address[] memory protocols = new address[](2);
        protocols[0] = COMPOUND_CETH;
        protocols[1] = COMPOUND_CDAI;
        
        uint8[] memory strategies = new uint8[](2);
        strategies[0] = 0; // Transfer cETH directly
        strategies[1] = 1; // Redeem DAI from cDAI
        
        bytes[] memory protocolData = new bytes[](2);
        // cETH transfer data
        protocolData[0] = abi.encode(CompoundHandler.CompoundData({
            cToken: COMPOUND_CETH,
            claimRewards: true,
            exitMarket: false
        }));
        
        // cDAI redemption data
        protocolData[1] = abi.encode(CompoundHandler.CompoundData({
            cToken: COMPOUND_CDAI,
            claimRewards: true,
            exitMarket: true
        }));
        
        inheritanceModule.executeInheritanceWithStaking(
            EXAMPLE_SAFE,
            BENEFICIARY,
            new IInheritanceModule.AssetAllocation[](0),
            "",
            protocols,
            strategies,
            protocolData
        );
    }
    
    /**
     * @notice Example 4: Mixed Asset Inheritance
     * @dev Shows inheritance of both regular and staked assets
     */
    function example4_MixedAssetInheritance() external {
        // Regular assets
        IInheritanceModule.AssetAllocation[] memory assets = 
            new IInheritanceModule.AssetAllocation[](2);
        
        // ETH
        assets[0] = IInheritanceModule.AssetAllocation({
            assetType: 0,
            assetAddress: address(0),
            tokenId: 0,
            amount: 5000, // 50%
            isPercentage: true
        });
        
        // ERC20 token
        assets[1] = IInheritanceModule.AssetAllocation({
            assetType: 1,
            assetAddress: 0xA0b86a33E6441b8435b662f0E2d0c2c4c5B8B8B8, // Example token
            tokenId: 0,
            amount: 10000, // 100%
            isPercentage: true
        });
        
        // Staked assets
        address[] memory protocols = new address[](2);
        protocols[0] = LIDO_STETH;
        protocols[1] = COMPOUND_CDAI;
        
        uint8[] memory strategies = new uint8[](2);
        strategies[0] = 0; // Transfer stETH
        strategies[1] = 1; // Redeem DAI
        
        bytes[] memory protocolData = new bytes[](2);
        protocolData[0] = "";
        protocolData[1] = abi.encode(CompoundHandler.CompoundData({
            cToken: COMPOUND_CDAI,
            claimRewards: true,
            exitMarket: true
        }));
        
        inheritanceModule.executeInheritanceWithStaking(
            EXAMPLE_SAFE,
            BENEFICIARY,
            assets,
            "",
            protocols,
            strategies,
            protocolData
        );
    }
    
    /**
     * @notice Example 5: Emergency Unstaking
     * @dev Shows how to handle emergency situations
     */
    function example5_EmergencyUnstaking() external {
        address[] memory protocols = new address[](2);
        protocols[0] = LIDO_STETH;
        protocols[1] = COMPOUND_CDAI;
        
        bytes[] memory protocolData = new bytes[](2);
        protocolData[0] = "";
        protocolData[1] = abi.encode(CompoundHandler.CompoundData({
            cToken: COMPOUND_CDAI,
            claimRewards: true,
            exitMarket: true
        }));
        
        // Emergency unbond all positions
        stakedAssetHandler.emergencyUnbond(EXAMPLE_SAFE, protocols, protocolData);
    }
    
    /**
     * @notice Example 6: Detect Staking Positions
     * @dev Shows how to discover staked assets
     */
    function example6_DetectStakingPositions() external {
        address[] memory protocols = new address[](3);
        protocols[0] = LIDO_STETH;
        protocols[1] = COMPOUND_CETH;
        protocols[2] = COMPOUND_CDAI;
        
        bytes[] memory protocolData = new bytes[](3);
        protocolData[0] = ""; // Lido doesn't need extra data
        protocolData[1] = abi.encode(CompoundHandler.CompoundData({
            cToken: COMPOUND_CETH,
            claimRewards: false,
            exitMarket: false
        }));
        protocolData[2] = abi.encode(CompoundHandler.CompoundData({
            cToken: COMPOUND_CDAI,
            claimRewards: false,
            exitMarket: false
        }));
        
        stakedAssetHandler.detectStakingPositions(EXAMPLE_SAFE, protocols, protocolData);
    }
    
    /**
     * @notice Example 7: Claim Rewards Before Inheritance
     * @dev Shows how to claim accumulated rewards
     */
    function example7_ClaimRewardsFirst() external {
        address[] memory protocols = new address[](1);
        protocols[0] = COMPOUND_CDAI;
        
        uint8[] memory strategies = new uint8[](1);
        strategies[0] = 2; // Claim rewards
        
        bytes[] memory protocolData = new bytes[](1);
        protocolData[0] = "";
        
        // First claim rewards
        stakedAssetHandler.handleStakedAssets(
            EXAMPLE_SAFE,
            BENEFICIARY,
            protocols,
            strategies,
            protocolData
        );
        
        // Then execute regular inheritance
        IInheritanceModule.AssetAllocation[] memory assets = 
            new IInheritanceModule.AssetAllocation[](1);
        assets[0] = IInheritanceModule.AssetAllocation({
            assetType: 1,
            assetAddress: 0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984, // UNI token (COMP rewards)
            tokenId: 0,
            amount: 10000,
            isPercentage: true
        });
        
        inheritanceModule.executeInheritance(EXAMPLE_SAFE, BENEFICIARY, assets, "");
    }
    
    /**
     * @notice Example 8: Batch Staking Operations
     * @dev Shows how to handle multiple protocols efficiently
     */
    function example8_BatchStakingOperations() external {
        // Handle multiple protocols with different strategies
        address[] memory protocols = new address[](4);
        protocols[0] = LIDO_STETH;
        protocols[1] = COMPOUND_CETH;
        protocols[2] = COMPOUND_CDAI;
        protocols[3] = LIDO_STETH; // Same protocol, different strategy
        
        uint8[] memory strategies = new uint8[](4);
        strategies[0] = 0; // Transfer stETH
        strategies[1] = 0; // Transfer cETH
        strategies[2] = 1; // Redeem DAI
        strategies[3] = 2; // Claim rewards (if any)
        
        bytes[] memory protocolData = new bytes[](4);
        protocolData[0] = "";
        protocolData[1] = abi.encode(CompoundHandler.CompoundData({
            cToken: COMPOUND_CETH,
            claimRewards: true,
            exitMarket: false
        }));
        protocolData[2] = abi.encode(CompoundHandler.CompoundData({
            cToken: COMPOUND_CDAI,
            claimRewards: true,
            exitMarket: true
        }));
        protocolData[3] = "";
        
        inheritanceModule.executeInheritanceWithStaking(
            EXAMPLE_SAFE,
            BENEFICIARY,
            new IInheritanceModule.AssetAllocation[](0),
            "",
            protocols,
            strategies,
            protocolData
        );
    }
    
    // Helper functions
    
    function _completeWithdrawal() internal {
        // This would be called after the Lido withdrawal period
        bytes32[] memory requestIds = stakedAssetHandler.getUnbondingRequests(EXAMPLE_SAFE);
        
        if (requestIds.length > 0) {
            bytes[] memory completionData = new bytes[](requestIds.length);
            for (uint256 i = 0; i < requestIds.length; i++) {
                // Get hint for withdrawal (simplified)
                completionData[i] = abi.encode(uint256(0)); // Hint would be calculated off-chain
            }
            
            stakedAssetHandler.completeUnbonding(requestIds, completionData);
        }
    }
    
    /**
     * @notice Get staking position summary for a Safe
     * @param safe Address of the Safe wallet
     * @return summary Summary of all staking positions
     */
    function getStakingPositionSummary(address safe) 
        external 
        view 
        returns (StakingPositionSummary memory summary) 
    {
        // Get Lido position
        StakedAssetHandler.StakingPosition[] memory lidoPositions = 
            stakedAssetHandler.getStakingPositions(safe, LIDO_STETH);
        
        // Get Compound positions
        StakedAssetHandler.StakingPosition[] memory cEthPositions = 
            stakedAssetHandler.getStakingPositions(safe, COMPOUND_CETH);
        StakedAssetHandler.StakingPosition[] memory cDaiPositions = 
            stakedAssetHandler.getStakingPositions(safe, COMPOUND_CDAI);
        
        // Get unbonding requests
        bytes32[] memory unbondingRequests = stakedAssetHandler.getUnbondingRequests(safe);
        
        summary = StakingPositionSummary({
            lidoStETH: lidoPositions.length > 0 ? lidoPositions[0].amount : 0,
            compoundCETH: cEthPositions.length > 0 ? cEthPositions[0].amount : 0,
            compoundCDAI: cDaiPositions.length > 0 ? cDaiPositions[0].amount : 0,
            pendingUnbonding: unbondingRequests.length,
            totalProtocols: _countActiveProtocols(safe)
        });
    }
    
    function _countActiveProtocols(address safe) internal view returns (uint256 count) {
        address[] memory protocols = new address[](3);
        protocols[0] = LIDO_STETH;
        protocols[1] = COMPOUND_CETH;
        protocols[2] = COMPOUND_CDAI;
        
        for (uint256 i = 0; i < protocols.length; i++) {
            StakedAssetHandler.StakingPosition[] memory positions = 
                stakedAssetHandler.getStakingPositions(safe, protocols[i]);
            if (positions.length > 0 && positions[0].amount > 0) {
                count++;
            }
        }
    }
    
    struct StakingPositionSummary {
        uint256 lidoStETH;
        uint256 compoundCETH;
        uint256 compoundCDAI;
        uint256 pendingUnbonding;
        uint256 totalProtocols;
    }
}
