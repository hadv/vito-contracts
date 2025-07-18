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
    function deploySafeTxPool() external returns (
        address registry,
        address txPoolCore,
        address addressBookManager,
        address delegateCallManager,
        address trustedContractManager,
        address transactionValidator
    ) {
        // First, deploy the registry with placeholder address to get its address
        registry = address(new SafeTxPoolRegistry(
            address(0), // placeholder
            address(0), // placeholder
            address(0), // placeholder
            address(0), // placeholder
            address(0)  // placeholder
        ));

        // Deploy core components
        txPoolCore = address(new SafeTxPoolCore());
        addressBookManager = address(new AddressBookManager());
        delegateCallManager = address(new DelegateCallManager());
        trustedContractManager = address(new TrustedContractManager());

        // Deploy transaction validator with dependencies
        transactionValidator = address(new TransactionValidator(
            addressBookManager,
            trustedContractManager
        ));

        // This approach won't work due to immutable variables
        // We need a different approach
        revert("Use DeployRefactoredSafeTxPool script instead");
    }
}
