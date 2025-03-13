// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {SafeTxPool} from "../src/SafeTxPool.sol";

contract DeploySafeTxPool is Script {
    function setUp() public {}

    function run() public {
        // Get deployment configuration from environment variables
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        string memory network = vm.envString("NETWORK");

        // Log deployment information
        console.log("Deploying SafeTxPool to network:", network);

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy SafeTxPool contract
        SafeTxPool pool = new SafeTxPool();

        // Stop broadcasting transactions
        vm.stopBroadcast();

        // Log the deployed contract address
        console.log("SafeTxPool deployed at:", address(pool));
        console.log("Network:", network);
    }
}
