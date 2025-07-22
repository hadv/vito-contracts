// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./SafeTxPoolCore.sol";
import {BaseGuard} from "@safe-global/safe-contracts/contracts/base/GuardManager.sol";
import {Enum} from "@safe-global/safe-contracts/contracts/common/Enum.sol";
import "./interfaces/ISafeTxPoolCore.sol";
import "./interfaces/IAddressBookManager.sol";
import "./interfaces/IDelegateCallManager.sol";
import "./interfaces/ITrustedContractManager.sol";
import "./interfaces/ITransactionValidator.sol";
import "./SafeMessagePool.sol";

/**
 * @title SafePoolRegistry
 * @notice Main coordinator contract that provides a unified interface to all Safe transaction and message pool components
 */
contract SafePoolRegistry is BaseGuard {
    // Custom errors
    error NotProposer();

    ISafeTxPoolCore public immutable txPoolCore;
    SafeMessagePool public immutable messagePool;
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

        // Deploy and configure message pool
        messagePool = new SafeMessagePool();
        messagePool.setRegistry(address(this));
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
    function markTxAsExecuted(bytes32 txHash) external {
        txPoolCore.markAsExecuted(txHash);
    }

    /**
     * @notice Mark a transaction as executed and remove from storage (alias for compatibility)
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
     * @notice Get pending transactions for a Safe
     */
    function getPendingTxs(address safe) external view returns (bytes32[] memory) {
        // Use getPendingTxHashes with no limit to get all pending transactions
        return txPoolCore.getPendingTxHashes(safe, 0, type(uint256).max);
    }

    /**
     * @notice Get signatures for a transaction
     */
    function getTxSignatures(bytes32 txHash) external view returns (bytes[] memory) {
        return txPoolCore.getSignatures(txHash);
    }

    /**
     * @notice Get signatures for a transaction (alias for compatibility)
     */
    function getSignatures(bytes32 txHash) external view returns (bytes[] memory) {
        return txPoolCore.getSignatures(txHash);
    }

    /**
     * @notice Get signature count for a transaction
     */
    function getTxSignatureCount(bytes32 txHash) external view returns (uint256) {
        return txPoolCore.getSignatures(txHash).length;
    }

    /**
     * @notice Check if an address has signed a transaction
     */
    function hasSigned(bytes32 txHash, address signer) external view returns (bool) {
        return txPoolCore.hasSignedTx(txHash, signer);
    }



    /**
     * @notice Get a range of pending transaction hashes for a Safe
     */
    function getPendingTxHashes(address safe, uint256 offset, uint256 limit) external view returns (bytes32[] memory) {
        return txPoolCore.getPendingTxHashes(safe, offset, limit);
    }

    // ============ Delegate Call Management Functions ============

    /**
     * @notice Check if delegate calls are enabled for a Safe
     */
    function isDelegateCallEnabled(address safe) external view returns (bool) {
        return delegateCallManager.isDelegateCallEnabled(safe);
    }

    /**
     * @notice Enable or disable delegate calls for a Safe
     */
    function setDelegateCallEnabled(address safe, bool enabled) external onlySafe(safe) {
        delegateCallManager.setDelegateCallEnabled(safe, enabled);
    }

    /**
     * @notice Check if a target is allowed for delegate calls
     */
    function isDelegateCallTargetAllowed(address safe, address target) external view returns (bool) {
        return delegateCallManager.isDelegateCallTargetAllowed(safe, target);
    }

    /**
     * @notice Add a target for delegate calls
     */
    function addDelegateCallTarget(address safe, address target) external onlySafe(safe) {
        delegateCallManager.addDelegateCallTarget(safe, target);
    }

    /**
     * @notice Remove a target for delegate calls
     */
    function removeDelegateCallTarget(address safe, address target) external onlySafe(safe) {
        delegateCallManager.removeDelegateCallTarget(safe, target);
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

    // ============ Address Book Management Functions ============

    /**
     * @notice Add an entry to the address book
     */
    function addAddressBookEntry(address safe, address walletAddress, bytes32 name) external onlySafe(safe) {
        addressBookManager.addAddressBookEntry(safe, walletAddress, name);
    }

    /**
     * @notice Remove an entry from the address book
     */
    function removeAddressBookEntry(address safe, address walletAddress) external onlySafe(safe) {
        addressBookManager.removeAddressBookEntry(safe, walletAddress);
    }

    /**
     * @notice Get all address book entries for a Safe
     */
    function getAddressBookEntries(address safe) external view returns (IAddressBookManager.AddressBookEntry[] memory) {
        return addressBookManager.getAddressBookEntries(safe);
    }

    /**
     * @notice Check if an address is in the address book
     */
    function isInAddressBook(address safe, address walletAddress) external view returns (bool) {
        return addressBookManager.hasAddressBookEntry(safe, walletAddress);
    }

    // ============ Trusted Contract Management Functions ============

    /**
     * @notice Add a trusted contract
     */
    function addTrustedContract(address safe, address contractAddress, bytes32 name) external onlySafe(safe) {
        trustedContractManager.addTrustedContract(safe, contractAddress, name);
    }

    /**
     * @notice Remove a trusted contract
     */
    function removeTrustedContract(address safe, address contractAddress) external onlySafe(safe) {
        trustedContractManager.removeTrustedContract(safe, contractAddress);
    }

    /**
     * @notice Check if a contract is trusted
     */
    function isTrustedContract(address safe, address contractAddress) external view returns (bool) {
        return trustedContractManager.isTrustedContract(safe, contractAddress);
    }

    /**
     * @notice Get all trusted contracts for a Safe
     */
    function getTrustedContracts(address safe) external view returns (ITrustedContractManager.TrustedContractEntry[] memory) {
        return trustedContractManager.getTrustedContracts(safe);
    }

    // ============ Message Pool Functions ============

    /**
     * @notice Propose a new Safe message for signing
     */
    function proposeMessage(
        bytes32 messageHash,
        address safe,
        bytes calldata message,
        string calldata dAppTopic,
        uint256 dAppRequestId
    ) external {
        messagePool.proposeMessageWithProposer(messageHash, safe, message, dAppTopic, dAppRequestId, msg.sender);
    }

    /**
     * @notice Sign a proposed message
     */
    function signMessage(bytes32 messageHash, bytes calldata signature) external {
        messagePool.signMessage(messageHash, signature);
    }

    /**
     * @notice Mark a message as executed
     */
    function markMessageAsExecuted(bytes32 messageHash) external {
        // Get message details to check if caller is the Safe wallet
        (address safe,,,,,) = messagePool.getMessageDetails(messageHash);

        // Check if caller is the Safe wallet
        require(msg.sender == safe, "Only Safe wallet can mark as executed");

        messagePool.markMessageAsExecuted(messageHash);
    }

    /**
     * @notice Delete a pending message
     */
    function deleteMessage(bytes32 messageHash) external {
        // Get message details to check if caller is the proposer
        (,, address proposer,,,) = messagePool.getMessageDetails(messageHash);

        // Check if caller is the proposer
        if (msg.sender != proposer) revert NotProposer();

        messagePool.deleteMessage(messageHash);
    }

    /**
     * @notice Get message details by hash
     */
    function getMessageDetails(bytes32 messageHash)
        external
        view
        returns (
            address safe,
            bytes memory message,
            address proposer,
            uint256 msgId,
            string memory dAppTopic,
            uint256 dAppRequestId
        )
    {
        return messagePool.getMessageDetails(messageHash);
    }

    /**
     * @notice Get pending messages for a Safe
     */
    function getPendingMessages(address safe) external view returns (bytes32[] memory) {
        return messagePool.getPendingMessages(safe);
    }

    /**
     * @notice Get all messages for a Safe (including executed ones for history)
     */
    function getAllMessages(address safe) external view returns (bytes32[] memory) {
        return messagePool.getAllMessages(safe);
    }

    /**
     * @notice Get signatures for a message
     */
    function getMessageSignatures(bytes32 messageHash) external view returns (bytes[] memory) {
        return messagePool.getMessageSignatures(messageHash);
    }

    /**
     * @notice Get signature count for a message
     */
    function getMessageSignatureCount(bytes32 messageHash) external view returns (uint256) {
        return messagePool.getMessageSignatureCount(messageHash);
    }

    /**
     * @notice Check if an address has signed a message
     */
    function hasSignedMessage(bytes32 messageHash, address signer) external view returns (bool) {
        return messagePool.hasSignedMessage(messageHash, signer);
    }

    // ============ BaseGuard Implementation ============

    /**
     * @notice Called by the Safe before a transaction is executed
     * @dev We don't need to implement any pre-transaction checks for the registry
     */
    function checkTransaction(
        address to,
        uint256 value,
        bytes memory data,
        Enum.Operation operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address payable refundReceiver,
        bytes memory signatures,
        address msgSender
    ) external view override {
        // No pre-transaction checks needed for the registry
        // This is just to satisfy the BaseGuard interface
    }

    /**
     * @notice Called by the Safe after a transaction is executed
     * @dev We don't need to implement any post-transaction checks for the registry
     */
    function checkAfterExecution(bytes32 txHash, bool success) external view override {
        // No post-transaction checks needed for the registry
        // This is just to satisfy the BaseGuard interface
    }

    /**
     * @notice This function is called by the Safe contract when a function is not found
     * @dev It prevents the Safe from being locked during upgrades
     */
    fallback() external {
        // We do not want to revert here to prevent the Safe from being locked during upgrades
    }
}
