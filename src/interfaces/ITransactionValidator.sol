// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Enum} from "@safe-global/safe-contracts/contracts/common/Enum.sol";

/**
 * @title ITransactionValidator
 * @notice Interface for validating Safe transactions
 */
interface ITransactionValidator {
    // Enum for different transaction types
    enum TransactionType {
        NATIVE_TRANSFER, // ETH transfer with no data
        ERC20_TRANSFER, // ERC20 token transfer
        ERC20_TRANSFER_FROM, // ERC20 token transferFrom
        CONTRACT_INTERACTION, // General contract interaction
        DELEGATE_CALL // Delegate call operation

    }

    // Events
    event TransactionValidated(address indexed safe, address indexed to, TransactionType txType);

    // Errors
    error AddressNotInAddressBook();
    error RecipientNotInAddressBook();
    error ContractNotTrusted();

    /**
     * @notice Classify transaction type based on transaction parameters
     * @param to Destination address
     * @param value Ether value
     * @param data Transaction data
     * @param operation Operation type
     * @return txType The classified transaction type
     */
    function classifyTransaction(address to, uint256 value, bytes memory data, Enum.Operation operation)
        external
        pure
        returns (TransactionType);

    /**
     * @notice Validate transaction based on its type and Safe's configuration
     * @param safe The Safe wallet address
     * @param to Destination address
     * @param value Ether value
     * @param data Transaction data
     * @param operation Operation type
     */
    function validateTransaction(address safe, address to, uint256 value, bytes memory data, Enum.Operation operation)
        external;
}
