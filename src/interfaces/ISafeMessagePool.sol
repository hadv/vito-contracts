// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title ISafeMessagePool
 * @notice Interface for Safe message signing pool with multi-signature support
 * @dev Handles message signing requests from dApps with Safe wallet multi-signature governance
 */
interface ISafeMessagePool {
    // Struct to hold message signing details
    // Uses Safe wallet compliant EIP-712 message hash format:
    // - Type hash: keccak256("SafeMessage(bytes message)") = 0x60b3cbf8b4a223d68d641b3b6ddf9a298e7f33710cf3d3a9d1146b5a6150fbca
    // - Domain separator: EIP712Domain(uint256 chainId,address verifyingContract)
    // - Final hash: keccak256("\x19\x01" + domainSeparator + structHash)
    struct SafeMessage {
        address safe;
        bytes message;
        bytes32 messageHash;
        // Additional fields for proposal management
        address proposer;
        // Signature management
        bytes[] signatures;
        // Message ID to distinguish between reused message hashes
        uint256 msgId;
        // dApp session info for WalletConnect responses
        string dAppTopic;
        uint256 dAppRequestId;
    }

    // Events
    event MessageProposed(
        bytes32 indexed messageHash,
        address indexed proposer,
        address indexed safe,
        bytes message,
        uint256 msgId,
        string dAppTopic,
        uint256 dAppRequestId
    );

    event MessageSigned(bytes32 indexed messageHash, address indexed signer, bytes signature, uint256 msgId);



    event MessageDeleted(bytes32 indexed messageHash, address indexed safe, address indexed proposer, uint256 msgId);

    // Errors
    error AlreadySigned();
    error MessageNotFound();
    error NotSafeWallet();
    error NotProposer();

    // ============ Core Functions ============

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
    ) external;

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
    ) external;

    /**
     * @notice Sign a proposed message
     * @param messageHash Hash of the Safe message to sign
     * @param signature Owner's signature of the message
     */
    function signMessage(bytes32 messageHash, bytes calldata signature) external;



    /**
     * @notice Delete a pending message
     * @param messageHash Hash of the Safe message to delete
     */
    function deleteMessage(bytes32 messageHash) external;

    // ============ View Functions ============

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
        );

    /**
     * @notice Get pending messages for a Safe
     * @param safe The Safe wallet address
     * @return Array of pending message hashes
     */
    function getPendingMessages(address safe) external view returns (bytes32[] memory);

    /**
     * @notice Get all message hashes for a Safe (including executed ones for history)
     * @param safe The Safe wallet address
     * @return Array of all message hashes
     */
    function getAllMessages(address safe) external view returns (bytes32[] memory);

    /**
     * @notice Get signatures for a message
     * @param messageHash Hash of the Safe message
     * @return Array of signatures
     */
    function getMessageSignatures(bytes32 messageHash) external view returns (bytes[] memory);

    /**
     * @notice Get signature count for a message
     * @param messageHash Hash of the Safe message
     * @return Number of signatures collected
     */
    function getMessageSignatureCount(bytes32 messageHash) external view returns (uint256);

    /**
     * @notice Check if an address has signed a message
     * @param messageHash Hash of the Safe message
     * @param signer Address to check
     * @return True if the address has signed
     */
    function hasSignedMessage(bytes32 messageHash, address signer) external view returns (bool);

    /**
     * @notice Set the registry address (only callable once)
     */
    function setRegistry(address _registry) external;
}
