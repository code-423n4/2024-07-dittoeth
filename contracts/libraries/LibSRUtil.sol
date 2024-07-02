// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {U88, U256} from "contracts/libraries/PRBMathHelper.sol";

import {STypes, SR, O} from "contracts/libraries/DataTypes.sol";
import {AppStorage, appStorage} from "contracts/libraries/AppStorage.sol";
import {C} from "contracts/libraries/Constants.sol";
import {LibOrders} from "contracts/libraries/LibOrders.sol";
import {LibShortRecord} from "contracts/libraries/LibShortRecord.sol";
import {LibAsset} from "contracts/libraries/LibAsset.sol";
import {Errors} from "contracts/libraries/Errors.sol";
import {LibBridgeRouter} from "contracts/libraries/LibBridgeRouter.sol";

// import {console} from "contracts/libraries/console.sol";

// extra ShortRecord helpers, similar to LibShortRecord
library LibSRUtil {
    using U88 for uint88;
    using U256 for uint256;

    function disburseCollateral(address asset, address shorter, uint88 collateral, uint256 dethYieldRate, uint32 updatedAt)
        internal
    {
        AppStorage storage s = appStorage();

        STypes.Asset storage Asset = s.asset[asset];
        uint256 vault = Asset.vault;
        STypes.Vault storage Vault = s.vault[vault];

        Vault.dethCollateral -= collateral;
        Asset.dethCollateral -= collateral;
        // Distribute yield
        uint88 yield = collateral.mulU88(Vault.dethYieldRate - dethYieldRate);
        if (yield > 0) {
            /*
            @dev If somebody exits a short, gets liquidated, decreases their collateral before YIELD_DELAY_SECONDS duration is up,
            they lose their yield to the TAPP
            */
            bool isNotRecentlyModified = LibOrders.getOffsetTime() - updatedAt > C.YIELD_DELAY_SECONDS;
            if (isNotRecentlyModified) {
                s.vaultUser[vault][shorter].ethEscrowed += yield;
            } else {
                s.vaultUser[vault][address(this)].ethEscrowed += yield;
            }
        }
    }

    function invalidShortOrder(STypes.Order storage shortOrder, uint8 shortRecordId, address shorter)
        internal
        view
        returns (bool isInvalid)
    {
        if (shortOrder.shortRecordId != shortRecordId || shortOrder.addr != shorter || shortOrder.orderType != O.LimitShort) {
            return true;
        }
    }

    function checkCancelShortOrder(address asset, SR initialStatus, uint16 shortOrderId, uint8 shortRecordId, address shorter)
        internal
        returns (bool isCancelled)
    {
        AppStorage storage s = appStorage();
        if (initialStatus == SR.PartialFill) {
            STypes.Order storage shortOrder = s.shorts[asset][shortOrderId];
            if (invalidShortOrder(shortOrder, shortRecordId, shorter)) revert Errors.InvalidShortOrder();
            LibOrders.cancelShort(asset, shortOrderId);
            return true;
        }
    }

    function checkShortMinErc(address asset, SR initialStatus, uint16 shortOrderId, uint8 shortRecordId, address shorter)
        internal
    {
        AppStorage storage s = appStorage();

        STypes.ShortRecord storage shortRecord = s.shortRecords[asset][shorter][shortRecordId];
        STypes.Asset storage Asset = s.asset[asset];
        uint256 minShortErc = LibAsset.minShortErc(Asset);

        if (initialStatus == SR.PartialFill) {
            // Verify shortOrder
            STypes.Order storage shortOrder = s.shorts[asset][shortOrderId];
            if (invalidShortOrder(shortOrder, shortRecordId, shorter)) revert Errors.InvalidShortOrder();

            if (shortRecord.status == SR.Closed) {
                // Check remaining shortOrder for too little erc or too little eth
                if (shortOrder.ercAmount < minShortErc || shortOrder.shortOrderCR < Asset.initialCR) {
                    // @dev The resulting SR will not have PartialFill status after cancel
                    LibOrders.cancelShort(asset, shortOrderId);
                }
            } else {
                // Check remaining shortOrder and remaining shortRecord
                if (shortOrder.ercAmount + shortRecord.ercDebt < minShortErc) revert Errors.CannotLeaveDustAmount();
                // Partial primary liquidation of capital efficient SR may not leave enough eth
                if (shorter != msg.sender && shortOrder.shortOrderCR < Asset.initialCR) revert Errors.CannotLeaveDustAmount();
            }
        } else if (shortRecord.status != SR.Closed && shortRecord.ercDebt < minShortErc) {
            revert Errors.CannotLeaveDustAmount();
        }
    }

    function checkRecoveryModeViolation(STypes.Asset storage Asset, uint256 shortRecordCR, uint256 oraclePrice)
        internal
        view
        returns (bool recoveryViolation)
    {
        uint256 recoveryCR = LibAsset.recoveryCR(Asset);
        if (shortRecordCR < recoveryCR) {
            // Only check asset CR if low enough
            uint256 ercDebt = Asset.ercDebt;
            if (ercDebt > 0) {
                // If Asset.ercDebt == 0 then assetCR is NA
                uint256 assetCR = LibAsset.getAssetCollateralRatio(Asset, oraclePrice);
                if (assetCR < recoveryCR) {
                    // Market is in recovery mode and shortRecord CR too low
                    return true;
                }
            }
        }
    }

    function updateErcDebt(STypes.ShortRecord storage short, address asset) internal {
        AppStorage storage s = appStorage();

        // Distribute ercDebt
        uint80 ercDebtRate = s.asset[asset].ercDebtRate;
        updateErcDebt(short, ercDebtRate);
    }

    function updateErcDebt(STypes.ShortRecord storage short, uint80 ercDebtRate) internal {
        // Distribute ercDebt
        uint88 ercDebt = (short.ercDebt - short.ercDebtFee).mulU88(ercDebtRate - short.ercDebtRate);

        if (ercDebt > 0) {
            short.ercDebt += ercDebt;
            short.ercDebtFee += ercDebt;
            short.ercDebtRate = ercDebtRate;
        }
    }

    function onlyValidShortRecord(address asset, address shorter, uint8 id)
        internal
        view
        returns (STypes.ShortRecord storage shortRecord)
    {
        AppStorage storage s = appStorage();
        shortRecord = s.shortRecords[asset][shorter][id];
        if (shortRecord.status == SR.Closed || shortRecord.ercDebt == 0) revert Errors.InvalidShortId();
    }

    function reduceErcDebtFee(STypes.Asset storage Asset, STypes.ShortRecord storage short, uint256 ercDebtReduction) internal {
        uint88 ercDebtFeeReduction = uint88(LibOrders.min(short.ercDebtFee, ercDebtReduction)); // @dev(safe-cast)
        Asset.ercDebtFee -= ercDebtFeeReduction;
        short.ercDebtFee -= ercDebtFeeReduction;
    }
}
