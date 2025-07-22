#\!/bin/bash
files=(
  "test/SafeTxPoolDelegateCall.t.sol"
  "test/SafeTxPoolGuard.t.sol" 
  "test/TrustedContractManagerTest.t.sol"
  "script/DelegateCallGuardExample.s.sol"
  "script/TrustedContractExample.s.sol"
)

for file in "${files[@]}"; do
  echo "Fixing $file..."
  # Add SafeMessagePool deployment if not already there
  if \! grep -q "SafeMessagePool messagePool = new SafeMessagePool();" "$file"; then
    sed -i '/new SafePoolRegistry(/i \        SafeMessagePool messagePool = new SafeMessagePool();' "$file"
  fi
  # Fix the constructor call
  sed -i 's/address(txPoolCore),$/address(txPoolCore),\n            address(messagePool),/' "$file"
done
