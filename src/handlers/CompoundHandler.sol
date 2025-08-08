// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../StakedAssetHandler.sol";

// Compound interfaces
interface ICToken {
    function balanceOf(address owner) external view returns (uint256);
    function balanceOfUnderlying(address owner) external returns (uint256);
    function exchangeRateStored() external view returns (uint256);
    function exchangeRateCurrent() external returns (uint256);
    function underlying() external view returns (address);
    function redeem(uint256 redeemTokens) external returns (uint256);
    function redeemUnderlying(uint256 redeemAmount) external returns (uint256);
    function transfer(address dst, uint256 amount) external returns (bool);
    function transferFrom(address src, address dst, uint256 amount) external returns (bool);
    function accrueInterest() external returns (uint256);
    function borrowBalanceStored(address account) external view returns (uint256);
    function borrowBalanceCurrent(address account) external returns (uint256);
}

interface IComptroller {
    function getAccountLiquidity(address account) external view returns (uint256, uint256, uint256);
    function markets(address cToken) external view returns (bool isListed, uint256 collateralFactorMantissa);
    function enterMarkets(address[] calldata cTokens) external returns (uint256[] memory);
    function exitMarket(address cToken) external returns (uint256);
    function claimComp(address holder) external;
    function compAccrued(address holder) external view returns (uint256);
}

/**
 * @title CompoundHandler
 * @notice Handler for Compound and Compound-like lending protocols
 * @dev Handles cToken positions and interest accrual
 */
