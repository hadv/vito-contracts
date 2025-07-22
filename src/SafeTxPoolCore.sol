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

    // Counter for message IDs
    uint256 private _msgIdCounter;

    // Mapping from transaction hash to SafeTx
    mapping(bytes32 => SafeTx) public transactions;

    // Mapping from message hash to SafeMessage
    mapping(bytes32 => SafeMessage) public messages;

    // Mapping from transaction hash and ID to signer's signature status
    mapping(bytes32 => mapping(uint256 => mapping(address => bool))) private hasSignedByTxId;

    // Mapping from message hash and ID to signer's signature status
    mapping(bytes32 => mapping(uint256 => mapping(address => bool))) private hasSignedMessageByMsgId;

    // Mapping from Safe address to array of pending transaction hashes
    mapping(address => bytes32[]) private pendingTxsBySafe;

    // Mapping from Safe address to array of pending message hashes
    mapping(address => bytes32[]) private pendingMessagesBySafe;

    // Mapping from Safe address to array of all message hashes (for history)
    mapping(address => bytes32[]) private allMessagesBySafe;

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

    // ============ Message Pool Functions ============

    /**
     * @notice Propose a new Safe message for signing
     * @param messageHash Hash of the Safe message
     * @param safe The Safe wallet address
     * @param message The message to be signed
     * @param dAppTopic WalletConnect topic for dApp response
     * @param dAppRequestId WalletConnect request ID for dApp response
     */
    function proposeMessage(
        bytes32 messageHash,
        address safe,
        bytes calldata message,
        string calldata dAppTopic,
        uint256 dAppRequestId
    ) external {
        _proposeMessage(messageHash, safe, message, dAppTopic, dAppRequestId, msg.sender);
    }

    function proposeMessageWithProposer(
        bytes32 messageHash,
        address safe,
        bytes calldata message,
        string calldata dAppTopic,
        uint256 dAppRequestId,
        address proposer
    ) external {
        // Only registry can call this function
        require(msg.sender == registry, "Only registry can specify proposer");
        _proposeMessage(messageHash, safe, message, dAppTopic, dAppRequestId, proposer);
    }

    function _proposeMessage(
        bytes32 messageHash,
        address safe,
        bytes calldata message,
        string calldata dAppTopic,
        uint256 dAppRequestId,
        address proposer
    ) internal {
        // Ensure message hasn't been proposed before
        require(messages[messageHash].proposer == address(0), "Message already proposed");

        // Create a new message ID
        uint256 msgId = ++_msgIdCounter;

        SafeMessage storage newMessage = messages[messageHash];
        newMessage.safe = safe;
        newMessage.message = message;
        newMessage.messageHash = messageHash;
        newMessage.proposer = proposer;
        newMessage.msgId = msgId;
        newMessage.dAppTopic = dAppTopic;
        newMessage.dAppRequestId = dAppRequestId;

        // Add to pending messages for this Safe
        pendingMessagesBySafe[safe].push(messageHash);

        // Add to all messages for this Safe (for history)
        allMessagesBySafe[safe].push(messageHash);

        emit MessageProposed(messageHash, proposer, safe, message, msgId, dAppTopic, dAppRequestId);
    }

    /**
     * @notice Sign a proposed message
     * @param messageHash Hash of the Safe message to sign
     * @param signature Owner's signature of the message
     */
    function signMessage(bytes32 messageHash, bytes calldata signature) external {
        SafeMessage storage safeMessage = messages[messageHash];

        // Check if message exists
        if (safeMessage.proposer == address(0)) revert MessageNotFound();

        uint256 msgId = safeMessage.msgId;

        // Recover signer from signature
        address signer = _recoverMessageSigner(messageHash, signature);

        // Check if signer hasn't already signed
        if (hasSignedMessageByMsgId[messageHash][msgId][signer]) revert AlreadySigned();

        // Store signature
        safeMessage.signatures.push(signature);
        hasSignedMessageByMsgId[messageHash][msgId][signer] = true;

        emit MessageSigned(messageHash, signer, signature, msgId);
    }

    /**
     * @notice Mark a message as executed (keep in storage for history)
     * @param messageHash Hash of the Safe message
     */
    function markMessageAsExecuted(bytes32 messageHash) external {
        SafeMessage storage safeMessage = messages[messageHash];

        // Check if message exists
        if (safeMessage.proposer == address(0)) revert MessageNotFound();

        // Check if caller is the Safe wallet, this contract, or the registry
        if (msg.sender != safeMessage.safe && msg.sender != address(this) && msg.sender != registry) {
            revert NotSafeWallet();
        }

        uint256 msgId = safeMessage.msgId;
        address safe = safeMessage.safe;

        // Remove from pending messages for this Safe (but keep message data for history)
        _removeMessageFromPending(safe, messageHash);

        // NOTE: We do NOT delete message data - keep it for history/audit trail
        // This is different from transactions which are removed after execution

        emit MessageExecuted(messageHash, safe, msgId);
    }

    /**
     * @notice Delete a pending message
     * @param messageHash Hash of the Safe message to delete
     */
    function deleteMessage(bytes32 messageHash) external {
        SafeMessage storage safeMessage = messages[messageHash];

        // Check if message exists
        if (safeMessage.proposer == address(0)) revert MessageNotFound();

        // Check if caller is the proposer, the Safe wallet, this contract, or the registry
        if (
            msg.sender != safeMessage.proposer && msg.sender != safeMessage.safe && msg.sender != address(this)
                && msg.sender != registry
        ) revert NotProposer();

        uint256 msgId = safeMessage.msgId;
        address safe = safeMessage.safe;
        address proposer = safeMessage.proposer;

        // Remove from pending messages for this Safe
        _removeMessageFromPending(safe, messageHash);

        // Remove from all messages for this Safe
        _removeMessageFromAll(safe, messageHash);

        // Delete message data
        delete messages[messageHash];

        emit MessageDeleted(messageHash, safe, proposer, msgId);
    }

    /**
     * @notice Get message details by hash
     * @param messageHash Hash of the Safe message
     * @return safe The Safe wallet address
     * @return message The message data
     * @return proposer Address of proposer
     * @return msgId Message ID
     * @return dAppTopic WalletConnect topic
     * @return dAppRequestId WalletConnect request ID
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
        SafeMessage storage safeMessage = messages[messageHash];
        return (
            safeMessage.safe,
            safeMessage.message,
            safeMessage.proposer,
            safeMessage.msgId,
            safeMessage.dAppTopic,
            safeMessage.dAppRequestId
        );
    }

    /**
     * @notice Get pending messages for a Safe
     * @param safe The Safe wallet address
     * @return Array of pending message hashes
     */
    function getPendingMessages(address safe) external view returns (bytes32[] memory) {
        return pendingMessagesBySafe[safe];
    }

    /**
     * @notice Get all message hashes for a Safe (including executed ones for history)
     * @param safe The Safe wallet address
     * @return Array of all message hashes
     */
    function getAllMessages(address safe) external view returns (bytes32[] memory) {
        return allMessagesBySafe[safe];
    }

    /**
     * @notice Get signatures for a message
     * @param messageHash Hash of the Safe message
     * @return Array of signatures
     */
    function getMessageSignatures(bytes32 messageHash) external view returns (bytes[] memory) {
        return messages[messageHash].signatures;
    }

    /**
     * @notice Get signature count for a message
     * @param messageHash Hash of the Safe message
     * @return Number of signatures collected
     */
    function getMessageSignatureCount(bytes32 messageHash) external view returns (uint256) {
        return messages[messageHash].signatures.length;
    }

    /**
     * @notice Check if an address has signed a message
     * @param messageHash Hash of the Safe message
     * @param signer Address to check
     * @return True if the address has signed
     */
    function hasSignedMessage(bytes32 messageHash, address signer) external view returns (bool) {
        SafeMessage storage safeMessage = messages[messageHash];
        if (safeMessage.proposer == address(0)) return false;
        return hasSignedMessageByMsgId[messageHash][safeMessage.msgId][signer];
    }

    /**
     * @notice Remove a message from pending list for a Safe
     * @param safe The Safe wallet address
     * @param messageHash Hash of the message to remove
     */
    function _removeMessageFromPending(address safe, bytes32 messageHash) internal {
        bytes32[] storage pendingMessages = pendingMessagesBySafe[safe];

        for (uint256 i = 0; i < pendingMessages.length; i++) {
            if (pendingMessages[i] == messageHash) {
                // Move last element to current position and pop
                pendingMessages[i] = pendingMessages[pendingMessages.length - 1];
                pendingMessages.pop();
                break;
            }
        }
    }

    /**
     * @notice Remove a message from all messages list for a Safe
     * @param safe The Safe wallet address
     * @param messageHash Hash of the message to remove
     */
    function _removeMessageFromAll(address safe, bytes32 messageHash) internal {
        bytes32[] storage allMessages = allMessagesBySafe[safe];

        for (uint256 i = 0; i < allMessages.length; i++) {
            if (allMessages[i] == messageHash) {
                // Move last element to current position and pop
                allMessages[i] = allMessages[allMessages.length - 1];
                allMessages.pop();
                break;
            }
        }
    }

    /**
     * @notice Recover signer from message signature
     * @param messageHash Hash of the Safe message
     * @param signature Signature to recover from
     * @return Recovered signer address
     */
    function _recoverMessageSigner(bytes32 messageHash, bytes memory signature) internal view returns (address) {
        bytes32 r;
        bytes32 s;
        uint8 v;

        assembly ("memory-safe") {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }

        // Get the message details to reconstruct the Safe message hash
        SafeMessage storage safeMessage = messages[messageHash];

        // Reconstruct the Safe message hash that was actually signed
        bytes32 safeMessageHash = _getSafeMessageHash(safeMessage);

        return ecrecover(safeMessageHash, v, r, s);
    }

    /**
     * @notice Reconstruct the Safe message hash for EIP-1271 signing (compliant with Safe wallet format)
     * @param safeMessage The Safe message data
     * @return The Safe message hash that should be signed
     */
    function _getSafeMessageHash(SafeMessage storage safeMessage) internal view returns (bytes32) {
        // Safe message type hash: keccak256("SafeMessage(bytes message)")
        // Correct type hash: 0x60b3cbf8b4a223d68d641b3b6ddf9a298e7f33710cf3d3a9d1146b5a6150fbca
        bytes32 SAFE_MSG_TYPEHASH = 0x60b3cbf8b4a223d68d641b3b6ddf9a298e7f33710cf3d3a9d1146b5a6150fbca;

        // EIP-712 domain separator for the Safe (using Safe's domain format)
        bytes32 domainSeparator = keccak256(
            abi.encode(
                keccak256("EIP712Domain(uint256 chainId,address verifyingContract)"), block.chainid, safeMessage.safe
            )
        );

        // Safe message struct hash (using Safe's format)
        bytes32 safeMessageStructHash = keccak256(abi.encode(SAFE_MSG_TYPEHASH, keccak256(safeMessage.message)));

        // Final Safe message hash (EIP-712 format compatible with Safe wallet)
        return keccak256(abi.encodePacked("\x19\x01", domainSeparator, safeMessageStructHash));
    }
}
