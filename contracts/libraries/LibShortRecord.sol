// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {U256, U88, U80} from "contracts/libraries/PRBMathHelper.sol";

import {STypes, SR} from "contracts/libraries/DataTypes.sol";
import {Errors} from "contracts/libraries/Errors.sol";
import {Events} from "contracts/libraries/Events.sol";
import {AppStorage, appStorage} from "contracts/libraries/AppStorage.sol";
import {C} from "contracts/libraries/Constants.sol";
import {LibBridgeRouter} from "contracts/libraries/LibBridgeRouter.sol";
import {LibOrders} from "contracts/libraries/LibOrders.sol";
import {LibOracle} from "contracts/libraries/LibOracle.sol";

// import {console} from "contracts/libraries/console.sol";

library LibShortRecord {
    using U256 for uint256;
    using U88 for uint88;
    using U80 for uint80;
    using LibBridgeRouter for address;

    function getCollateralRatio(STypes.ShortRecord memory short, uint256 oraclePrice) internal pure returns (uint256 cRatio) {
        return short.collateral.div(short.ercDebt.mul(oraclePrice));
    }

    /**
     * @notice Returns number of active shortRecords
     *
     * @param asset The market that will be impacted
     * @param shorter Shorter address
     *
     * @return shortRecordCount
     */
    function getShortRecordCount(address asset, address shorter) internal view returns (uint256 shortRecordCount) {
        AppStorage storage s = appStorage();

        // Retrieve first non-HEAD short
        uint8 id = s.shortRecords[asset][shorter][C.HEAD].nextId;
        if (id <= C.HEAD) {
            return 0;
        }

        while (true) {
            // One short of one shorter in this order book
            STypes.ShortRecord storage currentShort = s.shortRecords[asset][shorter][id];
            if (currentShort.status != SR.Closed) shortRecordCount++;
            // Move to next short unless this is the last one
            if (currentShort.nextId > C.HEAD) {
                id = currentShort.nextId;
            } else {
                return shortRecordCount;
            }
        }
    }

    function createShortRecord(
        address asset,
        address shorter,
        SR status,
        uint88 collateral,
        uint88 ercAmount,
        uint80 ercDebtRate,
        uint80 dethYieldRate,
        uint88 ercDebtFee
    ) internal returns (uint8 id) {
        AppStorage storage s = appStorage();

        uint8 nextId;
        (id, nextId) = setShortRecordIds(asset, shorter);

        STypes.ShortRecord storage shortRecord = s.shortRecords[asset][shorter][id];
        shortRecord.prevId = C.HEAD;
        shortRecord.id = id;
        shortRecord.nextId = nextId;
        shortRecord.status = status;
        shortRecord.collateral = collateral;
        shortRecord.ercDebt = ercAmount;
        shortRecord.ercDebtRate = ercDebtRate;
        shortRecord.dethYieldRate = dethYieldRate;
        shortRecord.updatedAt = LibOrders.getOffsetTime();
        shortRecord.ercDebtFee = ercDebtFee;

        emit Events.CreateShortRecord(asset, shorter, id);
    }

    function fillShortRecord(
        address asset,
        address shorter,
        uint8 shortId,
        SR status,
        uint88 collateral,
        uint88 ercAmount,
        uint80 ercDebtRate,
        uint80 dethYieldRate,
        uint88 ercDebtFee
    ) internal returns (uint88 ethInitial) {
        AppStorage storage s = appStorage();
        STypes.ShortRecord storage short = s.shortRecords[asset][shorter][shortId];

        if (short.status == SR.Closed) {
            // No need to blend/merge components if the shortRecord was closed, simply overwrite
            short.ercDebt = ercAmount;
            short.ercDebtRate = ercDebtRate;
            short.dethYieldRate = dethYieldRate;
            short.updatedAt = LibOrders.getOffsetTime();
            // This is the one exception in the case of seeded collateral for capital efficient SR
            ethInitial = short.collateral;
            short.collateral += collateral;
            short.ercDebtFee += ercDebtFee;
        } else {
            uint256 ercDebtSocialized = ercAmount.mul(ercDebtRate);
            uint256 yield = collateral.mul(dethYieldRate);
            merge(short, ercAmount, ercDebtSocialized, collateral, yield, LibOrders.getOffsetTime(), ercDebtFee);
        }
        // @dev Must be set after if statement eval
        short.status = status;
    }

    function deleteShortRecord(address asset, address shorter, uint8 id) internal {
        AppStorage storage s = appStorage();

        STypes.ShortRecord storage shortRecord = s.shortRecords[asset][shorter][id];

        // Because of the onlyValidShortRecord modifier, only cancelShort can pass SR.Closed
        if (shortRecord.status != SR.PartialFill && shorter != address(this)) {
            // remove the links of ID in the market
            // @dev (ID) is exiting, [ID] is inserted
            // BEFORE: PREV <-> (ID) <-> NEXT
            // AFTER : PREV <----------> NEXT
            s.shortRecords[asset][shorter][shortRecord.prevId].nextId = shortRecord.nextId;
            if (shortRecord.nextId != C.HEAD) {
                s.shortRecords[asset][shorter][shortRecord.nextId].prevId = shortRecord.prevId;
            }
            // Make reuseable for future short records
            uint8 prevHEAD = s.shortRecords[asset][shorter][C.HEAD].prevId;
            s.shortRecords[asset][shorter][C.HEAD].prevId = id;
            // Move the cancelled ID behind HEAD to re-use it
            // note: C_IDs (cancelled ids) only need to point back (set prevId, can retain nextId)
            // BEFORE: .. C_ID2 <- C_ID1 <--------- HEAD <-> ... [ID]
            // AFTER1: .. C_ID2 <- C_ID1 <- [ID] <- HEAD <-> ...
            if (prevHEAD > C.HEAD) {
                shortRecord.prevId = prevHEAD;
            } else {
                // if this is the first ID cancelled
                // HEAD.prevId needs to be HEAD
                // and one of the cancelled id.prevID should point to HEAD
                // BEFORE: HEAD <--------- HEAD <-> ... [ID]
                // AFTER1: HEAD <- [ID] <- HEAD <-> ...
                shortRecord.prevId = C.HEAD;
            }

            //Event for delete SR is emitted here and not at the top level because
            //SR may be cancelled, but there might tied to an active short order
            //The code above is hit when that SR id is ready for reuse
            emit Events.DeleteShortRecord(asset, shorter, id);
        }

        shortRecord.status = SR.Closed;
        // @dev Necessary for seeding closed SR for capital efficient SR
        shortRecord.collateral = 0;
    }

    function setShortRecordIds(address asset, address shorter) private returns (uint8 id, uint8 nextId) {
        AppStorage storage s = appStorage();

        STypes.ShortRecord storage headSR = s.shortRecords[asset][shorter][C.HEAD];
        STypes.AssetUser storage AssetUser = s.assetUser[asset][shorter];
        // Initialize HEAD in case of first short createShortRecord
        if (AssetUser.shortRecordCounter == 0) {
            AssetUser.shortRecordCounter = C.SHORT_STARTING_ID;
            headSR.prevId = C.HEAD;
            headSR.nextId = C.HEAD;
        }
        // BEFORE: HEAD <-> .. <-> PREV <--------------> NEXT
        // AFTER1: HEAD <-> .. <-> PREV <-> (NEW ID) <-> NEXT
        // place created short next to HEAD
        nextId = headSR.nextId;
        uint8 canceledId = headSR.prevId;
        // @dev (ID) is exiting, [ID] is inserted
        // in this case, the protocol re-uses (ID) and moves it to [ID]
        // check if a previously closed short exists
        if (canceledId > C.HEAD) {
            // BEFORE: CancelledID <- (ID) <- HEAD <-> .. <-> PREV <----------> NEXT
            // AFTER1: CancelledID <--------- HEAD <-> .. <-> PREV <-> [ID] <-> NEXT
            uint8 prevCanceledId = s.shortRecords[asset][shorter][canceledId].prevId;
            if (prevCanceledId > C.HEAD) {
                headSR.prevId = prevCanceledId;
            } else {
                // BEFORE: HEAD <- (ID) <- HEAD <-> .. <-> PREV <----------> NEXT
                // AFTER1: HEAD <--------- HEAD <-> .. <-> PREV <-> [ID] <-> NEXT
                headSR.prevId = C.HEAD;
            }
            // re-use the previous order's id
            id = canceledId;
        } else {
            // BEFORE: HEAD <-> .. <-> PREV <--------------> NEXT
            // AFTER1: HEAD <-> .. <-> PREV <-> (NEW ID) <-> NEXT
            // otherwise just increment to a new short record id
            // and the short record grows in height/size
            id = AssetUser.shortRecordCounter;
            // Avoids overflow revert, prevents DOS on uint8
            if (id < C.SHORT_MAX_ID) {
                AssetUser.shortRecordCounter += 1;
            } else {
                revert Errors.CannotMakeMoreThanMaxSR();
            }
        }

        if (nextId > C.HEAD) {
            s.shortRecords[asset][shorter][nextId].prevId = id;
        }
        headSR.nextId = id;
    }

    function merge(
        STypes.ShortRecord storage short,
        uint88 ercDebt,
        uint256 ercDebtSocialized,
        uint88 collateral,
        uint256 yield,
        uint32 creationTime,
        uint88 ercDebtFee
    ) internal {
        // Resolve ercDebt
        if (ercDebt > 0 || ercDebtSocialized > 0) {
            ercDebtSocialized += short.ercDebt.mul(short.ercDebtRate);
            short.ercDebt += ercDebt;
            short.ercDebtRate = ercDebtSocialized.divU64(short.ercDebt);
            short.ercDebtFee += ercDebtFee;
        }

        // Resolve dethCollateral
        yield += short.collateral.mul(short.dethYieldRate);
        short.collateral += collateral;
        short.dethYieldRate = yield.divU80(short.collateral);
        // Assign updatedAt
        short.updatedAt = creationTime;
    }
}
