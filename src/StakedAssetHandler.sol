// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./interfaces/IInheritanceModule.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

// Protocol handler interface
interface IProtocolHandler {
    function getStakingPosition(address safe, bytes calldata data)
        external
        view
        returns (StakedAssetHandler.StakingPosition memory);
    function initiateUnbonding(address safe, uint256 amount, bytes calldata data)
        external
        returns (bytes32 requestId);
    function completeUnbonding(address safe, bytes32 requestId, bytes calldata data)
        external
        returns (uint256 amount);
    function claimRewards(address safe, bytes calldata data) external returns (uint256 rewards);
    function transferReceiptToken(address safe, address to, uint256 amount, bytes calldata data)
        external
        returns (bool success);
}

/**
 * @title StakedAssetHandler
 * @notice Handles staked assets in DeFi protocols for inheritance
 * @dev Supports various staking protocols and unbonding mechanisms
 */
contract StakedAssetHandler is ReentrancyGuard, Ownable {
    // Staking protocol types
    enum ProtocolType {
        ETHEREUM_STAKING, // ETH 2.0 staking (Lido, RocketPool, etc.)
        COMPOUND_LIKE, // Compound, Aave lending
        UNISWAP_V3, // Uniswap V3 LP positions
        CURVE, // Curve LP tokens
        YEARN, // Yearn vaults
        CONVEX, // Convex staking
        GENERIC_STAKING, // Generic staking contracts
        LIQUID_STAKING, // Liquid staking tokens (stETH, rETH)
        VALIDATOR_STAKING // Direct validator staking

    }

    // Staking position information
    struct StakingPosition {
        address protocol; // Protocol contract address
        ProtocolType protocolType; // Type of staking protocol
        address stakedToken; // Original staked token
        address receiptToken; // Receipt token (if any)
        uint256 amount; // Staked amount
        uint256 rewards; // Accumulated rewards
        uint256 unbondingTime; // When unbonding completes
        bool isUnbonding; // Whether currently unbonding
        bool hasReceiptToken; // Whether position has transferable receipt
        bytes extraData; // Protocol-specific data
    }

    // Unbonding request
    struct UnbondingRequest {
        address safe;
        address beneficiary;
        address protocol;
        uint256 amount;
        uint256 requestTime;
        uint256 completionTime;
        bool completed;
        bytes32 requestId;
    }

    // Storage
    mapping(address => mapping(address => StakingPosition[])) public stakingPositions; // safe => protocol => positions
    mapping(address => IProtocolHandler) public protocolHandlers;
    mapping(bytes32 => UnbondingRequest) public unbondingRequests;
    mapping(address => bytes32[]) public safeUnbondingRequests;

    // Settings
    uint256 public maxUnbondingPeriod = 21 days;
    uint256 public emergencyUnbondingDelay = 7 days;

    // Events
    event StakingPositionDetected(
        address indexed safe, address indexed protocol, ProtocolType protocolType, uint256 amount
    );

    event UnbondingInitiated(address indexed safe, address indexed protocol, bytes32 indexed requestId, uint256 amount);

    event UnbondingCompleted(address indexed safe, bytes32 indexed requestId, uint256 amount);

    event RewardsClaimed(address indexed safe, address indexed protocol, uint256 amount);

    event ReceiptTokenTransferred(address indexed safe, address indexed beneficiary, address token, uint256 amount);

    // Errors
    error ProtocolNotSupported();
    error UnbondingNotReady();
    error InvalidUnbondingRequest();
    error PositionNotFound();
    error TransferFailed();

    constructor() Ownable(msg.sender) {}

    /**
     * @notice Register a protocol handler
     * @param protocol Protocol contract address
     * @param handler Handler contract address
     */
    function registerProtocolHandler(address protocol, address handler) external onlyOwner {
        protocolHandlers[protocol] = IProtocolHandler(handler);
    }

    /**
     * @notice Detect and register staking positions for a Safe
     * @param safe Address of the Safe wallet
     * @param protocols Array of protocol addresses to check
     * @param protocolData Array of protocol-specific data
     */
    function detectStakingPositions(address safe, address[] calldata protocols, bytes[] calldata protocolData)
        external
    {
        require(protocols.length == protocolData.length, "Array length mismatch");

        for (uint256 i = 0; i < protocols.length; i++) {
            address protocol = protocols[i];
            IProtocolHandler handler = protocolHandlers[protocol];

            if (address(handler) == address(0)) revert ProtocolNotSupported();

            StakingPosition memory position = handler.getStakingPosition(safe, protocolData[i]);

            if (position.amount > 0) {
                stakingPositions[safe][protocol].push(position);

                emit StakingPositionDetected(safe, protocol, position.protocolType, position.amount);
            }
        }
    }

    /**
     * @notice Handle staked assets during inheritance execution
     * @param safe Address of the Safe wallet
     * @param beneficiary Address of the beneficiary
     * @param protocols Array of protocols to handle
     * @param strategies Array of handling strategies (0: transfer receipt, 1: unbond, 2: claim rewards)
     * @param protocolData Array of protocol-specific data
     */
    function handleStakedAssets(
        address safe,
        address beneficiary,
        address[] calldata protocols,
        uint8[] calldata strategies,
        bytes[] calldata protocolData
    ) external nonReentrant {
        require(
            protocols.length == strategies.length && strategies.length == protocolData.length, "Array length mismatch"
        );

        for (uint256 i = 0; i < protocols.length; i++) {
            address protocol = protocols[i];
            uint8 strategy = strategies[i];
            bytes calldata data = protocolData[i];

            IProtocolHandler handler = protocolHandlers[protocol];
            if (address(handler) == address(0)) revert ProtocolNotSupported();

            if (strategy == 0) {
                // Transfer receipt tokens
                _transferReceiptTokens(safe, beneficiary, protocol, handler, data);
            } else if (strategy == 1) {
                // Initiate unbonding
                _initiateUnbonding(safe, beneficiary, protocol, handler, data);
            } else if (strategy == 2) {
                // Claim rewards
                _claimRewards(safe, protocol, handler, data);
            }
        }
    }

    /**
     * @notice Complete unbonding requests that are ready
     * @param requestIds Array of unbonding request IDs
     * @param protocolData Array of protocol-specific data for completion
     */
    function completeUnbonding(bytes32[] calldata requestIds, bytes[] calldata protocolData) external nonReentrant {
        require(requestIds.length == protocolData.length, "Array length mismatch");

        for (uint256 i = 0; i < requestIds.length; i++) {
            bytes32 requestId = requestIds[i];
            UnbondingRequest storage request = unbondingRequests[requestId];

            if (request.safe == address(0)) revert InvalidUnbondingRequest();
            if (request.completed) continue;
            if (block.timestamp < request.completionTime) revert UnbondingNotReady();

            IProtocolHandler handler = protocolHandlers[request.protocol];
            uint256 amount = handler.completeUnbonding(request.safe, requestId, protocolData[i]);

            request.completed = true;

            emit UnbondingCompleted(request.safe, requestId, amount);
        }
    }

    /**
     * @notice Emergency unbonding for critical situations
     * @param safe Address of the Safe wallet
     * @param protocols Array of protocols to emergency unbond
     * @param protocolData Array of protocol-specific data
     */
    function emergencyUnbond(address safe, address[] calldata protocols, bytes[] calldata protocolData)
        external
        onlyOwner
    {
        for (uint256 i = 0; i < protocols.length; i++) {
            IProtocolHandler handler = protocolHandlers[protocols[i]];
            if (address(handler) != address(0)) {
                try handler.initiateUnbonding(safe, type(uint256).max, protocolData[i]) {
                    // Emergency unbonding initiated
                } catch {
                    // Continue with other protocols if one fails
                }
            }
        }
    }

    // Internal functions

    function _transferReceiptTokens(
        address safe,
        address beneficiary,
        address protocol,
        IProtocolHandler handler,
        bytes calldata data
    ) internal {
        StakingPosition[] memory positions = stakingPositions[safe][protocol];

        for (uint256 j = 0; j < positions.length; j++) {
            if (positions[j].hasReceiptToken && positions[j].amount > 0) {
                bool success = handler.transferReceiptToken(safe, beneficiary, positions[j].amount, data);

                if (success) {
                    emit ReceiptTokenTransferred(safe, beneficiary, positions[j].receiptToken, positions[j].amount);
                }
            }
        }
    }

    function _initiateUnbonding(
        address safe,
        address beneficiary,
        address protocol,
        IProtocolHandler handler,
        bytes calldata data
    ) internal {
        StakingPosition[] memory positions = stakingPositions[safe][protocol];

        for (uint256 j = 0; j < positions.length; j++) {
            if (!positions[j].hasReceiptToken && positions[j].amount > 0) {
                bytes32 requestId = handler.initiateUnbonding(safe, positions[j].amount, data);

                unbondingRequests[requestId] = UnbondingRequest({
                    safe: safe,
                    beneficiary: beneficiary,
                    protocol: protocol,
                    amount: positions[j].amount,
                    requestTime: block.timestamp,
                    completionTime: block.timestamp + maxUnbondingPeriod,
                    completed: false,
                    requestId: requestId
                });

                safeUnbondingRequests[safe].push(requestId);

                emit UnbondingInitiated(safe, protocol, requestId, positions[j].amount);
            }
        }
    }

    function _claimRewards(address safe, address protocol, IProtocolHandler handler, bytes calldata data) internal {
        uint256 rewards = handler.claimRewards(safe, data);

        if (rewards > 0) {
            emit RewardsClaimed(safe, protocol, rewards);
        }
    }

    // View functions

    /**
     * @notice Get all staking positions for a Safe
     * @param safe Address of the Safe wallet
     * @param protocol Protocol address
     * @return positions Array of staking positions
     */
    function getStakingPositions(address safe, address protocol)
        external
        view
        returns (StakingPosition[] memory positions)
    {
        return stakingPositions[safe][protocol];
    }

    /**
     * @notice Get unbonding requests for a Safe
     * @param safe Address of the Safe wallet
     * @return requests Array of unbonding request IDs
     */
    function getUnbondingRequests(address safe) external view returns (bytes32[] memory requests) {
        return safeUnbondingRequests[safe];
    }

    /**
     * @notice Check if unbonding is ready for completion
     * @param requestId Unbonding request ID
     * @return ready Whether unbonding is ready
     * @return timeRemaining Time remaining until completion
     */
    function isUnbondingReady(bytes32 requestId) external view returns (bool ready, uint256 timeRemaining) {
        UnbondingRequest memory request = unbondingRequests[requestId];

        if (request.safe == address(0) || request.completed) {
            return (false, 0);
        }

        if (block.timestamp >= request.completionTime) {
            return (true, 0);
        }

        return (false, request.completionTime - block.timestamp);
    }
}
