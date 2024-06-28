// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {U256, U88, U80} from "contracts/libraries/PRBMathHelper.sol";
import {VAULT} from "contracts/libraries/Constants.sol";
import {O, SR, STypes, MTypes} from "contracts/libraries/DataTypes.sol";
import {C} from "contracts/libraries/Constants.sol";

import {InvariantsBase} from "./InvariantsBase.sol";

import {IAsset} from "interfaces/IAsset.sol";
import {LibOrders} from "contracts/libraries/LibOrders.sol";
import {LibBytes} from "contracts/libraries/LibBytes.sol";

import {Handler} from "./Handler.sol";

import {console} from "contracts/libraries/console.sol";

contract InvariantsSandbox is InvariantsBase {
    using U256 for uint256;
    using U88 for uint88;
    using U80 for uint80;

    function setUp() public override {
        super.setUp();

        targetSelector(FuzzSelector({addr: address(s_handler), selectors: selectors}));
        targetContract(address(s_handler));
    }

    // function test_InvariantScenario() public {
    //     address shorter = 0x000000000000000000000000000000000000000b;
    //     uint64 assetErcDebtRate = diamond.getAssetStruct(asset).ercDebtRate;

    //     s_handler.deposit(11, 1349);
    //     assertEq(assetErcDebtRate, 0);
    //     // These don't match
    //     s_handler.createLimitBidDiscounted(217223247450412, 42958072527563220, 0);
    //     assertEq(diamond.getBids(asset)[0].price, 239723247450413);
    //     assertEq(diamond.getBids(asset)[0].ercAmount, 45000042958072527563221);
    //     s_handler.createLimitAskDiscounted(1208925819614629174706172, 309485009821345068724781052, 0);
    //     assertEq(diamond.getBids(asset).length, 1);
    //     assertEq(diamond.getBids(asset)[0].price, 239723247450413);
    //     assertEq(diamond.getBids(asset)[0].ercAmount, 24990221613003802789046);

    //     //Interesting.....so the bid was partially matched here.
    //     //But so was the ask and the short
    //     assertEq(diamond.getAsks(asset).length, 0);

    //     //This does match
    //     s_handler.createLimitBid(129802, 4826, 202);
    //     s_handler.createLimitShort(87350, 17270, 225);

    //     //The first bid was not further matched (s_handler.createLimitBidDiscounted(217223247450412, 42958072527563220, 0);)
    //     assertEq(diamond.getBids(asset).length, 1);
    //     assertEq(diamond.getBids(asset)[0].price, 239723247450413);
    //     assertEq(diamond.getBids(asset)[0].ercAmount, 24990221613003802789046);

    //     // @dev: At this point, assetErcDebtRate is still 0 because the discount had not been triggered yet.
    //     assertEq(assetErcDebtRate, 0);
    //     STypes.ShortRecord[] memory shorts = diamond.getShortRecords(asset, shorter);
    //     assertEq(shorts.length, 2); //One from the call above. One from inside createLimitAskDiscounted

    //     STypes.ShortRecord memory short1 = diamond.getShortRecords(asset, shorter)[0];
    //     STypes.ShortRecord memory short2 = diamond.getShortRecords(asset, shorter)[1];
    //     // Another sanity check. See if this changes after discount is applied
    //     assertEq(short1.ercDebt, 45000000000000000004827);
    //     assertEq(short1.ercDebtRate, 0);
    //     assertEq(short2.ercDebt, 20009821345068724774175);
    //     assertEq(short2.ercDebtRate, 0);

    //     // DISCOUNT TRIGGERED HERE
    //     assetErcDebtRate = diamond.getAssetStruct(asset).ercDebtRate;
    //     assertEq(assetErcDebtRate, 0);
    //     assertEq(diamond.getAsks(asset).length, 0);
    //     s_handler.createLimitAskDiscounted(12040, 5807, 74); //this matches with this (s_handler.createLimitBidDiscounted(217223247450412, 42958072527563220, 0);)
    //     //This bid (s_handler.createLimitBidDiscounted(217223247450412, 42958072527563220, 0)) was matched here
    //     assertEq(diamond.getBids(asset).length, 0);

    //     //The ask was not fully matched
    //     assertEq(diamond.getAsks(asset).length, 1);

    //     // DISCOUNT TRIGGERED HERE AGAIN
    //     s_handler.createLimitBidDiscounted(6583152, 21916, 191);
    //     assertEq(diamond.getBids(asset).length, 1);
    //     assertEq(diamond.getAsks(asset).length, 0);

    //     assetErcDebtRate = diamond.getAssetStruct(asset).ercDebtRate;
    //     assertEq(assetErcDebtRate, C.DISCOUNT_PENALTY_FEE * 2);

    //     //There's a new short from createLimitAskDiscounted
    //     shorts = diamond.getShortRecords(asset, shorter);
    //     assertEq(shorts.length, 3); //One from the call above. Two from the two createLimitAskDiscounted calls

    //     short1 = diamond.getShortRecords(asset, shorter)[1];
    //     short2 = diamond.getShortRecords(asset, shorter)[2];
    //     STypes.ShortRecord memory short3 = diamond.getShortRecords(asset, shorter)[0];
    //     // Another sanity check. See if this changes after discount is applied
    //     assertEq(short1.ercDebt, 45000000000000000004827);
    //     assertEq(short1.ercDebtRate, 0);
    //     assertEq(short2.ercDebt, 20009821345068724774175);
    //     assertEq(short2.ercDebtRate, 0);

    //     address[] memory users = s_handler.getUsers();
    //     assertEq(users[0], shorter); //sanity check

    //     IAsset assetContract = IAsset(asset);
    //     uint256 ercEscrowed;
    //     uint256 assetBalance;
    //     uint256 totalDebt;
    //     uint256 testDebt;
    //     STypes.Order[] memory asks = diamond.getAsks(asset);
    //     for (uint256 i = 0; i < asks.length; i++) {
    //         ercEscrowed += asks[i].ercAmount;
    //     }

    //     assertEq(users.length, 1);
    //     assertEq(diamond.getAssetStruct(asset).ercDebtRate, C.DISCOUNT_PENALTY_FEE * 2);

    //     for (uint256 i = 0; i < users.length; i++) {
    //         ercEscrowed += diamond.getAssetUserStruct(asset, users[i]).ercEscrowed;
    //         assetBalance += assetContract.balanceOf(users[i]);

    //         STypes.ShortRecord[] memory shorts = diamond.getShortRecords(asset, users[i]);

    //         assertEq(shorts.length, 3);
    //         for (uint256 j = 0; j < shorts.length; j++) {
    //             totalDebt += shorts[j].ercDebt;
    //             // Undistributed debt
    //             assertEq(shorts[j].ercDebtRate, 0);

    //             if (j == 0) {
    //                 assertEq(shorts[j].ercDebt, 45000000000000000005808);
    //             } else if (j == 1) {
    //                 assertEq(shorts[j].ercDebt, 45000000000000000004827);
    //             } else {
    //                 assertEq(shorts[j].ercDebt, 20009821345068724774175);
    //             }
    //             totalDebt += shorts[j].ercDebt.mulU88(diamond.getAssetStruct(asset).ercDebtRate - shorts[j].ercDebtRate);
    //             testDebt += shorts[j].ercDebt.mulU88(diamond.getAssetStruct(asset).ercDebtRate - shorts[j].ercDebtRate);
    //         }
    //     }

    //     ercEscrowed += diamond.getAssetUserStruct(asset, address(diamond)).ercEscrowed;
    //     totalDebt += diamond.getShortRecords(asset, address(diamond))[0].ercDebt;

    //     assertApproxEqAbs(ercEscrowed + assetBalance, totalDebt, s_ob.MAX_DELTA());
    //     // assertApproxEqAbs(diamond.getAssetStruct(asset).ercDebt, totalDebt, s_ob.MAX_DELTA());
    // }
}
