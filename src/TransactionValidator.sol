// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Enum} from "@safe-global/safe-contracts/contracts/common/Enum.sol";
import "./interfaces/ITransactionValidator.sol";
import "./interfaces/IAddressBookManager.sol";
import "./interfaces/ITrustedContractManager.sol";

/**
 * @title TransactionValidator
 * @notice Validates Safe transactions based on their type and configuration
 */
contract TransactionValidator is ITransactionValidator {
    IAddressBookManager public immutable addressBookManager;
    ITrustedContractManager public immutable trustedContractManager;

    constructor(address _addressBookManager, address _trustedContractManager) {
        addressBookManager = IAddressBookManager(_addressBookManager);
        trustedContractManager = ITrustedContractManager(_trustedContractManager);
    }

    /**
     * @notice Classify transaction type based on transaction parameters
     * @param value Ether value
     * @param data Transaction data
     * @param operation Operation type
     * @return txType The classified transaction type
     */
    function classifyTransaction(
        address, // to
        uint256 value,
        bytes memory data,
        Enum.Operation operation
    ) external pure returns (TransactionType) {
        // Check for delegate call first
        if (operation == Enum.Operation.DelegateCall) {
            return TransactionType.DELEGATE_CALL;
        }

        // Check for native ETH transfer (no data or empty data)
        if (value > 0 && data.length == 0) {
            return TransactionType.NATIVE_TRANSFER;
        }

        // Check for ERC20 transfers
        if (data.length >= 68) {
            // Minimum length for ERC20 function calls
            bytes4 selector = bytes4(data);

            // ERC20 transfer(address,uint256) - 0xa9059cbb
            if (selector == 0xa9059cbb) {
                return TransactionType.ERC20_TRANSFER;
            }

            // ERC20 transferFrom(address,address,uint256) - 0x23b872dd
            if (selector == 0x23b872dd && data.length >= 100) {
                return TransactionType.ERC20_TRANSFER_FROM;
            }
        }

        // Default to general contract interaction
        return TransactionType.CONTRACT_INTERACTION;
    }

    /**
     * @notice Validate transaction based on its type and Safe's configuration
     * @param safe The Safe wallet address
     * @param to Destination address
     * @param value Ether value
     * @param data Transaction data
     * @param operation Operation type
     */
    function validateTransaction(address safe, address to, uint256 value, bytes memory data, Enum.Operation operation)
        external
    {
        TransactionType txType = this.classifyTransaction(to, value, data, operation);
        _validateTransaction(safe, to, value, data, txType);

        emit TransactionValidated(safe, to, txType);
    }

    /**
     * @notice Internal function to validate transaction based on its type
     * @param safe The Safe wallet address
     * @param to Destination address
     * @param data Transaction data
     * @param txType Transaction type
     */
    function _validateTransaction(
        address safe,
        address to,
        uint256, // value
        bytes memory data,
        TransactionType txType
    ) internal view {
        if (txType == TransactionType.NATIVE_TRANSFER) {
            // For native transfers, validate the recipient address
            int256 index = addressBookManager.findAddressBookEntry(safe, to);
            if (index < 0) revert AddressNotInAddressBook();
        } else if (txType == TransactionType.ERC20_TRANSFER) {
            // For ERC20 transfers, validate both the token contract and the recipient
            // First check if the token contract is trusted
            bool isTokenTrusted = trustedContractManager.isTrustedContract(safe, to);

            // Extract recipient from ERC20 transfer data
            address recipient;
            assembly {
                // Skip 4 bytes function selector + 12 bytes padding
                recipient := mload(add(data, 36))
            }

            // If token contract is trusted, only validate recipient
            if (isTokenTrusted) {
                int256 recipientIndex = addressBookManager.findAddressBookEntry(safe, recipient);
                if (recipientIndex < 0) revert RecipientNotInAddressBook();
            } else {
                // If token contract is not trusted, both contract and recipient must be in address book
                int256 contractIndex = addressBookManager.findAddressBookEntry(safe, to);
                if (contractIndex < 0) revert ContractNotTrusted();

                int256 recipientIndex = addressBookManager.findAddressBookEntry(safe, recipient);
                if (recipientIndex < 0) revert RecipientNotInAddressBook();
            }
        } else if (txType == TransactionType.ERC20_TRANSFER_FROM) {
            // For ERC20 transferFrom, validate both the token contract and the recipient
            // First check if the token contract is trusted
            bool isTokenTrusted = trustedContractManager.isTrustedContract(safe, to);

            // Extract recipient from ERC20 transferFrom data
            address recipient;
            assembly {
                // Skip 4 bytes function selector + 12 bytes padding + 32 bytes (from address)
                recipient := mload(add(data, 68))
            }

            // If token contract is trusted, only validate recipient
            if (isTokenTrusted) {
                int256 recipientIndex = addressBookManager.findAddressBookEntry(safe, recipient);
                if (recipientIndex < 0) revert RecipientNotInAddressBook();
            } else {
                // If token contract is not trusted, both contract and recipient must be in address book
                int256 contractIndex = addressBookManager.findAddressBookEntry(safe, to);
                if (contractIndex < 0) revert ContractNotTrusted();

                int256 recipientIndex = addressBookManager.findAddressBookEntry(safe, recipient);
                if (recipientIndex < 0) revert RecipientNotInAddressBook();
            }
        } else if (txType == TransactionType.CONTRACT_INTERACTION) {
            // For general contract interactions, check if contract is trusted first
            bool isContractTrusted = trustedContractManager.isTrustedContract(safe, to);

            if (!isContractTrusted) {
                // If contract is not trusted, it must be in the address book
                int256 index = addressBookManager.findAddressBookEntry(safe, to);
                if (index < 0) revert ContractNotTrusted();
            }
        } else if (txType == TransactionType.DELEGATE_CALL) {
            // For delegate calls, check if contract is trusted first
            bool isContractTrusted = trustedContractManager.isTrustedContract(safe, to);

            if (!isContractTrusted) {
                // If contract is not trusted, it must be in the address book
                int256 index = addressBookManager.findAddressBookEntry(safe, to);
                if (index < 0) revert ContractNotTrusted();
            }
        }
    }
}
