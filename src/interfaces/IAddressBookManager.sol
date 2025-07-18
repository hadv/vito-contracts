// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./IBaseManager.sol";

/**
 * @title IAddressBookManager
 * @notice Interface for managing address books for Safe wallets
 */
interface IAddressBookManager is IBaseManager {
    // Simple struct for address book entries
    struct AddressBookEntry {
        bytes32 name; // Limited to 32 bytes
        address walletAddress; // Mandatory
    }

    // Events
    event AddressBookEntryAdded(address indexed safe, address indexed walletAddress, bytes32 name);
    event AddressBookEntryRemoved(address indexed safe, address indexed walletAddress);

    // Errors (inherited from IBaseManager: InvalidAddress, NotSafeWallet)
    error AddressNotFound();

    /**
     * @notice Add an entry to the address book of a Safe
     * @param safe The Safe wallet address that owns this address book
     * @param walletAddress The wallet address to add (mandatory)
     * @param name Name associated with the address (32 bytes)
     */
    function addAddressBookEntry(address safe, address walletAddress, bytes32 name) external;

    /**
     * @notice Remove an entry from the address book of a Safe
     * @param safe The Safe wallet address that owns this address book
     * @param walletAddress The wallet address to remove
     */
    function removeAddressBookEntry(address safe, address walletAddress) external;

    /**
     * @notice Get all address book entries for a Safe
     * @param safe The Safe wallet address
     * @return entries Array of address book entries
     */
    function getAddressBookEntries(address safe) external view returns (AddressBookEntry[] memory);

    /**
     * @notice Check if an address exists in the address book
     * @param safe The Safe wallet address
     * @param walletAddress The wallet address to check
     * @return exists Whether the address exists in the address book
     */
    function hasAddressBookEntry(address safe, address walletAddress) external view returns (bool);

    /**
     * @notice Find an entry's index in the address book
     * @param safe The Safe wallet address
     * @param walletAddress The wallet address to find
     * @return index Index of the entry, or -1 if not found
     */
    function findAddressBookEntry(address safe, address walletAddress) external view returns (int256);
}
