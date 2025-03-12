// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Enum} from "@safe-global/safe-contracts/contracts/common/Enum.sol";

contract SafeTxPool {
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
        mapping(address => bool) hasSignedBy;
        // Safe transaction nonce
        uint256 nonce;
    }

    // Mapping from transaction hash to SafeTx
    mapping(bytes32 => SafeTx) public transactions;

    // Mapping from Safe address to array of pending transaction hashes
    mapping(address => bytes32[]) private pendingTxsBySafe;

    event TransactionProposed(
        bytes32 indexed txHash,
        address indexed proposer,
        address indexed safe,
        address to,
        uint256 value,
        bytes data,
        Enum.Operation operation,
        uint256 nonce
    );

    event TransactionSigned(bytes32 indexed txHash, address indexed signer, bytes signature);

    event TransactionExecuted(bytes32 indexed txHash, address indexed safe);

    event TransactionDeleted(bytes32 indexed txHash, address indexed safe, address indexed proposer);

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
    ) external {
        // Ensure transaction hasn't been proposed before
        require(transactions[txHash].proposer == address(0), "Transaction already proposed");

        SafeTx storage newTx = transactions[txHash];
        newTx.safe = safe;
        newTx.to = to;
        newTx.value = value;
        newTx.data = data;
        newTx.operation = operation;
        newTx.proposer = msg.sender;
        newTx.nonce = nonce;

        // Add to pending transactions for this Safe
        pendingTxsBySafe[safe].push(txHash);

        // Emit event
        emit TransactionProposed(txHash, msg.sender, safe, to, value, data, operation, nonce);
    }

    /**
     * @notice Sign a proposed transaction
     * @param txHash Hash of the Safe transaction to sign
     * @param signature Owner's signature of the transaction
     */
    function signTx(bytes32 txHash, bytes calldata signature) external {
        SafeTx storage safeTx = transactions[txHash];

        // Check if transaction exists
        if (safeTx.proposer == address(0)) revert TransactionNotFound();

        // Recover signer from signature
        address signer = _recoverSigner(txHash, signature);

        // Check if signer hasn't already signed
        if (safeTx.hasSignedBy[signer]) revert AlreadySigned();

        // Store signature
        safeTx.signatures.push(signature);
        safeTx.hasSignedBy[signer] = true;

        emit TransactionSigned(txHash, signer, signature);
    }

    /**
     * @notice Mark a transaction as executed and remove from storage
     * @param txHash Hash of the Safe transaction
     */
    function markAsExecuted(bytes32 txHash) external {
        SafeTx storage safeTx = transactions[txHash];

        // Check if transaction exists
        if (safeTx.proposer == address(0)) revert TransactionNotFound();

        // Check if caller is the Safe wallet
        if (msg.sender != safeTx.safe) revert NotSafeWallet();

        // Remove from pending transactions for this Safe
        _removeFromPending(safeTx.safe, txHash);

        // Delete transaction data
        delete transactions[txHash];

        emit TransactionExecuted(txHash, msg.sender);
    }

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
            uint256 nonce
        )
    {
        SafeTx storage safeTx = transactions[txHash];
        return (safeTx.safe, safeTx.to, safeTx.value, safeTx.data, safeTx.operation, safeTx.proposer, safeTx.nonce);
    }

    /**
     * @notice Get all signatures for a transaction
     * @param txHash Hash of the Safe transaction
     * @return Array of signatures
     */
    function getSignatures(bytes32 txHash) external view returns (bytes[] memory) {
        return transactions[txHash].signatures;
    }

    /**
     * @notice Check if an address has signed a transaction
     * @param txHash Hash of the Safe transaction
     * @param signer Address to check
     * @return True if the address has signed
     */
    function hasSignedTx(bytes32 txHash, address signer) external view returns (bool) {
        return transactions[txHash].hasSignedBy[signer];
    }

    /**
     * @notice Get all pending transaction hashes for a Safe
     * @param safe The Safe wallet address
     * @return Array of pending transaction hashes
     */
    function getPendingTxHashes(address safe) external view returns (bytes32[] memory) {
        return pendingTxsBySafe[safe];
    }

    /**
     * @notice Remove a transaction from pending list for a Safe
     * @param safe The Safe wallet address
     * @param txHash Hash of the transaction to remove
     */
    function _removeFromPending(address safe, bytes32 txHash) internal {
        bytes32[] storage pendingTxs = pendingTxsBySafe[safe];
        for (uint256 i = 0; i < pendingTxs.length; i++) {
            if (pendingTxs[i] == txHash) {
                // Move last element to current position and pop
                pendingTxs[i] = pendingTxs[pendingTxs.length - 1];
                pendingTxs.pop();
                break;
            }
        }
    }

    /**
     * @notice Recover signer from signature
     * @param txHash Hash of the Safe transaction
     * @param signature Signature to recover from
     * @return Recovered signer address
     */
    function _recoverSigner(bytes32 txHash, bytes memory signature) internal pure returns (address) {
        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly ("memory-safe") {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        return ecrecover(txHash, v, r, s);
    }

    /**
     * @notice Delete a pending transaction
     * @param txHash Hash of the Safe transaction to delete
     */
    function deleteTx(bytes32 txHash) external {
        SafeTx storage safeTx = transactions[txHash];

        // Check if transaction exists
        if (safeTx.proposer == address(0)) revert TransactionNotFound();

        // Check if caller is the proposer
        if (msg.sender != safeTx.proposer) revert NotProposer();

        // Remove from pending transactions for this Safe
        _removeFromPending(safeTx.safe, txHash);

        // Delete transaction data
        delete transactions[txHash];

        emit TransactionDeleted(txHash, safeTx.safe, msg.sender);
    }
}
