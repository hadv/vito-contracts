// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./interfaces/ISafeMessagePool.sol";

/**
 * @title SafeMessagePool
 * @notice Safe message signing pool with multi-signature support for dApp integrations
 * @dev Handles message signing requests from dApps with Safe wallet multi-signature governance
 */
contract SafeMessagePool is ISafeMessagePool {
    // Registry address for access control
    address public registry;

    // Counter for message IDs
    uint256 private _msgIdCounter;

    // Mapping from message hash to SafeMessage
    mapping(bytes32 => SafeMessage) public messages;

    // Mapping from message hash and ID to signer's signature status
    mapping(bytes32 => mapping(uint256 => mapping(address => bool))) private hasSignedMessageByMsgId;

    // Mapping from Safe address to array of pending message hashes
    mapping(address => bytes32[]) private pendingMessagesBySafe;

    // Mapping from Safe address to array of all message hashes (for history)
    mapping(address => bytes32[]) private allMessagesBySafe;

    /**
     * @notice Set the registry address (only callable once)
     */
    function setRegistry(address _registry) external {
        require(registry == address(0), "Registry already set");
        registry = _registry;
    }

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

    /**
     * @notice Propose a new Safe message for signing with explicit proposer (only callable by registry)
     */
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

    /**
     * @notice Internal function to propose a message
     */
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
     * @notice Delete a pending message
     * @param messageHash Hash of the Safe message to delete
     */
    function deleteMessage(bytes32 messageHash) external {
        SafeMessage storage safeMessage = messages[messageHash];

        // Check if message exists
        if (safeMessage.proposer == address(0)) revert MessageNotFound();

        // Check if caller is the proposer, the Safe wallet, this contract, or the registry
        // The registry handles access control, so we allow it to delete messages
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
     */
    function getPendingMessages(address safe) external view returns (bytes32[] memory) {
        return pendingMessagesBySafe[safe];
    }

    /**
     * @notice Get all message hashes for a Safe (for history)
     */
    function getAllMessages(address safe) external view returns (bytes32[] memory) {
        return allMessagesBySafe[safe];
    }

    /**
     * @notice Get signatures for a message
     */
    function getMessageSignatures(bytes32 messageHash) external view returns (bytes[] memory) {
        return messages[messageHash].signatures;
    }

    /**
     * @notice Get signature count for a message
     */
    function getMessageSignatureCount(bytes32 messageHash) external view returns (uint256) {
        return messages[messageHash].signatures.length;
    }

    /**
     * @notice Check if an address has signed a message
     */
    function hasSignedMessage(bytes32 messageHash, address signer) external view returns (bool) {
        SafeMessage storage safeMessage = messages[messageHash];
        if (safeMessage.proposer == address(0)) return false;
        return hasSignedMessageByMsgId[messageHash][safeMessage.msgId][signer];
    }

    /**
     * @notice Remove a message from pending list for a Safe
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
