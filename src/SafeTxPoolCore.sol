// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Enum} from "@safe-global/safe-contracts/contracts/common/Enum.sol";
import "./interfaces/ISafeTxPoolCore.sol";

/**
 * @title SafeTxPoolCore
 * @notice Core Safe transaction pool functionality
 */
contract SafeTxPoolCore is ISafeTxPoolCore {
    // Registry contract that can call this core
    address public registry;

    // Counter for transaction IDs
    uint256 private _txIdCounter;

    // Mapping from transaction hash to SafeTx
    mapping(bytes32 => SafeTx) public transactions;

    // Mapping from transaction hash and ID to signer's signature status
    mapping(bytes32 => mapping(uint256 => mapping(address => bool))) private hasSignedByTxId;

    // Mapping from Safe address to array of pending transaction hashes
    mapping(address => bytes32[]) private pendingTxsBySafe;

    /**
     * @notice Set the registry address (only callable once)
     * @param _registry The registry contract address
     */
    function setRegistry(address _registry) external {
        require(registry == address(0), "Registry already set");
        require(_registry != address(0), "Invalid registry address");
        registry = _registry;
    }

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
        _proposeTx(txHash, safe, to, value, data, operation, nonce, msg.sender);
    }

    function proposeTxWithProposer(
        bytes32 txHash,
        address safe,
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation,
        uint256 nonce,
        address proposer
    ) external {
        // Only registry can call this function
        require(msg.sender == registry, "Only registry can specify proposer");
        _proposeTx(txHash, safe, to, value, data, operation, nonce, proposer);
    }

    function _proposeTx(
        bytes32 txHash,
        address safe,
        address to,
        uint256 value,
        bytes calldata data,
        Enum.Operation operation,
        uint256 nonce,
        address proposer
    ) internal {
        // Ensure transaction hasn't been proposed before
        require(transactions[txHash].proposer == address(0), "Transaction already proposed");

        // Create a new transaction ID
        uint256 txId = ++_txIdCounter;

        SafeTx storage newTx = transactions[txHash];
        newTx.safe = safe;
        newTx.to = to;
        newTx.value = value;
        newTx.data = data;
        newTx.operation = operation;
        newTx.proposer = proposer;
        newTx.nonce = nonce;
        newTx.txId = txId;

        // Add to pending transactions for this Safe
        pendingTxsBySafe[safe].push(txHash);

        // Emit event
        emit TransactionProposed(txHash, proposer, safe, to, value, data, operation, nonce, txId);
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

        uint256 txId = safeTx.txId;

        // Recover signer from signature
        address signer = _recoverSigner(txHash, signature);

        // Check if signer hasn't already signed
        if (hasSignedByTxId[txHash][txId][signer]) revert AlreadySigned();

        // Store signature
        safeTx.signatures.push(signature);
        hasSignedByTxId[txHash][txId][signer] = true;

        emit TransactionSigned(txHash, signer, signature, txId);
    }

    /**
     * @notice Mark a transaction as executed and remove from storage
     * @param txHash Hash of the Safe transaction
     */
    function markAsExecuted(bytes32 txHash) external {
        SafeTx storage safeTx = transactions[txHash];

        // Check if transaction exists
        if (safeTx.proposer == address(0)) revert TransactionNotFound();

        // Check if caller is the Safe wallet, this contract, or the registry
        if (msg.sender != safeTx.safe && msg.sender != address(this) && msg.sender != registry) revert NotSafeWallet();

        uint256 txId = safeTx.txId;
        address safe = safeTx.safe;

        // Remove from pending transactions for this Safe
        _removeFromPending(safe, txHash);

        // Delete transaction data
        delete transactions[txHash];

        emit TransactionExecuted(txHash, safe, txId);
    }

    /**
     * @notice Mark a transaction as executed by Safe address (handles nonce mismatch)
     * @dev This method finds the transaction by Safe address and marks the most recent one as executed
     * @param safeAddress Address of the Safe wallet
     * @param executionTxHash Hash from Safe execution (may not match stored hash due to nonce difference)
     */
    function markAsExecutedBySafe(address safeAddress, bytes32 executionTxHash) external {
        // Only allow calls from the Safe itself or the registry
        if (msg.sender != safeAddress && msg.sender != registry) revert NotSafeWallet();

        // Get pending transactions for this Safe
        bytes32[] storage pendingTxs = pendingTransactions[safeAddress];

        if (pendingTxs.length == 0) {
            // No pending transactions, nothing to mark as executed
            return;
        }

        // Find the most recent executable transaction (with enough signatures)
        bytes32 txHashToExecute;
        uint256 indexToRemove;
        bool found = false;

        // Check transactions in reverse order (most recent first)
        for (uint256 i = pendingTxs.length; i > 0; i--) {
            uint256 index = i - 1;
            bytes32 txHash = pendingTxs[index];
            SafeTx storage safeTx = transactions[txHash];

            if (safeTx.proposer != address(0)) {
                // Check if this transaction has enough signatures to be executable
                uint256 signatureCount = 0;
                for (uint256 j = 0; j < safeTx.signatures.length; j++) {
                    if (safeTx.signatures[j].length > 0) {
                        signatureCount++;
                    }
                }

                // If this transaction is executable, mark it as executed
                if (signatureCount > 0) {
                    txHashToExecute = txHash;
                    indexToRemove = index;
                    found = true;
                    break;
                }
            }
        }

        if (found) {
            SafeTx storage safeTx = transactions[txHashToExecute];
            uint256 txId = safeTx.txId;

            // Remove from pending transactions array
            pendingTxs[indexToRemove] = pendingTxs[pendingTxs.length - 1];
            pendingTxs.pop();

            // Delete transaction data
            delete transactions[txHashToExecute];

            emit TransactionExecuted(txHashToExecute, safeAddress, txId);
        }
    }

    /**
     * @notice Delete a pending transaction
     * @param txHash Hash of the Safe transaction to delete
     */
    function deleteTx(bytes32 txHash) external {
        SafeTx storage safeTx = transactions[txHash];

        // Check if transaction exists
        if (safeTx.proposer == address(0)) revert TransactionNotFound();

        // Check if caller is the proposer or the registry (which handles access control)
        if (msg.sender != safeTx.proposer && msg.sender != registry) revert NotProposer();

        // Get Safe address and transaction ID before deletion
        address safe = safeTx.safe;
        address proposer = safeTx.proposer;
        uint256 txId = safeTx.txId;

        // Remove specific transaction from pending list
        bytes32[] storage pendingTxs = pendingTxsBySafe[safe];
        for (uint256 i = pendingTxs.length; i > 0; i--) {
            uint256 currentIndex = i - 1;
            if (pendingTxs[currentIndex] == txHash) {
                // Move last element to current position and pop
                pendingTxs[currentIndex] = pendingTxs[pendingTxs.length - 1];
                pendingTxs.pop();

                // Emit event for transaction removal from pending
                emit TransactionRemovedFromPending(txHash, safe, txId, "deleted");
                break;
            }
        }

        // Delete transaction data
        delete transactions[txHash];

        emit TransactionDeleted(txHash, safe, proposer, txId);
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
        )
    {
        SafeTx storage safeTx = transactions[txHash];
        return (
            safeTx.safe,
            safeTx.to,
            safeTx.value,
            safeTx.data,
            safeTx.operation,
            safeTx.proposer,
            safeTx.nonce,
            safeTx.txId
        );
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
        SafeTx storage safeTx = transactions[txHash];
        if (safeTx.proposer == address(0)) return false;

        return hasSignedByTxId[txHash][safeTx.txId][signer];
    }

    /**
     * @notice Get a range of pending transaction hashes for a Safe
     * @param safe The Safe wallet address
     * @param offset Starting index of the range (0-based)
     * @param limit Maximum number of transactions to return
     * @return Array of pending transaction hashes
     */
    function getPendingTxHashes(address safe, uint256 offset, uint256 limit) external view returns (bytes32[] memory) {
        bytes32[] storage allPendingTxs = pendingTxsBySafe[safe];
        uint256 totalLength = allPendingTxs.length;

        // If offset is beyond array length, return empty array
        if (offset >= totalLength) {
            return new bytes32[](0);
        }

        // Calculate actual limit to avoid out of bounds
        uint256 actualLimit = limit;
        if (offset + limit > totalLength) {
            actualLimit = totalLength - offset;
        }

        // Create new array with the correct size
        bytes32[] memory result = new bytes32[](actualLimit);

        // Copy the requested range
        for (uint256 i = 0; i < actualLimit; i++) {
            result[i] = allPendingTxs[offset + i];
        }

        return result;
    }

    /**
     * @notice Remove a transaction and all transactions with the same nonce from pending list for a Safe
     * @param safe The Safe wallet address
     * @param txHash Hash of the transaction to remove
     */
    function _removeFromPending(address safe, bytes32 txHash) internal {
        bytes32[] storage pendingTxs = pendingTxsBySafe[safe];
        uint256 targetNonce = transactions[txHash].nonce;
        uint256 removedCount = 0;

        // Iterate through pending transactions from end to start to handle removals safely
        for (uint256 i = pendingTxs.length; i > 0; i--) {
            uint256 currentIndex = i - 1;
            bytes32 currentTxHash = pendingTxs[currentIndex];

            // Check if current transaction has the same nonce
            if (transactions[currentTxHash].nonce == targetNonce) {
                // Get transaction details before removal for event emission
                uint256 txId = transactions[currentTxHash].txId;

                // Move last element to current position and pop
                pendingTxs[currentIndex] = pendingTxs[pendingTxs.length - 1];
                pendingTxs.pop();

                // Emit event for individual transaction removal
                // All transactions with the same nonce are removed due to nonce consumption
                emit TransactionRemovedFromPending(currentTxHash, safe, txId, "nonce_consumed");
                removedCount++;
            }
        }

        // Emit batch removal event if multiple transactions were removed
        if (removedCount > 1) {
            emit BatchTransactionsRemovedFromPending(safe, targetNonce, removedCount, "nonce_consumed");
        }
    }

    /**
     * @notice Recover signer from EIP-712 signature
     * @param txHash Hash of the Safe transaction (used to reconstruct EIP-712 hash)
     * @param signature Signature to recover from
     * @return Recovered signer address
     */
    function _recoverSigner(bytes32 txHash, bytes memory signature) internal view returns (address) {
        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly ("memory-safe") {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        // Get the transaction details to reconstruct the EIP-712 hash
        SafeTx storage safeTx = transactions[txHash];

        // Reconstruct the EIP-712 hash that was actually signed
        bytes32 eip712Hash = _getEIP712Hash(safeTx);

        return ecrecover(eip712Hash, v, r, s);
    }

    /**
     * @notice Reconstruct the EIP-712 hash for a Safe transaction
     * @param safeTx The Safe transaction data
     * @return The EIP-712 hash that should be signed
     */
    function _getEIP712Hash(SafeTx storage safeTx) internal view returns (bytes32) {
        // EIP-712 domain separator
        bytes32 domainSeparator = keccak256(
            abi.encode(keccak256("EIP712Domain(uint256 chainId,address verifyingContract)"), block.chainid, safeTx.safe)
        );

        // Safe transaction struct hash
        bytes32 safeTxHash = keccak256(
            abi.encode(
                keccak256(
                    "SafeTx(address to,uint256 value,bytes data,uint8 operation,uint256 safeTxGas,uint256 baseGas,uint256 gasPrice,address gasToken,address refundReceiver,uint256 nonce)"
                ),
                safeTx.to,
                safeTx.value,
                keccak256(safeTx.data),
                safeTx.operation,
                0, // safeTxGas
                0, // baseGas
                0, // gasPrice
                address(0), // gasToken
                address(0), // refundReceiver
                safeTx.nonce
            )
        );

        // Final EIP-712 hash
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, safeTxHash));
    }
}
