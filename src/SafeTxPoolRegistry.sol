// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Enum} from "@safe-global/safe-contracts/contracts/common/Enum.sol";
import {BaseGuard} from "@safe-global/safe-contracts/contracts/base/GuardManager.sol";
import "./interfaces/ISafeTxPoolCore.sol";
import "./interfaces/IAddressBookManager.sol";
import "./interfaces/IDelegateCallManager.sol";
import "./interfaces/ITrustedContractManager.sol";
import "./interfaces/ITransactionValidator.sol";

/**
 * @title SafeTxPoolRegistry
 * @notice Main coordinator contract that provides a unified interface to all Safe transaction pool components
 */
contract SafeTxPoolRegistry is BaseGuard {
    // Custom errors
    error NotProposer();

    ISafeTxPoolCore public immutable txPoolCore;
    IAddressBookManager public immutable addressBookManager;
    IDelegateCallManager public immutable delegateCallManager;
    ITrustedContractManager public immutable trustedContractManager;
    ITransactionValidator public immutable transactionValidator;

    // Events
    event SelfCallAllowed(address indexed safe, address indexed to);
    event GuardCallAllowed(address indexed safe, address indexed guard);

    // Errors
    error DelegateCallDisabled();
    error DelegateCallTargetNotAllowed();
    error NotSafeWallet();

    modifier onlySafe(address safe) {
        if (msg.sender != safe) revert NotSafeWallet();
        _;
    }

    constructor(
        address _txPoolCore,
        address _addressBookManager,
        address _delegateCallManager,
        address _trustedContractManager,
        address _transactionValidator
    ) {
        txPoolCore = ISafeTxPoolCore(_txPoolCore);
        addressBookManager = IAddressBookManager(_addressBookManager);
        delegateCallManager = IDelegateCallManager(_delegateCallManager);
        trustedContractManager = ITrustedContractManager(_trustedContractManager);
        transactionValidator = ITransactionValidator(_transactionValidator);
    }

    // ============ Transaction Pool Functions ============

    /**
     * @notice Propose a new Safe transaction
     */
    function proposeTx(
        bytes32 txHash,
        address safe,
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation,
        uint256 nonce
    ) external {
        txPoolCore.proposeTxWithProposer(txHash, safe, to, value, data, operation, nonce, msg.sender);
    }

    /**
     * @notice Sign a proposed transaction
     */
    function signTx(bytes32 txHash, bytes calldata signature) external {
        txPoolCore.signTx(txHash, signature);
    }

    /**
     * @notice Mark a transaction as executed and remove from storage
     */
    function markAsExecuted(bytes32 txHash) external {
        txPoolCore.markAsExecuted(txHash);
    }

    /**
     * @notice Delete a pending transaction
     */
    function deleteTx(bytes32 txHash) external {
        // Get transaction details to check if caller is the proposer
        (,,,,, address proposer,,) = txPoolCore.getTxDetails(txHash);

        // Check if caller is the proposer
        if (msg.sender != proposer) revert NotProposer();

        txPoolCore.deleteTx(txHash);
    }

    /**
     * @notice Get transaction details by hash
     */
    function getTxDetails(bytes32 txHash)
        external
        view
        returns (
            address safe,
            address to,
            uint256 value,
            bytes memory data,
            Enum.Operation operation,
            address proposer,
            uint256 nonce,
            uint256 txId
        )
    {
        return txPoolCore.getTxDetails(txHash);
    }

    /**
     * @notice Get all signatures for a transaction
     */
    function getSignatures(bytes32 txHash) external view returns (bytes[] memory) {
        return txPoolCore.getSignatures(txHash);
    }

    /**
     * @notice Check if an address has signed a transaction
     */
    function hasSignedTx(bytes32 txHash, address signer) external view returns (bool) {
        return txPoolCore.hasSignedTx(txHash, signer);
    }

    /**
     * @notice Get a range of pending transaction hashes for a Safe
     */
    function getPendingTxHashes(address safe, uint256 offset, uint256 limit) external view returns (bytes32[] memory) {
        return txPoolCore.getPendingTxHashes(safe, offset, limit);
    }

    // ============ Address Book Functions ============

    /**
     * @notice Add an entry to the address book of a Safe
     */
    function addAddressBookEntry(address safe, address walletAddress, bytes32 name) external onlySafe(safe) {
        addressBookManager.addAddressBookEntry(safe, walletAddress, name);
    }

    /**
     * @notice Remove an entry from the address book of a Safe
     */
    function removeAddressBookEntry(address safe, address walletAddress) external onlySafe(safe) {
        addressBookManager.removeAddressBookEntry(safe, walletAddress);
    }

    /**
     * @notice Get all address book entries for a Safe
     */
    function getAddressBookEntries(address safe)
        external
        view
        returns (IAddressBookManager.AddressBookEntry[] memory)
    {
        return addressBookManager.getAddressBookEntries(safe);
    }

    // ============ Delegate Call Functions ============

    /**
     * @notice Enable or disable delegate calls for a Safe
     */
    function setDelegateCallEnabled(address safe, bool enabled) external onlySafe(safe) {
        delegateCallManager.setDelegateCallEnabled(safe, enabled);
    }

    /**
     * @notice Add an allowed delegate call target for a Safe
     */
    function addDelegateCallTarget(address safe, address target) external onlySafe(safe) {
        delegateCallManager.addDelegateCallTarget(safe, target);
    }

    /**
     * @notice Remove an allowed delegate call target for a Safe
     */
    function removeDelegateCallTarget(address safe, address target) external onlySafe(safe) {
        delegateCallManager.removeDelegateCallTarget(safe, target);
    }

    /**
     * @notice Check if delegate calls are enabled for a Safe
     */
    function isDelegateCallEnabled(address safe) external view returns (bool) {
        return delegateCallManager.isDelegateCallEnabled(safe);
    }

    /**
     * @notice Check if a target is allowed for delegate calls from a Safe
     */
    function isDelegateCallTargetAllowed(address safe, address target) external view returns (bool) {
        return delegateCallManager.isDelegateCallTargetAllowed(safe, target);
    }

    /**
     * @notice Get all allowed delegate call targets for a Safe
     */
    function getDelegateCallTargets(address safe) external view returns (address[] memory) {
        return delegateCallManager.getDelegateCallTargets(safe);
    }

    /**
     * @notice Get the number of allowed delegate call targets for a Safe
     */
    function getDelegateCallTargetsCount(address safe) external view returns (uint256) {
        return delegateCallManager.getDelegateCallTargetsCount(safe);
    }

    // ============ Trusted Contract Functions ============

    /**
     * @notice Add a trusted contract for a Safe
     */
    function addTrustedContract(address safe, address contractAddress, bytes32 name) external onlySafe(safe) {
        trustedContractManager.addTrustedContract(safe, contractAddress, name);
    }

    /**
     * @notice Remove a trusted contract for a Safe
     */
    function removeTrustedContract(address safe, address contractAddress) external onlySafe(safe) {
        trustedContractManager.removeTrustedContract(safe, contractAddress);
    }

    /**
     * @notice Check if a contract is trusted by a Safe
     */
    function isTrustedContract(address safe, address contractAddress) external view returns (bool) {
        return trustedContractManager.isTrustedContract(safe, contractAddress);
    }

    /**
     * @notice Get all trusted contract entries for a Safe
     */
    function getTrustedContracts(address safe)
        external
        view
        returns (ITrustedContractManager.TrustedContractEntry[] memory)
    {
        return trustedContractManager.getTrustedContracts(safe);
    }

    // ============ Guard Interface Implementation ============

    /**
     * @notice Implementation of the Guard interface's checkTransaction function
     * @dev This function is called before a Safe transaction is executed
     */
    function checkTransaction(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        uint256,
        uint256,
        uint256,
        address,
        address payable,
        bytes memory,
        address
    ) external override {
        address safe = msg.sender;

        // Always allow the Safe to call itself (needed for owner management, threshold changes, etc.)
        if (to == safe) {
            emit SelfCallAllowed(safe, to);
            return;
        }

        // Always allow the Safe to call this guard contract (needed for address book management)
        if (to == address(this)) {
            emit GuardCallAllowed(safe, address(this));
            return;
        }

        // Check delegate call restrictions
        if (operation == Enum.Operation.DelegateCall) {
            // If delegate calls are not enabled for this Safe, revert
            if (!delegateCallManager.isDelegateCallEnabled(safe)) {
                revert DelegateCallDisabled();
            }

            // If the target is trusted, we can skip the delegate call target restrictions
            bool isTargetTrusted = trustedContractManager.isTrustedContract(safe, to);
            if (!isTargetTrusted) {
                // If delegate calls are enabled, check if there are any specific target restrictions
                // If the target is not explicitly allowed and there are restrictions, revert
                if (
                    !delegateCallManager.isDelegateCallTargetAllowed(safe, to)
                        && delegateCallManager.hasDelegateCallTargetRestrictions(safe)
                ) {
                    revert DelegateCallTargetNotAllowed();
                }
            }
        }

        // Validate the transaction using the transaction validator
        transactionValidator.validateTransaction(safe, to, value, data, operation);
    }

    // Events for debugging guard execution
    event GuardAfterExecuted(bytes32 indexed txHash, address indexed safe, bool success);

    // Events for error handling in checkAfterExecution
    event TransactionNotInPool(bytes32 indexed txHash, address indexed safe);
    event FailedTransactionSkipped(bytes32 indexed txHash, address indexed safe);
    event MarkExecutionFailed(bytes32 indexed txHash, address indexed safe, bytes reason);

    /**
     * @notice Implementation of the Guard interface's checkAfterExecution function
     * @dev This function is called after a Safe transaction is executed
     * @param txHash Hash of the Safe transaction
     * @param success Whether the transaction was successful
     */
    function checkAfterExecution(bytes32 txHash, bool success) external override {
        address safe = msg.sender;

        // Always emit event at the beginning to track guard execution
        emit GuardAfterExecuted(txHash, safe, success);

        // Only proceed if transaction was successful
        if (!success) {
            emit FailedTransactionSkipped(txHash, safe);
            return;
        }

        // Since the transaction hash is the same in the pool and in the Safe,
        // we can directly try to mark the transaction as executed
        try txPoolCore.markAsExecuted(txHash) {
            // Transaction was successfully marked as executed
        } catch (bytes memory reason) {
            // Emit detailed error information for debugging
            emit MarkExecutionFailed(txHash, safe, reason);

            // Check if this is specifically because transaction doesn't exist in pool
            // This is the most common and expected case
            if (reason.length >= 4) {
                bytes4 errorSelector = bytes4(reason);
                // TransactionNotFound() error selector is 0x31fb878f
                if (errorSelector == 0x31fb878f) {
                    emit TransactionNotInPool(txHash, safe);
                }
            }
        }
    }

    /**
     * @notice This function is called by the Safe contract when a function is not found
     * @dev It prevents the Safe from being locked during upgrades
     */
    fallback() external {
        // We do not want to revert here to prevent the Safe from being locked during upgrades
    }
}
