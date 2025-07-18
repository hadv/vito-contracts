// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./interfaces/IAddressBookManager.sol";

/**
 * @title AddressBookManager
 * @notice Manages address books for Safe wallets
 */
contract AddressBookManager is IAddressBookManager {
    // Mapping from Safe address to its array of address book entries
    mapping(address => AddressBookEntry[]) private addressBooks;

    // Registry contract that can call this manager
    address public immutable registry;

    constructor(address _registry) {
        registry = _registry;
    }

    modifier onlySafeOrRegistry(address safe) {
        if (msg.sender != safe && msg.sender != registry) revert NotSafeWallet();
        _;
    }

    /**
     * @notice Add an entry to the address book of a Safe
     * @param safe The Safe wallet address that owns this address book
     * @param walletAddress The wallet address to add (mandatory)
     * @param name Name associated with the address (32 bytes)
     */
    function addAddressBookEntry(address safe, address walletAddress, bytes32 name) external onlySafeOrRegistry(safe) {
        // Validate inputs
        if (walletAddress == address(0)) revert InvalidAddress();

        // Check if entry already exists
        int256 existingIndex = findAddressBookEntry(safe, walletAddress);
        if (existingIndex >= 0) {
            // Update existing entry
            uint256 index = uint256(existingIndex);
            addressBooks[safe][index].name = name;
        } else {
            // Add new entry
            addressBooks[safe].push(AddressBookEntry({name: name, walletAddress: walletAddress}));
        }

        emit AddressBookEntryAdded(safe, walletAddress, name);
    }

    /**
     * @notice Remove an entry from the address book of a Safe
     * @param safe The Safe wallet address that owns this address book
     * @param walletAddress The wallet address to remove
     */
    function removeAddressBookEntry(address safe, address walletAddress) external onlySafeOrRegistry(safe) {
        int256 index = findAddressBookEntry(safe, walletAddress);

        if (index < 0) revert AddressNotFound();

        // Get the array
        AddressBookEntry[] storage entries = addressBooks[safe];
        uint256 entryIndex = uint256(index);

        // Move the last element to the position of the element to delete (if it's not the last)
        if (entryIndex < entries.length - 1) {
            entries[entryIndex] = entries[entries.length - 1];
        }

        // Remove the last element
        entries.pop();

        emit AddressBookEntryRemoved(safe, walletAddress);
    }

    /**
     * @notice Get all address book entries for a Safe
     * @param safe The Safe wallet address
     * @return entries Array of address book entries
     */
    function getAddressBookEntries(address safe) external view returns (AddressBookEntry[] memory) {
        return addressBooks[safe];
    }

    /**
     * @notice Check if an address exists in the address book
     * @param safe The Safe wallet address
     * @param walletAddress The wallet address to check
     * @return exists Whether the address exists in the address book
     */
    function hasAddressBookEntry(address safe, address walletAddress) external view returns (bool) {
        return findAddressBookEntry(safe, walletAddress) >= 0;
    }

    /**
     * @notice Find an entry's index in the address book
     * @param safe The Safe wallet address
     * @param walletAddress The wallet address to find
     * @return index Index of the entry, or -1 if not found
     */
    function findAddressBookEntry(address safe, address walletAddress) public view returns (int256) {
        AddressBookEntry[] storage entries = addressBooks[safe];

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].walletAddress == walletAddress) {
                return int256(i);
            }
        }

        return -1; // Not found
    }
}
