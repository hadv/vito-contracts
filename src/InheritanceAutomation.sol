// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./interfaces/IInheritanceModule.sol";
import "./InheritanceModule.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

/**
 * @title InheritanceAutomation
 * @notice Automated execution service for time-based inheritance
 * @dev Provides keeper-style automation for inheritance execution
 */
contract InheritanceAutomation is Ownable, ReentrancyGuard {
    // Automation job structure
    struct AutomationJob {
        address safe;
        address module;
        address beneficiary;
        IInheritanceModule.AssetAllocation[] assets;
        bytes oracleProof;
        uint256 executionTime;
        bool executed;
        address creator;
        uint256 reward;
    }

    // Keeper structure
    struct Keeper {
        bool isActive;
        uint256 successfulExecutions;
        uint256 failedExecutions;
        uint256 totalRewards;
        uint256 registrationTime;
    }

    // Storage
    mapping(bytes32 => AutomationJob) public automationJobs;
    mapping(address => Keeper) public keepers;
    mapping(address => bytes32[]) public safeJobs;

    bytes32[] public pendingJobs;
    address[] public activeKeepers;

    // Settings
    uint256 public minReward = 0.001 ether;
    uint256 public maxReward = 1 ether;
    uint256 public keeperBond = 0.1 ether;
    uint256 public executionWindow = 24 hours; // Window after execution time

    // Events
    event JobCreated(
        bytes32 indexed jobId, address indexed safe, address indexed beneficiary, uint256 executionTime, uint256 reward
    );

    event JobExecuted(bytes32 indexed jobId, address indexed keeper, bool success, uint256 reward);

    event KeeperRegistered(address indexed keeper);
    event KeeperDeregistered(address indexed keeper);

    // Errors
    error InsufficientReward();
    error JobNotFound();
    error JobAlreadyExecuted();
    error ExecutionTimeNotReached();
    error ExecutionWindowExpired();
    error KeeperNotActive();
    error InsufficientBond();
    error JobNotExecutable();

    /**
     * @notice Create an automation job for inheritance execution
     * @param safe Address of the Safe wallet
     * @param module Address of the inheritance module
     * @param beneficiary Address of the beneficiary
     * @param assets Array of asset allocations
     * @param oracleProof Oracle proof if required
     * @param executionTime Timestamp when job should be executed
     */
    function createAutomationJob(
        address safe,
        address module,
        address beneficiary,
        IInheritanceModule.AssetAllocation[] calldata assets,
        bytes calldata oracleProof,
        uint256 executionTime
    ) external payable nonReentrant returns (bytes32 jobId) {
        if (msg.value < minReward || msg.value > maxReward) revert InsufficientReward();
        if (executionTime <= block.timestamp) revert ExecutionTimeNotReached();

        jobId = keccak256(abi.encodePacked(safe, beneficiary, executionTime, block.timestamp, msg.sender));

        // Store assets in the job
        AutomationJob storage job = automationJobs[jobId];
        job.safe = safe;
        job.module = module;
        job.beneficiary = beneficiary;
        job.oracleProof = oracleProof;
        job.executionTime = executionTime;
        job.executed = false;
        job.creator = msg.sender;
        job.reward = msg.value;

        // Copy assets
        for (uint256 i = 0; i < assets.length; i++) {
            job.assets.push(assets[i]);
        }

        pendingJobs.push(jobId);
        safeJobs[safe].push(jobId);

        emit JobCreated(jobId, safe, beneficiary, executionTime, msg.value);
        return jobId;
    }

    /**
     * @notice Execute an automation job
     * @param jobId ID of the job to execute
     */
    function executeJob(bytes32 jobId) external nonReentrant {
        if (!keepers[msg.sender].isActive) revert KeeperNotActive();

        AutomationJob storage job = automationJobs[jobId];
        if (job.creator == address(0)) revert JobNotFound();
        if (job.executed) revert JobAlreadyExecuted();
        if (block.timestamp < job.executionTime) revert ExecutionTimeNotReached();
        if (block.timestamp > job.executionTime + executionWindow) revert ExecutionWindowExpired();

        // Check if inheritance can be executed
        (bool canExecute, string memory reason) =
            InheritanceModule(job.module).canExecuteInheritance(job.safe, job.beneficiary);

        if (!canExecute) revert JobNotExecutable();

        job.executed = true;
        bool success = false;

        try InheritanceModule(job.module).executeInheritance(job.safe, job.beneficiary, job.assets, job.oracleProof) {
            success = true;
            keepers[msg.sender].successfulExecutions++;
        } catch {
            keepers[msg.sender].failedExecutions++;
        }

        if (success) {
            // Pay reward to keeper
            keepers[msg.sender].totalRewards += job.reward;
            payable(msg.sender).transfer(job.reward);
        } else {
            // Return reward to job creator
            payable(job.creator).transfer(job.reward);
        }

        emit JobExecuted(jobId, msg.sender, success, job.reward);
        _removeFromPendingJobs(jobId);
    }

    /**
     * @notice Register as a keeper
     */
    function registerKeeper() external payable {
        if (msg.value < keeperBond) revert InsufficientBond();

        keepers[msg.sender] = Keeper({
            isActive: true,
            successfulExecutions: 0,
            failedExecutions: 0,
            totalRewards: 0,
            registrationTime: block.timestamp
        });

        activeKeepers.push(msg.sender);
        emit KeeperRegistered(msg.sender);
    }

    /**
     * @notice Deregister as a keeper
     */
    function deregisterKeeper() external nonReentrant {
        require(keepers[msg.sender].isActive, "Not an active keeper");

        keepers[msg.sender].isActive = false;

        // Return bond
        payable(msg.sender).transfer(keeperBond);

        _removeFromActiveKeepers(msg.sender);
        emit KeeperDeregistered(msg.sender);
    }

    /**
     * @notice Cancel an automation job (only creator)
     * @param jobId ID of the job to cancel
     */
    function cancelJob(bytes32 jobId) external nonReentrant {
        AutomationJob storage job = automationJobs[jobId];
        require(job.creator == msg.sender, "Not job creator");
        require(!job.executed, "Job already executed");

        job.executed = true; // Mark as executed to prevent execution

        // Return reward to creator
        payable(job.creator).transfer(job.reward);

        _removeFromPendingJobs(jobId);
    }

    /**
     * @notice Get executable jobs for keepers
     * @return executableJobs Array of job IDs that can be executed
     */
    function getExecutableJobs() external view returns (bytes32[] memory executableJobs) {
        uint256 count = 0;

        // First pass: count executable jobs
        for (uint256 i = 0; i < pendingJobs.length; i++) {
            bytes32 jobId = pendingJobs[i];
            AutomationJob memory job = automationJobs[jobId];

            if (
                !job.executed && block.timestamp >= job.executionTime
                    && block.timestamp <= job.executionTime + executionWindow
            ) {
                count++;
            }
        }

        // Second pass: populate array
        executableJobs = new bytes32[](count);
        uint256 index = 0;

        for (uint256 i = 0; i < pendingJobs.length; i++) {
            bytes32 jobId = pendingJobs[i];
            AutomationJob memory job = automationJobs[jobId];

            if (
                !job.executed && block.timestamp >= job.executionTime
                    && block.timestamp <= job.executionTime + executionWindow
            ) {
                executableJobs[index] = jobId;
                index++;
            }
        }
    }

    /**
     * @notice Get jobs for a specific Safe
     * @param safe Address of the Safe wallet
     * @return jobIds Array of job IDs for the Safe
     */
    function getSafeJobs(address safe) external view returns (bytes32[] memory jobIds) {
        return safeJobs[safe];
    }

    /**
     * @notice Get keeper information
     * @param keeper Address of the keeper
     * @return keeperInfo Keeper information
     */
    function getKeeperInfo(address keeper) external view returns (Keeper memory keeperInfo) {
        return keepers[keeper];
    }

    /**
     * @notice Update automation settings (only owner)
     */
    function updateSettings(uint256 _minReward, uint256 _maxReward, uint256 _keeperBond, uint256 _executionWindow)
        external
        onlyOwner
    {
        minReward = _minReward;
        maxReward = _maxReward;
        keeperBond = _keeperBond;
        executionWindow = _executionWindow;
    }

    // Internal functions

    function _removeFromPendingJobs(bytes32 jobId) internal {
        for (uint256 i = 0; i < pendingJobs.length; i++) {
            if (pendingJobs[i] == jobId) {
                pendingJobs[i] = pendingJobs[pendingJobs.length - 1];
                pendingJobs.pop();
                break;
            }
        }
    }

    function _removeFromActiveKeepers(address keeper) internal {
        for (uint256 i = 0; i < activeKeepers.length; i++) {
            if (activeKeepers[i] == keeper) {
                activeKeepers[i] = activeKeepers[activeKeepers.length - 1];
                activeKeepers.pop();
                break;
            }
        }
    }

    /**
     * @notice Get job details
     * @param jobId ID of the job
     * @return job Job details
     */
    function getJob(bytes32 jobId) external view returns (AutomationJob memory job) {
        return automationJobs[jobId];
    }

    /**
     * @notice Get all pending jobs
     * @return jobs Array of pending job IDs
     */
    function getPendingJobs() external view returns (bytes32[] memory jobs) {
        return pendingJobs;
    }

    /**
     * @notice Get all active keepers
     * @return keepers Array of active keeper addresses
     */
    function getActiveKeepers() external view returns (address[] memory) {
        return activeKeepers;
    }
}
