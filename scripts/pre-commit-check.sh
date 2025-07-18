#!/bin/bash

# Pre-commit checks for vito-contracts
# Run this script before committing to ensure code quality

set -e

echo "🔍 Running pre-commit checks..."

# Check if foundry is available
if ! command -v forge &> /dev/null; then
    echo "❌ Forge not found. Please install Foundry first."
    exit 1
fi

# 1. Format check
echo "📝 Checking code formatting..."
if ! forge fmt --check; then
    echo "❌ Code formatting issues found. Run 'forge fmt' to fix them."
    exit 1
fi
echo "✅ Code formatting is correct"

# 2. Build check
echo "🔨 Building contracts..."
if ! forge build; then
    echo "❌ Build failed. Please fix compilation errors."
    exit 1
fi
echo "✅ Build successful"

# 3. Test check
echo "🧪 Running tests..."
if ! forge test; then
    echo "❌ Tests failed. Please fix failing tests."
    exit 1
fi
echo "✅ All tests passed"

# 4. Contract size check
echo "📏 Checking contract sizes..."
forge build --sizes | grep -E "(Runtime Size|SafeTxPool)" || true

echo ""
echo "🎉 All pre-commit checks passed!"
echo "💡 Remember to:"
echo "   - Review your changes carefully"
echo "   - Write meaningful commit messages"
echo "   - Update documentation if needed"
