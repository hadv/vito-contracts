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

    // Delegate call control mappings
    mapping(address => bool) private delegateCallEnabled;
    mapping(address => mapping(address => bool)) private allowedDelegateCallTargets;
    mapping(address => bool) private hasTargetRestrictions;

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

    event AddressBookEntryAdded(address indexed safe, address indexed walletAddress, bytes32 name);
    event AddressBookEntryRemoved(address indexed safe, address indexed walletAddress);
    event SelfCallAllowed(address indexed safe, address indexed to);
    event GuardCallAllowed(address indexed safe, address indexed guard);
    event DelegateCallToggled(address indexed safe, bool enabled);
    event DelegateCallTargetAdded(address indexed safe, address indexed target);
    event DelegateCallTargetRemoved(address indexed safe, address indexed target);

    error AlreadySigned();
    error TransactionNotFound();
    error NotSafeWallet();
    error NotProposer();
    error InvalidAddress();
    error AddressAlreadyExists();
    error AddressNotFound();
    error AddressNotInAddressBook();
    error DelegateCallDisabled();
    error DelegateCallTargetNotAllowed();

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
        address safe = safeTx.safe;

        // Remove from pending transactions for this Safe
        _removeFromPending(safe, txHash);

        // Delete transaction data
        delete transactions[txHash];

        emit TransactionExecuted(txHash, safe, txId);
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
     * @notice Implementation of the Guard interface's checkTransaction function
     * @dev This function is called before a Safe transaction is executed
     */
    function checkTransaction(
        address to,
        uint256,
        bytes memory,
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
            if (!delegateCallEnabled[safe]) {
                revert DelegateCallDisabled();
            }

            // If delegate calls are enabled, check if there are any specific target restrictions
            // If the target is not explicitly allowed and there are restrictions, revert
            if (!allowedDelegateCallTargets[safe][to] && _hasDelegateCallTargetRestrictions(safe)) {
                revert DelegateCallTargetNotAllowed();
            }
        }

        // Check if the destination address is in the Safe's address book
        int256 index = _findAddressBookEntry(safe, to);

        // If the address is not in the address book, revert
        if (index < 0) revert AddressNotInAddressBook();
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
        // Only the Safe wallet itself can modify its address book
        if (msg.sender != safe) revert NotSafeWallet();

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
        // Only the Safe wallet itself can modify its address book
        if (msg.sender != safe) revert NotSafeWallet();

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

    /**
     * @notice Enable or disable delegate calls for a Safe
     * @param safe The Safe wallet address
     * @param enabled Whether delegate calls should be enabled
     */
    function setDelegateCallEnabled(address safe, bool enabled) external {
        // Only the Safe wallet itself can modify its delegate call settings
        if (msg.sender != safe) revert NotSafeWallet();

        delegateCallEnabled[safe] = enabled;
        emit DelegateCallToggled(safe, enabled);
    }

    /**
     * @notice Add an allowed delegate call target for a Safe
     * @param safe The Safe wallet address
     * @param target The target address to allow for delegate calls
     */
    function addDelegateCallTarget(address safe, address target) external {
        // Only the Safe wallet itself can modify its delegate call settings
        if (msg.sender != safe) revert NotSafeWallet();

        // Validate target address
        if (target == address(0)) revert InvalidAddress();

        allowedDelegateCallTargets[safe][target] = true;
        hasTargetRestrictions[safe] = true;
        emit DelegateCallTargetAdded(safe, target);
    }

    /**
     * @notice Remove an allowed delegate call target for a Safe
     * @param safe The Safe wallet address
     * @param target The target address to remove from allowed delegate calls
     */
    function removeDelegateCallTarget(address safe, address target) external {
        // Only the Safe wallet itself can modify its delegate call settings
        if (msg.sender != safe) revert NotSafeWallet();

        allowedDelegateCallTargets[safe][target] = false;
        emit DelegateCallTargetRemoved(safe, target);
    }

    /**
     * @notice Check if delegate calls are enabled for a Safe
     * @param safe The Safe wallet address
     * @return enabled Whether delegate calls are enabled
     */
    function isDelegateCallEnabled(address safe) external view returns (bool) {
        return delegateCallEnabled[safe];
    }

    /**
     * @notice Check if a target is allowed for delegate calls from a Safe
     * @param safe The Safe wallet address
     * @param target The target address to check
     * @return allowed Whether the target is allowed for delegate calls
     */
    function isDelegateCallTargetAllowed(address safe, address target) external view returns (bool) {
        return allowedDelegateCallTargets[safe][target];
    }

    /**
     * @notice Internal function to check if a Safe has any delegate call target restrictions
     * @param safe The Safe wallet address
     * @return hasRestrictions Whether the Safe has any specific target restrictions
     */
    function _hasDelegateCallTargetRestrictions(address safe) internal view returns (bool) {
        return hasTargetRestrictions[safe];
    }
}
