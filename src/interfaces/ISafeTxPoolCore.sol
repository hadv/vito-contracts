// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Enum} from "@safe-global/safe-contracts/contracts/common/Enum.sol";

/**
 * @title ISafeTxPoolCore
 * @notice Interface for core Safe transaction pool functionality
 */
interface ISafeTxPoolCore {
    // Struct to hold transaction details
    struct SafeTx {
        address safe;
        address to;
        uint256 value;
        bytes data;
        Enum.Operation operation;
        // Additional fields for proposal management
        address proposer;
        // Signature management
        bytes[] signatures;
        // Safe transaction nonce
        uint256 nonce;
        // Transaction ID to distinguish between reused transaction hashes
        uint256 txId;
    }

    // Events
    event TransactionProposed(
        bytes32 indexed txHash,
        address indexed proposer,
        address indexed safe,
        address to,
        uint256 value,
        bytes data,
        Enum.Operation operation,
        uint256 nonce,
        uint256 txId
    );

    event TransactionSigned(bytes32 indexed txHash, address indexed signer, bytes signature, uint256 txId);

    event TransactionExecuted(bytes32 indexed txHash, address indexed safe, uint256 txId);

    event TransactionDeleted(bytes32 indexed txHash, address indexed safe, address indexed proposer, uint256 txId);

    event TransactionRemovedFromPending(bytes32 indexed txHash, address indexed safe, uint256 txId, string reason);

    event BatchTransactionsRemovedFromPending(address indexed safe, uint256 nonce, uint256 count, string reason);

    // Errors
    error AlreadySigned();
    error TransactionNotFound();
    error NotSafeWallet();
    error NotProposer();

    /**
     * @notice Propose a new Safe transaction
     * @param txHash Hash of the Safe transaction
     * @param safe The Safe wallet address
     * @param to Destination address of Safe transaction
     * @param value Ether value of Safe transaction
     * @param data Data payload of Safe transaction
     * @param operation Operation type of Safe transaction
     * @param nonce Safe transaction nonce
     */
    function proposeTx(
        bytes32 txHash,
        address safe,
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation,
        uint256 nonce
    ) external;

    /**
     * @notice Propose a new Safe transaction with explicit proposer (only callable by registry)
     */
    function proposeTxWithProposer(
        bytes32 txHash,
        address safe,
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation,
        uint256 nonce,
        address proposer
    ) external;

    /**
     * @notice Sign a proposed transaction
     * @param txHash Hash of the Safe transaction to sign
     * @param signature Owner's signature of the transaction
     */
    function signTx(bytes32 txHash, bytes calldata signature) external;

    /**
     * @notice Mark a transaction as executed and remove from storage
     * @param txHash Hash of the Safe transaction
     */
    function markAsExecuted(bytes32 txHash) external;

    /**
     * @notice Delete a pending transaction
     * @param txHash Hash of the Safe transaction to delete
     */
    function deleteTx(bytes32 txHash) external;

    /**
     * @notice Get transaction details by hash
     * @param txHash Hash of the Safe transaction
     * @return safe The Safe wallet address
     * @return to Destination address
     * @return value Ether value
     * @return data Transaction data
     * @return operation Operation type
     * @return proposer Address of proposer
     * @return nonce Safe transaction nonce
     * @return txId Transaction ID
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
        );

    /**
     * @notice Get all signatures for a transaction
     * @param txHash Hash of the Safe transaction
     * @return Array of signatures
     */
    function getSignatures(bytes32 txHash) external view returns (bytes[] memory);

    /**
     * @notice Check if an address has signed a transaction
     * @param txHash Hash of the Safe transaction
     * @param signer Address to check
     * @return True if the address has signed
     */
    function hasSignedTx(bytes32 txHash, address signer) external view returns (bool);

    /**
     * @notice Get a range of pending transaction hashes for a Safe
     * @param safe The Safe wallet address
     * @param offset Starting index of the range (0-based)
     * @param limit Maximum number of transactions to return
     * @return Array of pending transaction hashes
     */
    function getPendingTxHashes(address safe, uint256 offset, uint256 limit) external view returns (bytes32[] memory);
}
