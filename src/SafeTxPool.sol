// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import {Enum} from "@safe-global/safe-contracts/contracts/common/Enum.sol";
import {BaseGuard} from "@safe-global/safe-contracts/contracts/base/GuardManager.sol";

contract SafeTxPool is BaseGuard {
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

    // Simple struct for address book entries
    struct AddressBookEntry {
        bytes32 name; // Limited to 32 bytes
        address walletAddress; // Mandatory
    }

    // Counter for transaction IDs
    uint256 private _txIdCounter;

    // Mapping from transaction hash to SafeTx
    mapping(bytes32 => SafeTx) public transactions;

    // Mapping from transaction hash and ID to signer's signature status
    mapping(bytes32 => mapping(uint256 => mapping(address => bool))) private hasSignedByTxId;

    // Mapping from Safe address to array of pending transaction hashes
    mapping(address => bytes32[]) private pendingTxsBySafe;

    // Mapping from Safe address to its array of address book entries
    mapping(address => AddressBookEntry[]) private addressBooks;

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

    event AddressBookEntryAdded(address indexed safe, address indexed walletAddress, bytes32 name);
    event AddressBookEntryRemoved(address indexed safe, address indexed walletAddress);

    error AlreadySigned();
    error TransactionNotFound();
    error NotSafeWallet();
    error NotProposer();
    error InvalidAddress();
    error AddressAlreadyExists();
    error AddressNotFound();
    error AddressNotInAddressBook();

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

        // Create a new transaction ID
        uint256 txId = ++_txIdCounter;

        SafeTx storage newTx = transactions[txHash];
        newTx.safe = safe;
        newTx.to = to;
        newTx.value = value;
        newTx.data = data;
        newTx.operation = operation;
        newTx.proposer = msg.sender;
        newTx.nonce = nonce;
        newTx.txId = txId;

        // Add to pending transactions for this Safe
        pendingTxsBySafe[safe].push(txHash);

        // Emit event
        emit TransactionProposed(txHash, msg.sender, safe, to, value, data, operation, nonce, txId);
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

        // Check if caller is the Safe wallet or this contract (when called from checkAfterExecution)
        if (msg.sender != safeTx.safe && msg.sender != address(this)) revert NotSafeWallet();

        uint256 txId = safeTx.txId;

        // Remove from pending transactions for this Safe
        _removeFromPending(safeTx.safe, txHash);

        // Delete transaction data
        delete transactions[txHash];

        emit TransactionExecuted(txHash, safeTx.safe, txId);
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

        // Iterate through pending transactions from end to start to handle removals safely
        for (uint256 i = pendingTxs.length; i > 0; i--) {
            uint256 currentIndex = i - 1;
            bytes32 currentTxHash = pendingTxs[currentIndex];

            // Check if current transaction has the same nonce
            if (transactions[currentTxHash].nonce == targetNonce) {
                // Move last element to current position and pop
                pendingTxs[currentIndex] = pendingTxs[pendingTxs.length - 1];
                pendingTxs.pop();
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
                break;
            }
        }

        // Delete transaction data
        delete transactions[txHash];

        emit TransactionDeleted(txHash, safe, proposer, txId);
    }

    /**
     * @notice Implementation of the Guard interface's checkTransaction function
     * @dev This function is called before a Safe transaction is executed
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
        // Check if the destination address is in the address book
        int256 addressIndex = _findAddressBookEntry(msg.sender, to);
        if (addressIndex < 0) revert AddressNotInAddressBook();
    }

    /**
     * @notice Implementation of the Guard interface's checkAfterExecution function
     * @dev This function is called after a Safe transaction is executed
     * @param txHash Hash of the Safe transaction
     * @param success Whether the transaction was successful
     */
    function checkAfterExecution(bytes32 txHash, bool success) external override {
        // Only proceed if transaction was successful
        if (!success) return;

        // Since the transaction hash is the same in the pool and in the Safe,
        // we can directly try to mark the transaction as executed
        if (transactions[txHash].proposer != address(0)) {
            this.markAsExecuted(txHash);
        }
    }

    /**
     * @notice This function is called by the Safe contract when a function is not found
     * @dev It prevents the Safe from being locked during upgrades
     */
    fallback() external {
        // We do not want to revert here to prevent the Safe from being locked during upgrades
    }

    /**
     * @notice Add an entry to the address book of a Safe
     * @param safe The Safe wallet address that owns this address book
     * @param walletAddress The wallet address to add (mandatory)
     * @param name Name associated with the address (32 bytes)
     */
    function addAddressBookEntry(address safe, address walletAddress, bytes32 name) external {
        // Validate inputs
        if (walletAddress == address(0)) revert InvalidAddress();

        // Check if entry already exists
        int256 existingIndex = _findAddressBookEntry(safe, walletAddress);
        if (existingIndex >= 0) {
            // Update existing entry
            uint256 index = uint256(existingIndex);
            addressBooks[safe][index].name = name;
        } else {
            // Add new entry
            addressBooks[safe].push(AddressBookEntry({name: name, walletAddress: walletAddress}));
        }

        emit AddressBookEntryAdded(safe, walletAddress, name);
    }

    /**
     * @notice Remove an entry from the address book of a Safe
     * @param safe The Safe wallet address that owns this address book
     * @param walletAddress The wallet address to remove
     */
    function removeAddressBookEntry(address safe, address walletAddress) external {
        int256 index = _findAddressBookEntry(safe, walletAddress);

        if (index < 0) revert AddressNotFound();

        // Get the array
        AddressBookEntry[] storage entries = addressBooks[safe];
        uint256 entryIndex = uint256(index);

        // Move the last element to the position of the element to delete (if it's not the last)
        if (entryIndex < entries.length - 1) {
            entries[entryIndex] = entries[entries.length - 1];
        }

        // Remove the last element
        entries.pop();

        emit AddressBookEntryRemoved(safe, walletAddress);
    }

    /**
     * @notice Get all address book entries for a Safe
     * @param safe The Safe wallet address
     * @return entries Array of address book entries
     */
    function getAddressBookEntries(address safe) external view returns (AddressBookEntry[] memory) {
        return addressBooks[safe];
    }

    /**
     * @notice Internal function to find an entry's index in the address book
     * @param safe The Safe wallet address
     * @param walletAddress The wallet address to find
     * @return Index of the entry, or -1 if not found
     */
    function _findAddressBookEntry(address safe, address walletAddress) internal view returns (int256) {
        AddressBookEntry[] storage entries = addressBooks[safe];

        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].walletAddress == walletAddress) {
                return int256(i);
            }
        }

        return -1; // Not found
    }
}
