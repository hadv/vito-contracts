// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/SafeTxPool.sol";
import "./mocks/MockERC20.sol";
import "@safe-global/safe-contracts/contracts/common/Enum.sol";

contract MockSafeWithGuard {
    SafeTxPool public guard;

    constructor(SafeTxPool _guard) {
        guard = _guard;
    }

    function executeTransaction(address to, uint256 value, bytes calldata data, Enum.Operation operation) external {
        // Call checkTransaction on the guard
        guard.checkTransaction(
            to,
            value,
            data,
            operation,
            0, // safeTxGas
            0, // baseGas
            0, // gasPrice
            address(0), // gasToken
            payable(address(0)), // refundReceiver
            bytes(""), // signatures
            msg.sender // msgSender
        );

        // If the guard doesn't revert, the transaction would execute
    }
}

contract SafeTxPoolTypeSpecificValidationTest is Test {
    SafeTxPool public pool;
    MockSafeWithGuard public mockSafe;
    MockERC20 public token;

    address public owner;
    address public recipient;
    address public anotherRecipient;
    address public tokenAddress;

    function setUp() public {
        // Setup test accounts
        owner = address(0x1234);
        recipient = address(0xABCD);
        anotherRecipient = address(0x5678);

        // Deploy SafeTxPool
        pool = new SafeTxPool();

        // Deploy mock Safe with the guard
        mockSafe = new MockSafeWithGuard(pool);

        // Deploy mock ERC20 token
        token = new MockERC20("Test Token", "TEST", 18, 1000000 * 10 ** 18);
        tokenAddress = address(token);

        // Mint some tokens to the mock Safe
        token.mint(address(mockSafe), 1000 * 10 ** 18);

        // Add recipient to the address book
        vm.prank(address(mockSafe));
        pool.addAddressBookEntry(address(mockSafe), recipient, bytes32("Recipient"));
    }

    // Test native ETH transfer to address in address book
    function testNativeTransferToAddressInBook() public {
        mockSafe.executeTransaction(recipient, 1 ether, hex"", Enum.Operation.Call);
        // If we got here without reverting, the test passes
        assertTrue(true);
    }

    // Test native ETH transfer to address not in address book
    function testRevertNativeTransferToAddressNotInBook() public {
        vm.expectRevert(SafeTxPool.AddressNotInAddressBook.selector);
        mockSafe.executeTransaction(anotherRecipient, 1 ether, hex"", Enum.Operation.Call);
    }

    // Test ERC20 transfer with token not in address book and recipient not in address book
    function testRevertERC20TransferWithTokenNotInBookAndRecipientNotInBook() public {
        // Create ERC20 transfer data
        bytes memory data = abi.encodeWithSelector(token.transfer.selector, anotherRecipient, 100 * 10 ** 18);

        vm.expectRevert(SafeTxPool.ContractNotTrusted.selector);
        mockSafe.executeTransaction(tokenAddress, 0, data, Enum.Operation.Call);
    }

    // Test ERC20 transfer with token in address book but recipient not in address book
    function testRevertERC20TransferWithTokenInBookButRecipientNotInBook() public {
        // Add token to address book
        vm.prank(address(mockSafe));
        pool.addAddressBookEntry(address(mockSafe), tokenAddress, bytes32("Token"));

        // Create ERC20 transfer data
        bytes memory data = abi.encodeWithSelector(token.transfer.selector, anotherRecipient, 100 * 10 ** 18);

        vm.expectRevert(SafeTxPool.RecipientNotInAddressBook.selector);
        mockSafe.executeTransaction(tokenAddress, 0, data, Enum.Operation.Call);
    }

    // Test ERC20 transfer with token in address book and recipient in address book
    function testERC20TransferWithTokenAndRecipientInBook() public {
        // Add token to address book
        vm.prank(address(mockSafe));
        pool.addAddressBookEntry(address(mockSafe), tokenAddress, bytes32("Token"));

        // Create ERC20 transfer data
        bytes memory data = abi.encodeWithSelector(token.transfer.selector, recipient, 100 * 10 ** 18);

        mockSafe.executeTransaction(tokenAddress, 0, data, Enum.Operation.Call);
        // If we got here without reverting, the test passes
        assertTrue(true);
    }

    // Test ERC20 transfer with trusted token and recipient in address book
    function testERC20TransferWithTrustedTokenAndRecipientInBook() public {
        // Add token as trusted contract
        vm.prank(address(mockSafe));
        pool.addTrustedContract(address(mockSafe), tokenAddress);

        // Create ERC20 transfer data
        bytes memory data = abi.encodeWithSelector(token.transfer.selector, recipient, 100 * 10 ** 18);

        mockSafe.executeTransaction(tokenAddress, 0, data, Enum.Operation.Call);
        // If we got here without reverting, the test passes
        assertTrue(true);
    }

    // Test ERC20 transfer with trusted token but recipient not in address book
    function testRevertERC20TransferWithTrustedTokenButRecipientNotInBook() public {
        // Add token as trusted contract
        vm.prank(address(mockSafe));
        pool.addTrustedContract(address(mockSafe), tokenAddress);

        // Create ERC20 transfer data
        bytes memory data = abi.encodeWithSelector(token.transfer.selector, anotherRecipient, 100 * 10 ** 18);

        vm.expectRevert(SafeTxPool.RecipientNotInAddressBook.selector);
        mockSafe.executeTransaction(tokenAddress, 0, data, Enum.Operation.Call);
    }

    // Test ERC20 transferFrom
    function testERC20TransferFromWithTrustedToken() public {
        // Add token as trusted contract
        vm.prank(address(mockSafe));
        pool.addTrustedContract(address(mockSafe), tokenAddress);

        // Create ERC20 transferFrom data
        bytes memory data = abi.encodeWithSelector(token.transferFrom.selector, owner, recipient, 100 * 10 ** 18);

        mockSafe.executeTransaction(tokenAddress, 0, data, Enum.Operation.Call);
        // If we got here without reverting, the test passes
        assertTrue(true);
    }

    // Test removing trusted contract
    function testRemoveTrustedContract() public {
        // Add token as trusted contract
        vm.prank(address(mockSafe));
        pool.addTrustedContract(address(mockSafe), tokenAddress);

        // Verify it's trusted
        assertTrue(pool.isTrustedContract(address(mockSafe), tokenAddress));

        // Remove from trusted contracts
        vm.prank(address(mockSafe));
        pool.removeTrustedContract(address(mockSafe), tokenAddress);

        // Verify it's no longer trusted
        assertFalse(pool.isTrustedContract(address(mockSafe), tokenAddress));

        // Create ERC20 transfer data
        bytes memory data = abi.encodeWithSelector(token.transfer.selector, recipient, 100 * 10 ** 18);

        // Should now revert since token is no longer trusted
        vm.expectRevert(SafeTxPool.ContractNotTrusted.selector);
        mockSafe.executeTransaction(tokenAddress, 0, data, Enum.Operation.Call);
    }
}
