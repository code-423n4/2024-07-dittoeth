// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {U256, U104, U88} from "contracts/libraries/PRBMathHelper.sol";
import {IDiamond} from "interfaces/IDiamond.sol";
import {AppStorage, appStorage} from "contracts/libraries/AppStorage.sol";
import {STypes, MTypes, O, SR} from "contracts/libraries/DataTypes.sol";
import {LibAsset} from "contracts/libraries/LibAsset.sol";
import {LibOracle} from "contracts/libraries/LibOracle.sol";
import {LibOrders} from "contracts/libraries/LibOrders.sol";
import {C} from "contracts/libraries/Constants.sol";

// import {console} from "contracts/libraries/console.sol";

library LibPriceDiscount {
    using LibOracle for address;
    using U256 for uint256;
    using U104 for uint104;
    using U88 for uint88;

    // Approximates the match price compared to the oracle price and accounts for any discount by increasing ercDebtRate
    function handlePriceDiscount(address asset, uint256 price, uint256 ercAmount) internal {
        AppStorage storage s = appStorage();
        MTypes.HandleDiscount memory h;
        h.asset = asset;
        STypes.Asset storage Asset = s.asset[h.asset];
        h.ercDebt = Asset.ercDebt;
        h.price = price;
        h.ercAmount = ercAmount;
        // @dev No need to consider discounts if system-wide ercDebt is low
        if (h.ercDebt <= C.DISCOUNT_UPDATE_THRESHOLD) return;
        h.savedPrice = LibOracle.getPrice(h.asset);
        // @dev Applying penalty to ercDebt when asset level CR is low is harmful
        uint256 assetCR = LibAsset.getAssetCollateralRatio(Asset, h.savedPrice);
        if (assetCR <= LibAsset.recoveryCR(Asset)) return;
        // @dev Only consider discounts that are meaningfully different from oracle price
        if (h.savedPrice > h.price.mul(1 ether + C.DISCOUNT_THRESHOLD)) {
            IDiamond(payable(address(this)))._matchIsDiscounted(h);
        } else {
            if (Asset.discountedErcMatched > h.ercAmount) {
                Asset.discountedErcMatched -= uint88(h.ercAmount); // @dev(safe-cast)
            } else {
                Asset.discountedErcMatched = 1 wei;
            }
            // @dev Reset iniitialDiscountTime to reset the daysElapsed multiplier
            Asset.initialDiscountTime = 1 seconds;
        }
    }
}
