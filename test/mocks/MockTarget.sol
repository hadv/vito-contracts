// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

contract MockTarget {
    function delegateCallMe() external pure returns (bool) {
        return true;
    }

    function callMe() external pure returns (bool) {
        return true;
    }

    // Receive function to handle ETH transfers
    receive() external payable {
        // Do nothing, just accept ETH
    }

    // Fallback function to handle all other calls
    fallback() external payable {
        // Do nothing, just accept the call
    }
}
