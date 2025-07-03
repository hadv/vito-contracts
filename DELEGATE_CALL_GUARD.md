# SafeTxPool Delegate Call Guard

The SafeTxPool contract now includes a comprehensive delegate call guard mechanism that allows Safe wallets to control when and where delegate calls (operation = 1) can be executed.

## Overview

Delegate calls are powerful but potentially dangerous operations that execute code from another contract in the context of the calling contract. This guard provides granular control over delegate call execution to enhance security.

## Features

### 1. Enable/Disable Delegate Calls
- Delegate calls are **disabled by default** for all Safe wallets
- Safe owners can enable or disable delegate calls for their specific Safe
- Only the Safe wallet itself can modify its delegate call settings

### 2. Target Whitelisting (Optional)
- When delegate calls are enabled, all targets are allowed by default
- Safe owners can optionally add specific target restrictions
- Once target restrictions are added, only whitelisted targets are allowed for delegate calls

### 3. Granular Control
- Each Safe wallet has independent delegate call settings
- Settings persist across transactions
- Normal calls (operation = 0) are unaffected by delegate call restrictions

## Usage

### Basic Setup

```solidity
// Deploy SafeTxPool
SafeTxPool pool = new SafeTxPool();

// Set the pool as a guard on your Safe wallet
// (This requires Safe owner signatures)
safe.setGuard(address(pool));
```

### Enable Delegate Calls

```solidity
// Enable delegate calls for your Safe (called from the Safe)
pool.setDelegateCallEnabled(address(safe), true);
```

### Add Target Restrictions (Optional)

```solidity
// Add specific allowed targets for delegate calls
pool.addDelegateCallTarget(address(safe), targetContract1);
pool.addDelegateCallTarget(address(safe), targetContract2);

// Remove a target from the allowed list
pool.removeDelegateCallTarget(address(safe), targetContract1);
```

### Check Settings

```solidity
// Check if delegate calls are enabled
bool enabled = pool.isDelegateCallEnabled(address(safe));

// Check if a specific target is allowed
bool allowed = pool.isDelegateCallTargetAllowed(address(safe), targetContract);
```

## Security Model

### Default Security
- **Delegate calls disabled by default**: New Safes cannot execute delegate calls until explicitly enabled
- **Address book integration**: All targets (delegate call or normal call) must be in the Safe's address book

### Progressive Security Levels

1. **Level 1 - Disabled (Default)**
   - All delegate calls are blocked
   - Maximum security

2. **Level 2 - Enabled, No Restrictions**
   - Delegate calls allowed to any target in the address book
   - Moderate security

3. **Level 3 - Enabled with Target Restrictions**
   - Delegate calls only allowed to whitelisted targets
   - High security with controlled flexibility

### Always Allowed
The following calls bypass delegate call restrictions:
- **Self calls**: Safe calling itself (required for owner management, threshold changes, etc.)
- **Guard calls**: Safe calling the SafeTxPool contract (required for settings management)

## Events

The guard emits events for all delegate call management operations:

```solidity
event DelegateCallToggled(address indexed safe, bool enabled);
event DelegateCallTargetAdded(address indexed safe, address indexed target);
event DelegateCallTargetRemoved(address indexed safe, address indexed target);
```

## Error Handling

The guard defines specific errors for different failure scenarios:

```solidity
error DelegateCallDisabled();           // Delegate calls are disabled for this Safe
error DelegateCallTargetNotAllowed();   // Target is not in the whitelist
error NotSafeWallet();                  // Only the Safe can modify its settings
```

## Integration with Existing Features

### Address Book Requirement
All transaction targets (including delegate call targets) must be in the Safe's address book. The delegate call guard works in conjunction with the existing address book functionality:

1. First, add the target to the address book
2. Then, configure delegate call settings
3. The guard checks both address book membership AND delegate call permissions

### Transaction Pool
The delegate call guard integrates seamlessly with the existing transaction pool functionality. Proposed transactions are checked against delegate call restrictions when executed.

## Example Workflow

```solidity
// 1. Add target to address book
pool.addAddressBookEntry(address(safe), targetContract, "My Target Contract");

// 2. Enable delegate calls
pool.setDelegateCallEnabled(address(safe), true);

// 3. (Optional) Add target restrictions
pool.addDelegateCallTarget(address(safe), targetContract);

// 4. Now delegate calls to targetContract are allowed
// Normal Safe transaction execution will pass the guard checks
```

## Testing

Comprehensive tests are provided in `test/SafeTxPoolDelegateCallGuard.t.sol` covering:
- Default disabled state
- Enabling/disabling delegate calls
- Target whitelisting
- Integration with address book
- Event emission
- Error conditions
- Permission checks

Run tests with:
```bash
forge test --match-path test/SafeTxPoolDelegateCallGuard.t.sol -v
```

## Best Practices

1. **Start Secure**: Keep delegate calls disabled unless specifically needed
2. **Use Target Restrictions**: When enabling delegate calls, consider adding target restrictions for additional security
3. **Regular Audits**: Periodically review enabled targets and remove unused ones
4. **Monitor Events**: Watch for delegate call configuration changes in your Safe
5. **Test Thoroughly**: Always test delegate call configurations in a safe environment before production use

## Migration

Existing Safe wallets using SafeTxPool will have delegate calls disabled by default after upgrading. This ensures no breaking changes and maintains security. Safe owners must explicitly enable delegate calls if needed.
