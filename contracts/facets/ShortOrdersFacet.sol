// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {U256, U80} from "contracts/libraries/PRBMathHelper.sol";

import {Errors} from "contracts/libraries/Errors.sol";
import {STypes, MTypes, O, SR} from "contracts/libraries/DataTypes.sol";
import {Modifiers} from "contracts/libraries/AppStorage.sol";
import {LibOrders} from "contracts/libraries/LibOrders.sol";
import {LibAsset} from "contracts/libraries/LibAsset.sol";
import {LibOracle} from "contracts/libraries/LibOracle.sol";
import {LibShortRecord} from "contracts/libraries/LibShortRecord.sol";
import {LibSRUtil} from "contracts/libraries/LibSRUtil.sol";
import {C} from "contracts/libraries/Constants.sol";

// import {console} from "contracts/libraries/console.sol";

contract ShortOrdersFacet is Modifiers {
    using U256 for uint256;
    using U80 for uint80;

    /**
     * @notice Creates limit short in market system
     * @dev incomingShort created here instead of AskMatchAlgo to prevent stack too deep
     * @dev Shorts can only be limits
     *
     * @param asset The market that will be impacted
     * @param price Unit price in eth for erc sold
     * @param ercAmount Amount of erc minted and sold
     * @param orderHintArray Array of hint ID for gas-optimized sorted placement on market
     * @param shortHintArray Array of hint ID for gas-optimized short matching above oracle price
     * @param shortOrderCR Initial Collateral Ratio for a short order, between min/max, converted to uint8
     */
    function createLimitShort(
        address asset,
        uint80 price,
        uint88 ercAmount,
        MTypes.OrderHint[] memory orderHintArray,
        uint16[] memory shortHintArray,
        uint16 shortOrderCR
    ) external isNotFrozen(asset) onlyValidAsset(asset) nonReentrant {
        MTypes.CreateLimitShortParam memory p;
        STypes.Asset storage Asset = s.asset[asset];

        p.CR = LibOrders.convertCR(shortOrderCR);
        p.initialCR = LibAsset.initialCR(Asset);
        if (p.CR + C.BID_CR < p.initialCR || p.CR >= C.CRATIO_MAX_INITIAL) revert Errors.InvalidCR();

        p.eth = price.mul(ercAmount);
        p.minAskEth = LibAsset.minAskEth(Asset);
        p.minShortErc = LibAsset.minShortErc(Asset);
        if (ercAmount < p.minShortErc || p.eth < p.minAskEth) revert Errors.OrderUnderMinimumSize();

        STypes.VaultUser storage vaultUser = s.vaultUser[Asset.vault][msg.sender];
        // @dev When shortOrderCR less than initialCR, eth is needed to seed the SR to guarantee minShortErc collateralized @ initialCR
        if (p.CR < p.initialCR) {
            uint256 minEth = price.mul(p.minShortErc);
            uint256 diffCR = p.initialCR - p.CR;
            p.ethInitial = minEth.mul(diffCR);
            // Need enough collateral to cover minting ercDebt @ shortOrderCR and minShortErc @ initialCR
            if (vaultUser.ethEscrowed < p.eth.mul(p.CR) + p.ethInitial) revert Errors.InsufficientETHEscrowed();
            vaultUser.ethEscrowed -= uint88(p.ethInitial); // @dev(safe-cast)
        } else if (vaultUser.ethEscrowed < p.eth.mul(p.CR)) {
            // Need enough collateral to cover minting ercDebt @ shortOrderCR
            revert Errors.InsufficientETHEscrowed();
        }

        STypes.Order memory incomingShort;
        // @dev create "empty" SR, unless some collateral is seeded to ensure minShortErc collateralization requirement
        incomingShort.shortRecordId =
            LibShortRecord.createShortRecord(asset, msg.sender, SR.Closed, uint88(p.ethInitial), 0, 0, 0, 0); // @dev(safe-cast)
        incomingShort.addr = msg.sender;
        incomingShort.price = price;
        incomingShort.ercAmount = ercAmount;
        incomingShort.orderType = O.LimitShort;
        incomingShort.shortOrderCR = shortOrderCR;

        uint16 startingId = s.bids[asset][C.HEAD].nextId;
        STypes.Order storage highestBid = s.bids[asset][startingId];
        // @dev if match and match price is gt .5% to saved oracle in either direction, update startingShortId
        if (highestBid.price >= incomingShort.price && highestBid.orderType == O.LimitBid) {
            LibOrders.updateOracleAndStartingShortViaThreshold(asset, incomingShort, shortHintArray);
        }

        p.oraclePrice = LibOracle.getSavedOrSpotOraclePrice(asset);
        if (LibSRUtil.checkRecoveryModeViolation(Asset, p.CR, p.oraclePrice)) revert Errors.BelowRecoveryModeCR();

        // @dev reading spot oracle price
        if (incomingShort.price < p.oraclePrice) {
            LibOrders.addShort(asset, incomingShort, orderHintArray);
        } else {
            LibOrders.sellMatchAlgo(asset, incomingShort, orderHintArray, p.minAskEth);
        }
    }
}
