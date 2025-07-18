// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "./SafeTxPoolCore.sol";
import "./AddressBookManager.sol";
import "./DelegateCallManager.sol";
import "./TrustedContractManager.sol";
import "./TransactionValidator.sol";
import "./SafeTxPoolRegistry.sol";

/**
 * @title SafeTxPoolFactory
 * @notice Factory contract to deploy all SafeTxPool components in a single transaction
 */
contract SafeTxPoolFactory {
    event SafeTxPoolDeployed(
        address indexed registry,
        address txPoolCore,
        address addressBookManager,
        address delegateCallManager,
        address trustedContractManager,
        address transactionValidator
    );

    /**
     * @notice Deploy all SafeTxPool components and return the registry address
     * @return registry The main SafeTxPoolRegistry contract address
     * @return txPoolCore The SafeTxPoolCore contract address
     * @return addressBookManager The AddressBookManager contract address
     * @return delegateCallManager The DelegateCallManager contract address
     * @return trustedContractManager The TrustedContractManager contract address
     * @return transactionValidator The TransactionValidator contract address
     */
    function deploySafeTxPool()
        external
        returns (
            address registry,
            address txPoolCore,
            address addressBookManager,
            address delegateCallManager,
            address trustedContractManager,
            address transactionValidator
        )
    {
        // Use CREATE2 to predict the registry address
        bytes32 salt = keccak256(abi.encodePacked(msg.sender, block.timestamp));

        // Calculate the registry address that will be deployed
        bytes memory registryBytecode = abi.encodePacked(
            type(SafeTxPoolRegistry).creationCode,
            abi.encode(address(0), address(0), address(0), address(0), address(0))
        );
        registry = address(
            uint160(
                uint256(keccak256(abi.encodePacked(bytes1(0xff), address(this), salt, keccak256(registryBytecode))))
            )
        );

        // Deploy core components with predicted registry address
        txPoolCore = address(new SafeTxPoolCore());
        addressBookManager = address(new AddressBookManager(registry));
        delegateCallManager = address(new DelegateCallManager(registry));
        trustedContractManager = address(new TrustedContractManager(registry));

        // Deploy transaction validator with dependencies
        transactionValidator = address(new TransactionValidator(addressBookManager, trustedContractManager));

        // Deploy the actual registry with CREATE2
        SafeTxPoolRegistry actualRegistry = new SafeTxPoolRegistry{salt: salt}(
            txPoolCore, addressBookManager, delegateCallManager, trustedContractManager, transactionValidator
        );

        // Verify the address matches our prediction
        require(address(actualRegistry) == registry, "Registry address mismatch");

        emit SafeTxPoolDeployed(
            registry, txPoolCore, addressBookManager, delegateCallManager, trustedContractManager, transactionValidator
        );
    }
}
