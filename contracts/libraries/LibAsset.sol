// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {U256, U88} from "contracts/libraries/PRBMathHelper.sol";

import {STypes} from "contracts/libraries/DataTypes.sol";
import {AppStorage, appStorage} from "contracts/libraries/AppStorage.sol";
import {C} from "contracts/libraries/Constants.sol";
import {IAsset} from "interfaces/IAsset.sol";
import {Errors} from "contracts/libraries/Errors.sol";

library LibAsset {
    using U256 for uint256;
    using U88 for uint88;

    // @dev used in ExitShortWallet and MarketShutDown
    function burnMsgSenderDebt(address asset, uint88 debt) internal {
        IAsset tokenContract = IAsset(asset);
        uint256 walletBalance = tokenContract.balanceOf(msg.sender);
        if (walletBalance < debt) revert Errors.InsufficientWalletBalance();
        tokenContract.burnFrom(msg.sender, debt);
        assert(tokenContract.balanceOf(msg.sender) < walletBalance);
    }

    function getAssetCollateralRatio(STypes.Asset storage Asset, uint256 oraclePrice) internal view returns (uint256 assetCR) {
        return Asset.dethCollateral.div(oraclePrice.mul(Asset.ercDebt));
    }

    // default of 1.7 ether, stored in uint16 as 170
    // range of [1-10],
    // 2 decimal places, divide by 100
    // i.e. 123 -> 1.23 ether
    // @dev cRatio that a short order has to begin at
    function initialCR(STypes.Asset storage Asset) internal view returns (uint256) {
        return (uint256(Asset.initialCR) * 1 ether) / C.TWO_DECIMAL_PLACES;
    }

    // default of 1.5 ether, stored in uint16 as 150
    // range of [1-5],
    // 2 decimal places, divide by 100
    // i.e. 120 -> 1.2 ether
    // less than initialCR
    // @dev cRatio that a shortRecord can be liquidated at
    function liquidationCR(address asset) internal view returns (uint256) {
        AppStorage storage s = appStorage();
        return (uint256(s.asset[asset].liquidationCR) * 1 ether) / C.TWO_DECIMAL_PLACES;
    }

    // default of 1.1 ether, stored in uint8 as 110
    // range of [1-2],
    // 2 decimal places, divide by 100
    // i.e. 120 -> 1.2 ether
    // less than liquidationCR
    // @dev buffer/slippage for forcedBid price
    function forcedBidPriceBuffer(address asset) internal view returns (uint256) {
        AppStorage storage s = appStorage();
        return (uint256(s.asset[asset].forcedBidPriceBuffer) * 1 ether) / C.TWO_DECIMAL_PLACES;
    }

    // default of 1.1 ether, stored in uint8 as 110
    // range of [1-2],
    // 2 decimal places, divide by 100
    // i.e. 120 -> 1.2 ether
    // @dev cRatio where a shorter loses all collateral on liquidation
    function penaltyCR(address asset) internal view returns (uint256) {
        AppStorage storage s = appStorage();
        return (uint256(s.asset[asset].penaltyCR) * 1 ether) / C.TWO_DECIMAL_PLACES;
    }

    // default of .025 ether, stored in uint8 as 25
    // range of [0.1-2.5%],
    // 3 decimal places, divide by 1000
    // i.e. 1234 -> 1.234 ether
    // @dev percentage of fees given to TAPP during liquidations
    function tappFeePct(address asset) internal view returns (uint256) {
        AppStorage storage s = appStorage();
        return (uint256(s.asset[asset].tappFeePct) * 1 ether) / C.THREE_DECIMAL_PLACES;
    }

    // default of .005 ether, stored in uint8 as 5
    // range of [0.1-2.5%],
    // 3 decimal places, divide by 1000
    // i.e. 1234 -> 1.234 ether
    // @dev percentage of fees given to the liquidator during liquidations
    function callerFeePct(address asset) internal view returns (uint256) {
        AppStorage storage s = appStorage();
        return (uint256(s.asset[asset].callerFeePct) * 1 ether) / C.THREE_DECIMAL_PLACES;
    }

    // default of .1 ether, stored in uint8 as 10
    // range of [.01 - 2.55],
    // 2 decimal places, divide by 100
    // i.e. 125 -> 1.25 ether
    // @dev dust amount
    function minBidEth(address asset) internal view returns (uint256) {
        AppStorage storage s = appStorage();
        return (uint256(s.asset[asset].minBidEth) * 1 ether) / C.TWO_DECIMAL_PLACES;
    }

    // default of .1 ether, stored in uint8 as 10
    // range of [.01 - 2.55],
    // 2 decimal places, divide by 100
    // i.e. 125 -> 1.25 ether
    // @dev dust amount
    function minAskEth(STypes.Asset storage Asset) internal view returns (uint256) {
        return (uint256(Asset.minAskEth) * 1 ether) / C.TWO_DECIMAL_PLACES;
    }

    // default of 2000 ether, stored in uint16 as 2000
    // range of [1 - 65,535 (uint16 max)],
    // i.e. 2000 -> 2000 ether
    // @dev min short record debt
    function minShortErc(STypes.Asset storage Asset) internal view returns (uint256) {
        return uint256(Asset.minShortErc) * 1 ether;
    }

    // default of 1.5 ether, stored in uint8 as 150
    // range of [1-2],
    // 2 decimal places, divide by 100
    // i.e. 120 -> 1.2 ether
    // @dev cRatio where the market enters recovery mode
    function recoveryCR(STypes.Asset storage Asset) internal view returns (uint256) {
        return (uint256(Asset.recoveryCR) * 1 ether) / C.TWO_DECIMAL_PLACES;
    }

    // default of .001 ether, stored in uint16 as 10
    // range of [1 - 10000],
    // 4 decimal places, divide by 10000
    // i.e. 120 -> .012 ether
    // @dev penalty fee applied to ercDebtRate when assets are traded at discount
    function discountPenaltyFee(STypes.Asset storage Asset) internal view returns (uint256) {
        return (uint256(Asset.discountPenaltyFee) * 1 ether) / C.FOUR_DECIMAL_PLACES;
    }

    // default of 10 ether, stored in uint16 as 10000
    // range of [1 - 65535],
    // 4 decimal places, divide by 1000
    // i.e. 5000 -> 5 ether
    // @dev multiplier applied to discount when increasing discountedErcMatched
    function discountMultiplier(STypes.Asset storage Asset) internal view returns (uint256) {
        return (uint256(Asset.discountMultiplier) * 1 ether) / C.THREE_DECIMAL_PLACES;
    }
}
