// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

import "../StakedAssetHandler.sol";

// Lido contracts
interface ILido {
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function sharesOf(address account) external view returns (uint256);
    function getSharesByPooledEth(uint256 ethAmount) external view returns (uint256);
    function getPooledEthByShares(uint256 sharesAmount) external view returns (uint256);
}

interface IWithdrawalQueue {
    function requestWithdrawals(uint256[] calldata amounts, address owner)
        external
        returns (uint256[] memory requestIds);
    function claimWithdrawals(uint256[] calldata requestIds, uint256[] calldata hints) external;
    function getWithdrawalStatus(uint256[] calldata requestIds)
        external
        view
        returns (WithdrawalRequestStatus[] memory statuses);
    function findCheckpointHints(uint256[] calldata requestIds, uint256 firstIndex, uint256 lastIndex)
        external
        view
        returns (uint256[] memory hintIds);
}

struct WithdrawalRequestStatus {
    uint256 amountOfStETH;
    uint256 amountOfShares;
    address owner;
    uint256 timestamp;
    bool isFinalized;
    bool isClaimed;
}

/**
 * @title LidoStakingHandler
 * @notice Handler for Lido liquid staking positions
 * @dev Handles stETH positions and withdrawal requests
 */
contract LidoStakingHandler {
    // Lido mainnet addresses
    address public constant LIDO = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public constant WITHDRAWAL_QUEUE = 0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1;

    StakedAssetHandler public immutable stakedAssetHandler;

    constructor(address _stakedAssetHandler) {
        stakedAssetHandler = StakedAssetHandler(_stakedAssetHandler);
    }

    /**
     * @notice Get Lido staking position for a Safe
     * @param safe Address of the Safe wallet
     * @param data Additional data (not used for Lido)
     * @return position Staking position information
     */
    function getStakingPosition(address safe, bytes calldata data)
        external
        view
        returns (StakedAssetHandler.StakingPosition memory position)
    {
        ILido lido = ILido(LIDO);
        uint256 stETHBalance = lido.balanceOf(safe);

        if (stETHBalance > 0) {
            position = StakedAssetHandler.StakingPosition({
                protocol: LIDO,
                protocolType: StakedAssetHandler.ProtocolType.LIQUID_STAKING,
                stakedToken: address(0), // ETH
                receiptToken: LIDO, // stETH
                amount: stETHBalance,
                rewards: 0, // Rewards are automatically compounded in stETH
                unbondingTime: 0,
                isUnbonding: false,
                hasReceiptToken: true, // stETH is transferable
                extraData: ""
            });
        }
    }

    /**
     * @notice Initiate unbonding (withdrawal) from Lido
     * @param safe Address of the Safe wallet
     * @param amount Amount to unbond
     * @param data Additional data (not used)
     * @return requestId Withdrawal request ID
     */
    function initiateUnbonding(address safe, uint256 amount, bytes calldata data)
        external
        returns (bytes32 requestId)
    {
        ILido lido = ILido(LIDO);
        IWithdrawalQueue withdrawalQueue = IWithdrawalQueue(WITHDRAWAL_QUEUE);

        uint256 stETHBalance = lido.balanceOf(safe);
        if (amount > stETHBalance) {
            amount = stETHBalance;
        }

        // Approve withdrawal queue to spend stETH
        // Note: This would need to be executed through Safe's execTransactionFromModule
        bytes memory approveData = abi.encodeWithSelector(lido.transferFrom.selector, safe, WITHDRAWAL_QUEUE, amount);

        // Request withdrawal
        uint256[] memory amounts = new uint256[](1);
        amounts[0] = amount;

        uint256[] memory requestIds = withdrawalQueue.requestWithdrawals(amounts, safe);

        return bytes32(requestIds[0]);
    }

    /**
     * @notice Complete unbonding (claim withdrawal) from Lido
     * @param safe Address of the Safe wallet
     * @param requestId Withdrawal request ID
     * @param data Additional data containing hint
     * @return amount Amount of ETH received
     */
    function completeUnbonding(address safe, bytes32 requestId, bytes calldata data)
        external
        returns (uint256 amount)
    {
        IWithdrawalQueue withdrawalQueue = IWithdrawalQueue(WITHDRAWAL_QUEUE);

        uint256[] memory requestIds = new uint256[](1);
        requestIds[0] = uint256(requestId);

        // Get withdrawal status
        WithdrawalRequestStatus[] memory statuses = withdrawalQueue.getWithdrawalStatus(requestIds);
        require(statuses[0].isFinalized && !statuses[0].isClaimed, "Withdrawal not ready or already claimed");

        // Decode hint from data
        uint256 hint = 0;
        if (data.length >= 32) {
            hint = abi.decode(data, (uint256));
        }

        uint256[] memory hints = new uint256[](1);
        hints[0] = hint;

        uint256 balanceBefore = safe.balance;
        withdrawalQueue.claimWithdrawals(requestIds, hints);
        uint256 balanceAfter = safe.balance;

        return balanceAfter - balanceBefore;
    }

    /**
     * @notice Claim rewards (not applicable for Lido as rewards are auto-compounded)
     * @param safe Address of the Safe wallet
     * @param data Additional data (not used)
     * @return rewards Amount of rewards claimed (always 0 for Lido)
     */
    function claimRewards(address safe, bytes calldata data) external pure returns (uint256 rewards) {
        // Lido automatically compounds rewards into stETH balance
        return 0;
    }

    /**
     * @notice Transfer stETH receipt tokens to beneficiary
     * @param safe Address of the Safe wallet
     * @param to Beneficiary address
     * @param amount Amount to transfer
     * @param data Additional data (not used)
     * @return success Whether transfer was successful
     */
    function transferReceiptToken(address safe, address to, uint256 amount, bytes calldata data)
        external
        returns (bool success)
    {
        ILido lido = ILido(LIDO);

        // This would need to be executed through Safe's execTransactionFromModule
        return lido.transferFrom(safe, to, amount);
    }

    /**
     * @notice Get withdrawal request status
     * @param requestIds Array of withdrawal request IDs
     * @return statuses Array of withdrawal statuses
     */
    function getWithdrawalStatus(uint256[] calldata requestIds)
        external
        view
        returns (WithdrawalRequestStatus[] memory statuses)
    {
        IWithdrawalQueue withdrawalQueue = IWithdrawalQueue(WITHDRAWAL_QUEUE);
        return withdrawalQueue.getWithdrawalStatus(requestIds);
    }

    /**
     * @notice Find checkpoint hints for withdrawal claims
     * @param requestIds Array of withdrawal request IDs
     * @param firstIndex First index to search
     * @param lastIndex Last index to search
     * @return hintIds Array of hint IDs
     */
    function findCheckpointHints(uint256[] calldata requestIds, uint256 firstIndex, uint256 lastIndex)
        external
        view
        returns (uint256[] memory hintIds)
    {
        IWithdrawalQueue withdrawalQueue = IWithdrawalQueue(WITHDRAWAL_QUEUE);
        return withdrawalQueue.findCheckpointHints(requestIds, firstIndex, lastIndex);
    }

    /**
     * @notice Check if withdrawal requests are ready for claiming
     * @param requestIds Array of withdrawal request IDs
     * @return ready Array indicating which requests are ready
     * @return finalized Array indicating which requests are finalized
     */
    function areWithdrawalsReady(uint256[] calldata requestIds)
        external
        view
        returns (bool[] memory ready, bool[] memory finalized)
    {
        IWithdrawalQueue withdrawalQueue = IWithdrawalQueue(WITHDRAWAL_QUEUE);
        WithdrawalRequestStatus[] memory statuses = withdrawalQueue.getWithdrawalStatus(requestIds);

        ready = new bool[](requestIds.length);
        finalized = new bool[](requestIds.length);

        for (uint256 i = 0; i < requestIds.length; i++) {
            finalized[i] = statuses[i].isFinalized;
            ready[i] = statuses[i].isFinalized && !statuses[i].isClaimed;
        }
    }

    /**
     * @notice Get stETH balance and shares for a Safe
     * @param safe Address of the Safe wallet
     * @return stETHBalance Balance in stETH
     * @return shares Balance in shares
     */
    function getBalanceInfo(address safe) external view returns (uint256 stETHBalance, uint256 shares) {
        ILido lido = ILido(LIDO);
        stETHBalance = lido.balanceOf(safe);
        shares = lido.sharesOf(safe);
    }

    /**
     * @notice Convert between stETH and shares
     * @param ethAmount Amount in ETH/stETH
     * @param sharesAmount Amount in shares
     * @return shares Shares equivalent of ethAmount
     * @return ethEquivalent ETH equivalent of sharesAmount
     */
    function convertAmounts(uint256 ethAmount, uint256 sharesAmount)
        external
        view
        returns (uint256 shares, uint256 ethEquivalent)
    {
        ILido lido = ILido(LIDO);

        if (ethAmount > 0) {
            shares = lido.getSharesByPooledEth(ethAmount);
        }

        if (sharesAmount > 0) {
            ethEquivalent = lido.getPooledEthByShares(sharesAmount);
        }
    }
}