contract CompoundHandler {
    StakedAssetHandler public immutable stakedAssetHandler;
    IComptroller public immutable comptroller;

    // Protocol-specific data structure
    struct CompoundData {
        address cToken;
        bool claimRewards;
        bool exitMarket;
    }

    constructor(address _stakedAssetHandler, address _comptroller) {
        stakedAssetHandler = StakedAssetHandler(_stakedAssetHandler);
        comptroller = IComptroller(_comptroller);
    }

    /**
     * @notice Get Compound lending position for a Safe
     * @param safe Address of the Safe wallet
     * @param data Encoded CompoundData
     * @return position Staking position information
     */
    function getStakingPosition(address safe, bytes calldata data)
        external
        view
        returns (StakedAssetHandler.StakingPosition memory position)
    {
        CompoundData memory compoundData = abi.decode(data, (CompoundData));
        ICToken cToken = ICToken(compoundData.cToken);

        uint256 cTokenBalance = cToken.balanceOf(safe);

        if (cTokenBalance > 0) {
            uint256 exchangeRate = cToken.exchangeRateStored();
            uint256 underlyingBalance = (cTokenBalance * exchangeRate) / 1e18;

            // Calculate accrued interest as rewards
            uint256 borrowBalance = cToken.borrowBalanceStored(safe);
            uint256 compRewards = comptroller.compAccrued(safe);

            position = StakedAssetHandler.StakingPosition({
                protocol: compoundData.cToken,
                protocolType: StakedAssetHandler.ProtocolType.COMPOUND_LIKE,
                stakedToken: cToken.underlying(),
                receiptToken: compoundData.cToken,
                amount: underlyingBalance,
                rewards: compRewards,
                unbondingTime: 0, // Compound allows instant withdrawal
                isUnbonding: false,
                hasReceiptToken: true, // cTokens are transferable
                extraData: abi.encode(borrowBalance, exchangeRate)
            });
        }
    }

    /**
     * @notice Initiate unbonding (redemption) from Compound
     * @param safe Address of the Safe wallet
     * @param amount Amount to redeem (in underlying tokens)
     * @param data Encoded CompoundData
     * @return requestId Request ID (immediate for Compound)
     */
    function initiateUnbonding(address safe, uint256 amount, bytes calldata data)
        external
        returns (bytes32 requestId)
    {
        CompoundData memory compoundData = abi.decode(data, (CompoundData));
        ICToken cToken = ICToken(compoundData.cToken);

        // Check account liquidity before redemption
        (uint256 liquidity, uint256 shortfall,) = comptroller.getAccountLiquidity(safe);
        require(shortfall == 0, "Account has shortfall");

        // Accrue interest first
        cToken.accrueInterest();

        uint256 cTokenBalance = cToken.balanceOf(safe);
        if (amount == type(uint256).max) {
            // Redeem all cTokens
            cToken.redeem(cTokenBalance);
        } else {
            // Redeem specific underlying amount
            cToken.redeemUnderlying(amount);
        }

        // Exit market if specified and no remaining balance
        if (compoundData.exitMarket && cToken.balanceOf(safe) == 0) {
            comptroller.exitMarket(compoundData.cToken);
        }

        // Return immediate completion (Compound is instant)
        return keccak256(abi.encodePacked(safe, compoundData.cToken, block.timestamp));
    }

    /**
     * @notice Complete unbonding (already completed for Compound)
     * @param safe Address of the Safe wallet
     * @param requestId Request ID
     * @param data Additional data
     * @return amount Amount redeemed (0 as already completed)
     */
    function completeUnbonding(address safe, bytes32 requestId, bytes calldata data)
        external
        pure
        returns (uint256 amount)
    {
        // Compound redemption is instant, so nothing to complete
        return 0;
    }

    /**
     * @notice Claim COMP rewards
     * @param safe Address of the Safe wallet
     * @param data Additional data (not used)
     * @return rewards Amount of COMP rewards claimed
     */
    function claimRewards(address safe, bytes calldata data) external returns (uint256 rewards) {
        uint256 compBefore = comptroller.compAccrued(safe);
        comptroller.claimComp(safe);
        uint256 compAfter = comptroller.compAccrued(safe);

        return compBefore - compAfter;
    }

    /**
     * @notice Transfer cToken receipt tokens to beneficiary
     * @param safe Address of the Safe wallet
     * @param to Beneficiary address
     * @param amount Amount to transfer (in cTokens)
     * @param data Encoded CompoundData
     * @return success Whether transfer was successful
     */
    function transferReceiptToken(address safe, address to, uint256 amount, bytes calldata data)
        external
        returns (bool success)
    {
        CompoundData memory compoundData = abi.decode(data, (CompoundData));
        ICToken cToken = ICToken(compoundData.cToken);

        uint256 cTokenBalance = cToken.balanceOf(safe);
        if (amount > cTokenBalance) {
            amount = cTokenBalance;
        }

        // This would need to be executed through Safe's execTransactionFromModule
        return cToken.transferFrom(safe, to, amount);
    }

    /**
     * @notice Get detailed account information
     * @param safe Address of the Safe wallet
     * @param cTokens Array of cToken addresses
     * @return info Account information
     */
    function getAccountInfo(address safe, address[] calldata cTokens) external view returns (AccountInfo memory info) {
        (uint256 liquidity, uint256 shortfall,) = comptroller.getAccountLiquidity(safe);
        uint256 compAccrued = comptroller.compAccrued(safe);

        CTokenInfo[] memory cTokenInfos = new CTokenInfo[](cTokens.length);

        for (uint256 i = 0; i < cTokens.length; i++) {
            ICToken cToken = ICToken(cTokens[i]);

            cTokenInfos[i] = CTokenInfo({
                cToken: cTokens[i],
                underlying: cToken.underlying(),
                cTokenBalance: cToken.balanceOf(safe),
                underlyingBalance: 0, // Would need to call non-view function
                borrowBalance: cToken.borrowBalanceStored(safe),
                exchangeRate: cToken.exchangeRateStored()
            });
        }

        info = AccountInfo({
            liquidity: liquidity,
            shortfall: shortfall,
            compAccrued: compAccrued,
            cTokenInfos: cTokenInfos
        });
    }

    /**
     * @notice Check if account can safely redeem amount
     * @param safe Address of the Safe wallet
     * @param cToken cToken to redeem from
     * @param amount Amount to redeem (in underlying)
     * @return canRedeem Whether redemption is safe
     * @return maxRedeemable Maximum safely redeemable amount
     */
    function canSafelyRedeem(address safe, address cToken, uint256 amount)
        external
        view
        returns (bool canRedeem, uint256 maxRedeemable)
    {
        (uint256 liquidity, uint256 shortfall,) = comptroller.getAccountLiquidity(safe);

        if (shortfall > 0) {
            return (false, 0);
        }

        ICToken cTokenContract = ICToken(cToken);
        uint256 cTokenBalance = cTokenContract.balanceOf(safe);
        uint256 exchangeRate = cTokenContract.exchangeRateStored();
        uint256 maxUnderlying = (cTokenBalance * exchangeRate) / 1e18;

        // Simple check - in practice would need more complex calculation
        // considering collateral factors and other positions
        canRedeem = amount <= maxUnderlying && amount <= liquidity;
        maxRedeemable = maxUnderlying < liquidity ? maxUnderlying : liquidity;
    }

    // Structs for return data
    struct AccountInfo {
        uint256 liquidity;
        uint256 shortfall;
        uint256 compAccrued;
        CTokenInfo[] cTokenInfos;
    }

    struct CTokenInfo {
        address cToken;
        address underlying;
        uint256 cTokenBalance;
        uint256 underlyingBalance;
        uint256 borrowBalance;
        uint256 exchangeRate;
    }

    /**
     * @notice Emergency exit from all markets
     * @param safe Address of the Safe wallet
     * @param cTokens Array of cTokens to exit
     */
    function emergencyExitMarkets(address safe, address[] calldata cTokens) external {
        for (uint256 i = 0; i < cTokens.length; i++) {
            ICToken cToken = ICToken(cTokens[i]);

            // Try to redeem all cTokens first
            uint256 cTokenBalance = cToken.balanceOf(safe);
            if (cTokenBalance > 0) {
                try cToken.redeem(cTokenBalance) {
                    // Redemption successful
                } catch {
                    // Continue with other tokens if one fails
                }
            }

            // Try to exit market
            try comptroller.exitMarket(cTokens[i]) {
                // Exit successful
            } catch {
                // Continue with other markets if one fails
            }
        }
    }

    /**
     * @notice Batch operations for multiple cTokens
     * @param safe Address of the Safe wallet
     * @param cTokens Array of cToken addresses
     * @param operations Array of operations (0: redeem all, 1: transfer, 2: exit market)
     * @param amounts Array of amounts for operations
     * @param recipients Array of recipients for transfers
     */
    function batchOperations(
        address safe,
        address[] calldata cTokens,
        uint8[] calldata operations,
        uint256[] calldata amounts,
        address[] calldata recipients
    ) external {
        require(
            cTokens.length == operations.length && operations.length == amounts.length
                && amounts.length == recipients.length,
            "Array length mismatch"
        );

        for (uint256 i = 0; i < cTokens.length; i++) {
            ICToken cToken = ICToken(cTokens[i]);

            if (operations[i] == 0) {
                // Redeem all
                uint256 balance = cToken.balanceOf(safe);
                if (balance > 0) {
                    cToken.redeem(balance);
                }
            } else if (operations[i] == 1) {
                // Transfer
                cToken.transferFrom(safe, recipients[i], amounts[i]);
            } else if (operations[i] == 2) {
                // Exit market
                comptroller.exitMarket(cTokens[i]);
            }
        }
    }
}
