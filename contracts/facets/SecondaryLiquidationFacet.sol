// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {U256, U88, U80} from "contracts/libraries/PRBMathHelper.sol";

import {IAsset} from "interfaces/IAsset.sol";

import {Errors} from "contracts/libraries/Errors.sol";
import {Events} from "contracts/libraries/Events.sol";
import {STypes, MTypes, SR} from "contracts/libraries/DataTypes.sol";
import {Modifiers} from "contracts/libraries/AppStorage.sol";
import {LibAsset} from "contracts/libraries/LibAsset.sol";
import {LibOracle} from "contracts/libraries/LibOracle.sol";
import {LibOrders} from "contracts/libraries/LibOrders.sol";
import {LibShortRecord} from "contracts/libraries/LibShortRecord.sol";
import {LibSRUtil} from "contracts/libraries/LibSRUtil.sol";

// import {console} from "contracts/libraries/console.sol";

contract SecondaryLiquidationFacet is Modifiers {
    using LibShortRecord for STypes.ShortRecord;
    using LibSRUtil for STypes.ShortRecord;
    using U256 for uint256;
    using U88 for uint88;
    using U80 for uint80;

    /**
     * @notice Liquidates short using liquidator's ercEscrowed or wallet
     * @dev Secondary liquidation function
     * @dev Must liquidate all of the debt. No partial (unless TAPP short)
     *
     * @param asset The market that will be impacted
     * @param batches Array of shorters, shortRecordIds, and shortOrderIds to liquidate
     * @param liquidateAmount Amount of ercDebt to liquidate
     * @param isWallet Liquidate using wallet balance when true, ercEscrowed when false
     *
     */

    // @dev If you want to liquidated more than uint88.max worth of erc in shorts, you must call liquidateSecondary multiple times
    function liquidateSecondary(address asset, MTypes.BatchLiquidation[] memory batches, uint88 liquidateAmount, bool isWallet)
        external
        onlyValidAsset(asset)
        isNotFrozen(asset)
        nonReentrant
    {
        MTypes.AssetParams memory a;
        a.asset = asset;

        STypes.Asset storage Asset = s.asset[asset];
        STypes.AssetUser storage AssetUser = s.assetUser[asset][msg.sender];
        a.penaltyCR = LibAsset.penaltyCR(asset);
        a.oraclePrice = LibOracle.getSavedOrSpotOraclePrice(asset);
        a.liquidationCR = LibAsset.liquidationCR(asset);
        a.minShortErc = LibAsset.minShortErc(Asset);
        a.ercDebtRate = Asset.ercDebtRate;

        uint88 liquidatorCollateral;
        uint88 liquidateAmountLeft = liquidateAmount;
        uint88 ercDebtFee;

        MTypes.SecondaryLiquidation memory m;
        for (uint256 i; i < batches.length;) {
            m = _setLiquidationStruct(batches[i], a);
            unchecked {
                ++i;
            }

            // If ineligible, skip to the next shortrecord instead of reverting
            if (
                m.shorter == msg.sender || m.cRatio > a.liquidationCR || m.short.status == SR.Closed || m.short.ercDebt == 0
                    || (m.shorter != address(this) && liquidateAmountLeft < m.short.ercDebt)
            ) continue;

            bool shortUnderMin; // Too little erc or too little eth
            if (m.isPartialFill) {
                // Check attached shortOrder ercAmount left since SR will be fully liquidated
                STypes.Order storage shortOrder = s.shorts[a.asset][m.shortOrderId];
                // Skip instead of reverting for invalid shortOrder
                if (LibSRUtil.invalidShortOrder(shortOrder, m.short.id, m.shorter)) continue;
                // @dev shortOrder needs to be verified BEFORE using
                shortUnderMin = shortOrder.ercAmount < a.minShortErc || shortOrder.shortOrderCR < Asset.initialCR;
            }

            bool partialTappLiquidation;
            // Setup partial liquidation of TAPP short
            if (m.shorter == address(this)) {
                partialTappLiquidation = liquidateAmountLeft < m.short.ercDebt;
                if (partialTappLiquidation) {
                    m.short.ercDebt = liquidateAmountLeft;
                }
            }

            // Determine which secondary liquidation method to use
            if (isWallet) {
                IAsset tokenContract = IAsset(a.asset);
                uint256 walletBalance = tokenContract.balanceOf(msg.sender);
                if (walletBalance < m.short.ercDebt) continue;
                tokenContract.burnFrom(msg.sender, m.short.ercDebt);
                assert(tokenContract.balanceOf(msg.sender) < walletBalance);
            } else {
                if (AssetUser.ercEscrowed < m.short.ercDebt) continue;
                AssetUser.ercEscrowed -= m.short.ercDebt;
            }

            if (partialTappLiquidation) {
                // Partial liquidation of TAPP short
                _secondaryLiquidationHelperPartialTapp(m, a);
            } else {
                // Full liquidation
                _secondaryLiquidationHelper(m, a);
            }

            // @dev cancels shortOrder of partialFilled SR
            if (shortUnderMin) {
                LibOrders.cancelShort(a.asset, m.shortOrderId);
            }

            // Update in memory for final state change after loops
            liquidatorCollateral += m.liquidatorCollateral;
            liquidateAmountLeft -= m.short.ercDebt;
            ercDebtFee += m.short.ercDebtFee;
            if (liquidateAmountLeft == 0) break;
        }

        if (liquidateAmount == liquidateAmountLeft) revert Errors.SecondaryLiquidationNoValidShorts();

        // Update finalized state changes
        Asset.ercDebt -= liquidateAmount - liquidateAmountLeft;
        Asset.ercDebtFee -= ercDebtFee;
        s.vaultUser[Asset.vault][msg.sender].ethEscrowed += liquidatorCollateral;

        emit Events.LiquidateSecondary(asset, batches, msg.sender, isWallet);
    }

    /**
     * @notice Sets the memory struct m with initial data
     *
     * @param batch Struct of shorters, shortRecordIds, and shortOrderIds to liquidate
     * @param a Parameters of the market
     *
     * @return m Memory struct used throughout PrimaryLiquidationFacet.sol
     */
    function _setLiquidationStruct(MTypes.BatchLiquidation memory batch, MTypes.AssetParams memory a)
        private
        returns (MTypes.SecondaryLiquidation memory m)
    {
        STypes.ShortRecord storage shortRecord = s.shortRecords[a.asset][batch.shorter][batch.shortId];
        shortRecord.updateErcDebt(a.ercDebtRate);
        m.short = shortRecord;

        if (m.short.ercDebt == 0) return m; // @dev To avoid divide by 0 for CR calc, SR will be skipped anyways

        m.shorter = batch.shorter;
        m.cRatio = m.short.getCollateralRatio(a.oraclePrice);
        m.shortOrderId = batch.shortOrderId;
        m.isPartialFill = m.short.status == SR.PartialFill;
    }

    /**
     * @notice Handles accounting for secondary liquidation methods (wallet and ercEscrowed)
     *
     * @param m Memory struct used throughout PrimaryLiquidationFacet.sol
     *
     */
    // +----------------+---------------+---------+-------+
    // |     Cratio     |  Liquidator   | Shorter | Pool  |
    // +----------------+---------------+---------+-------+
    // | > 1.5          | (cannot call) | n/a     | n/a   |
    // | 1.1 < c <= 1.5 | 1             | c - 1   | 0     |
    // | 1.0 < c <= 1.1 | 1             | 0       | c - 1 |
    // | c <= 1         | c             | 0       | 0     |
    // +----------------+---------------+---------+-------+
    function _secondaryLiquidationHelper(MTypes.SecondaryLiquidation memory m, MTypes.AssetParams memory a) private {
        if (m.cRatio > 1 ether) {
            m.liquidatorCollateral = m.short.ercDebt.mulU88(a.oraclePrice); // eth

            // if cRatio > 110%, shorter gets remaining collateral
            // Otherwise they take a penalty, and remaining goes to the pool
            address remainingCollateralAddress = m.cRatio > a.penaltyCR ? m.shorter : address(this);

            s.vaultUser[s.asset[a.asset].vault][remainingCollateralAddress].ethEscrowed +=
                m.short.collateral - m.liquidatorCollateral;
        } else {
            m.liquidatorCollateral = m.short.collateral;
        }

        LibSRUtil.disburseCollateral(a.asset, m.shorter, m.short.collateral, m.short.dethYieldRate, m.short.updatedAt);
        LibShortRecord.deleteShortRecord(a.asset, m.shorter, m.short.id);
    }

    function min88(uint256 a, uint88 b) private pure returns (uint88) {
        if (a > type(uint88).max) revert Errors.InvalidAmount();
        return a < b ? uint88(a) : b;
    }

    function _secondaryLiquidationHelperPartialTapp(MTypes.SecondaryLiquidation memory m, MTypes.AssetParams memory a) private {
        STypes.ShortRecord storage short = s.shortRecords[a.asset][address(this)][m.short.id];
        // Update erc balance
        short.ercDebt -= m.short.ercDebt; // @dev m.short.ercDebt was updated earlier to equal erc filled
        // Update eth balance
        // @dev Need to use min if CR < 1
        m.liquidatorCollateral = min88(m.short.ercDebt.mul(a.oraclePrice), m.short.collateral);
        short.collateral -= m.liquidatorCollateral;
        LibSRUtil.disburseCollateral(a.asset, m.shorter, m.liquidatorCollateral, m.short.dethYieldRate, m.short.updatedAt);
    }
}
