// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Enum} from "@safe-global/safe-contracts/contracts/common/Enum.sol";
import {BaseGuard} from "@safe-global/safe-contracts/contracts/base/GuardManager.sol";

contract SafeGuard is BaseGuard {
    mapping(address => bool) public allowedTargets;
    address public immutable owner;

    error OnlyOwner();
    error DelegateCallRestricted();

    event TargetAllowed(address indexed target);
    event TargetDisallowed(address indexed target);

    constructor(address[] memory targets) {
        owner = msg.sender;
        for (uint256 i = 0; i < targets.length; i++) {
            require(targets[i] != address(0), "Invalid target address");
            allowedTargets[targets[i]] = true;
            emit TargetAllowed(targets[i]);
        }
    }

    modifier onlyOwner() {
        if (msg.sender != owner && msg.sender != address(this)) revert OnlyOwner();
        _;
    }

    function addAllowedTarget(address target) public onlyOwner {
        require(target != address(0), "Invalid target address");
        allowedTargets[target] = true;
        emit TargetAllowed(target);
    }

    function removeAllowedTarget(address target) public onlyOwner {
        allowedTargets[target] = false;
        emit TargetDisallowed(target);
    }

    // This function is called by the Safe contract before a transaction is executed.
    // It is used to restrict delegate calls to only the allowed targets.
    function checkTransaction(
        address to,
        uint256,
        bytes memory,
        Enum.Operation operation,
        uint256,
        uint256,
        uint256,
        address,
        address payable,
        bytes memory,
        address
    ) external view override {
        if (operation == Enum.Operation.DelegateCall && !allowedTargets[to]) revert DelegateCallRestricted();
    }

    // This function is called by the Safe contract after a transaction is executed.
    // It is not used in this guard.
    function checkAfterExecution(bytes32, bool) external view override {}

    // This function is called by the Safe contract when a function is not found.
    // It is used to prevent the Safe from being locked during upgrades.
    fallback() external {
        // We do not want to revert here to prevent the Safe from being locked during upgrades
    }
}
