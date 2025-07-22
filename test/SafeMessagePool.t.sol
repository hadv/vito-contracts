// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/SafeTxPoolRegistry.sol";
import "../src/SafeTxPoolCore.sol";
import "../src/AddressBookManager.sol";
import "../src/DelegateCallManager.sol";
import "../src/TrustedContractManager.sol";
import "../src/TransactionValidator.sol";
import "../src/interfaces/ISafeTxPoolCore.sol";

contract SafeMessagePoolTest is Test {
    SafeTxPoolRegistry public registry;
    SafeTxPoolCore public txPoolCore;
    AddressBookManager public addressBookManager;
    DelegateCallManager public delegateCallManager;
    TrustedContractManager public trustedContractManager;
    TransactionValidator public transactionValidator;

    address public safe = address(0x123);
    address public owner1 = address(0x456);
    address public owner2 = address(0x789);
    address public proposer = address(0xABC);

    bytes32 public messageHash;
    bytes public testMessage = "Hello, Safe message signing!";
    string public dAppTopic = "test-topic-123";
    uint256 public dAppRequestId = 42;

    function setUp() public {
        // Deploy core components
        txPoolCore = new SafeTxPoolCore();
        addressBookManager = new AddressBookManager();
        delegateCallManager = new DelegateCallManager();
        trustedContractManager = new TrustedContractManager();
        transactionValidator = new TransactionValidator(address(trustedContractManager), address(delegateCallManager));

        // Deploy registry
        registry = new SafeTxPoolRegistry(
            address(txPoolCore),
            address(addressBookManager),
            address(delegateCallManager),
            address(trustedContractManager),
            address(transactionValidator)
        );

        // Set registry in core
        txPoolCore.setRegistry(address(registry));

        // Generate message hash (simplified for testing)
        messageHash = keccak256(abi.encodePacked(testMessage, safe, block.chainid));
    }

    function testProposeMessage() public {
        vm.prank(proposer);
        registry.proposeMessage(messageHash, safe, testMessage, dAppTopic, dAppRequestId);

        // Verify message was proposed
        (
            address returnedSafe,
            bytes memory returnedMessage,
            address returnedProposer,
            uint256 msgId,
            string memory returnedTopic,
            uint256 returnedRequestId
        ) = registry.getMessageDetails(messageHash);

        assertEq(returnedSafe, safe);
        assertEq(returnedMessage, testMessage);
        assertEq(returnedProposer, proposer);
        assertEq(msgId, 1); // First message should have ID 1
        assertEq(returnedTopic, dAppTopic);
        assertEq(returnedRequestId, dAppRequestId);
    }

    function testSignMessage() public {
        // First propose the message
        vm.prank(proposer);
        registry.proposeMessage(messageHash, safe, testMessage, dAppTopic, dAppRequestId);

        // Create a signature (simplified for testing)
        bytes memory signature = abi.encodePacked(bytes32(uint256(0x1)), bytes32(uint256(0x2)), uint8(27));

        // Sign the message
        vm.prank(owner1);
        registry.signMessage(messageHash, signature);

        // Verify signature was recorded
        bytes[] memory signatures = registry.getMessageSignatures(messageHash);
        assertEq(signatures.length, 1);
        assertEq(signatures[0], signature);

        // Check signature count
        uint256 count = registry.getMessageSignatureCount(messageHash);
        assertEq(count, 1);
    }

    function testGetPendingMessages() public {
        // Propose a message
        vm.prank(proposer);
        registry.proposeMessage(messageHash, safe, testMessage, dAppTopic, dAppRequestId);

        // Get pending messages
        bytes32[] memory pendingMessages = registry.getPendingMessages(safe);
        assertEq(pendingMessages.length, 1);
        assertEq(pendingMessages[0], messageHash);
    }

    function testMarkMessageAsExecuted() public {
        // Propose a message
        vm.prank(proposer);
        registry.proposeMessage(messageHash, safe, testMessage, dAppTopic, dAppRequestId);

        // Mark as executed (from Safe)
        vm.prank(safe);
        registry.markMessageAsExecuted(messageHash);

        // Verify message was removed from pending
        bytes32[] memory pendingMessages = registry.getPendingMessages(safe);
        assertEq(pendingMessages.length, 0);

        // Verify message details are cleared
        (address returnedSafe,,,,, ) = registry.getMessageDetails(messageHash);
        assertEq(returnedSafe, address(0)); // Should be cleared
    }

    function testDeleteMessage() public {
        // Propose a message
        vm.prank(proposer);
        registry.proposeMessage(messageHash, safe, testMessage, dAppTopic, dAppRequestId);

        // Delete message (only proposer can delete)
        vm.prank(proposer);
        registry.deleteMessage(messageHash);

        // Verify message was removed
        bytes32[] memory pendingMessages = registry.getPendingMessages(safe);
        assertEq(pendingMessages.length, 0);
    }

    function testOnlyProposerCanDelete() public {
        // Propose a message
        vm.prank(proposer);
        registry.proposeMessage(messageHash, safe, testMessage, dAppTopic, dAppRequestId);

        // Try to delete from non-proposer (should fail)
        vm.prank(owner1);
        vm.expectRevert(ISafeTxPoolCore.NotProposer.selector);
        registry.deleteMessage(messageHash);
    }

    function testCannotSignNonExistentMessage() public {
        bytes memory signature = abi.encodePacked(bytes32(uint256(0x1)), bytes32(uint256(0x2)), uint8(27));

        vm.prank(owner1);
        vm.expectRevert(ISafeTxPoolCore.MessageNotFound.selector);
        registry.signMessage(messageHash, signature);
    }

    function testMultipleSignatures() public {
        // Propose a message
        vm.prank(proposer);
        registry.proposeMessage(messageHash, safe, testMessage, dAppTopic, dAppRequestId);

        // Create different signatures
        bytes memory signature1 = abi.encodePacked(bytes32(uint256(0x1)), bytes32(uint256(0x2)), uint8(27));
        bytes memory signature2 = abi.encodePacked(bytes32(uint256(0x3)), bytes32(uint256(0x4)), uint8(28));

        // Sign from different owners
        vm.prank(owner1);
        registry.signMessage(messageHash, signature1);

        vm.prank(owner2);
        registry.signMessage(messageHash, signature2);

        // Verify both signatures were recorded
        bytes[] memory signatures = registry.getMessageSignatures(messageHash);
        assertEq(signatures.length, 2);
        assertEq(signatures[0], signature1);
        assertEq(signatures[1], signature2);

        // Check signature count
        uint256 count = registry.getMessageSignatureCount(messageHash);
        assertEq(count, 2);
    }

    function testMessageIsolationBetweenSafes() public {
        address safe2 = address(0x999);
        bytes32 messageHash2 = keccak256(abi.encodePacked(testMessage, safe2, block.chainid));

        // Propose messages for different Safes
        vm.prank(proposer);
        registry.proposeMessage(messageHash, safe, testMessage, dAppTopic, dAppRequestId);

        vm.prank(proposer);
        registry.proposeMessage(messageHash2, safe2, testMessage, "topic2", 43);

        // Verify each Safe only sees its own messages
        bytes32[] memory pendingMessages1 = registry.getPendingMessages(safe);
        bytes32[] memory pendingMessages2 = registry.getPendingMessages(safe2);

        assertEq(pendingMessages1.length, 1);
        assertEq(pendingMessages2.length, 1);
        assertEq(pendingMessages1[0], messageHash);
        assertEq(pendingMessages2[0], messageHash2);
    }
}
