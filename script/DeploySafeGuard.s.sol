// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {SafeGuard} from "../src/SafeGuard.sol";

contract DeploySafeGuard is Script {
    function run() external returns (SafeGuard) {
        // Get deployer's private key from environment variable
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Initialize allowed targets array (can be modified as needed)
        address[] memory initialTargets = new address[](0);

        // Deploy SafeGuard with initial targets
        SafeGuard guard = new SafeGuard(initialTargets);

        vm.stopBroadcast();

        return guard;
    }
} 