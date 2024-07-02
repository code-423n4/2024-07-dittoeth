// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {U256, U80, U88} from "contracts/libraries/PRBMathHelper.sol";
import {C} from "contracts/libraries/Constants.sol";
import {STypes, MTypes, O, SR} from "contracts/libraries/DataTypes.sol";

import {Test} from "forge-std/Test.sol";

import {IAsset} from "interfaces/IAsset.sol";
import {IOBFixture} from "interfaces/IOBFixture.sol";
import {IDiamond} from "interfaces/IDiamond.sol";
import {LibOrders} from "contracts/libraries/LibOrders.sol";
import {LibBytes} from "contracts/libraries/LibBytes.sol";
import {VAULT} from "contracts/libraries/Constants.sol";
import {Handler} from "./Handler.sol";

import {console} from "contracts/libraries/console.sol";

/* solhint-disable */
/// @dev This contract deploys the target contract, the Handler, adds the Handler's actions to the invariant fuzzing
/// @dev targets, then defines invariants that should always hold throughout any invariant run.
contract InvariantsBase is Test {
    using U256 for uint256;
    using U80 for uint80;
    using U88 for uint88;

    Handler internal s_handler;
    IDiamond public diamond;
    uint256 public vault;
    address public asset;
    address public deth;
    address public ditto;
    IOBFixture public s_ob;

    bytes4[] public selectors;

    // @dev Used for one test: statefulFuzz_allOrderIdsUnique
    mapping(uint16 id => uint256 cnt) orderIdMapping;

    function setUp() public virtual {
        IOBFixture ob = IOBFixture(deployCode("foundry/artifacts/OBFixture.sol/OBFixture.json"));
        ob.setUp();
        address _diamond = ob.contracts("diamond");
        asset = ob.contracts("dusd");
        deth = ob.contracts("deth");
        ditto = ob.contracts("ditto");
        diamond = IDiamond(payable(_diamond));
        vault = VAULT.ONE;

        s_ob = ob;
        s_handler = new Handler(ob);

        // @dev duplicate the selector to increase the distribution of certain handler calls
        selectors = [
            // Bridge
            Handler.deposit.selector,
            Handler.deposit.selector,
            Handler.deposit.selector,
            Handler.depositEth.selector,
            Handler.depositEth.selector,
            Handler.depositEth.selector,
            Handler.withdraw.selector,
            // OrderBook
            Handler.createLimitBidSmall.selector,
            Handler.createLimitBid.selector,
            Handler.createLimitBid.selector,
            Handler.createLimitAsk.selector,
            Handler.createLimitShortSmall.selector,
            Handler.createLimitShortSmall.selector,
            Handler.createLimitShort.selector,
            Handler.createLimitShort.selector,
            Handler.createLimitBidDiscounted.selector,
            Handler.createLimitAskDiscounted.selector,
            Handler.cancelOrder.selector,
            // Yield
            Handler.fakeYield.selector,
            Handler.distributeYieldAll.selector,
            // Vault
            Handler.depositAsset.selector,
            Handler.withdrawAsset.selector,
            // Short
            Handler.proposeRedemption.selector,
            Handler.proposeRedemption.selector,
            Handler.disputeRedemption.selector,
            Handler.claimRedemption.selector,
            Handler.claimRemainingCollateral.selector,
            Handler.secondaryLiquidation.selector,
            Handler.primaryLiquidation.selector,
            Handler.exitShort.selector,
            Handler.increaseCollateral.selector,
            Handler.decreaseCollateral.selector,
            Handler.combineShorts.selector
        ];
    }

    function boundTest() public view {
        address[] memory users = s_handler.getUsers();
        for (uint256 i = 0; i < users.length; i++) {
            assertTrue(uint160(users[i]) <= type(uint160).max);
        }
    }

    function sortedBidsHighestToLowest() public view {
        if (diamond.getBids(asset).length > 1) {
            STypes.Order memory firstBid = diamond.getBids(asset)[0];
            STypes.Order memory lastBid = diamond.getBids(asset)[diamond.getBids(asset).length - 1];

            STypes.Order memory prevBid = firstBid;
            STypes.Order memory currentBid;

            for (uint256 i = 0; i < diamond.getBids(asset).length; i++) {
                currentBid = diamond.getBids(asset)[i];
                assertTrue(currentBid.orderType == O.LimitBid, "statefulFuzz_sortedBidsHighestToLowest_1");
                if (i == 0) {
                    assertEq(currentBid.prevId, C.HEAD, "statefulFuzz_sortedBidsHighestToLowest_2");
                } else {
                    assertEq(currentBid.prevId, prevBid.id, "statefulFuzz_sortedBidsHighestToLowest_2");
                }
                if (i == 0) {
                    assertEq(diamond.getBidOrder(asset, C.HEAD).nextId, currentBid.id, "statefulFuzz_sortedBidsHighestToLowest_3");
                } else {
                    assertEq(prevBid.nextId, currentBid.id, "statefulFuzz_sortedBidsHighestToLowest_3");
                }
                assertTrue(prevBid.price >= currentBid.price, "statefulFuzz_sortedBidsHighestToLowest_4");
                prevBid = diamond.getBids(asset)[i];
            }
            assertEq(firstBid.prevId, C.HEAD, "statefulFuzz_sortedBidsHighestToLowest_5");
            assertEq(lastBid.nextId, C.HEAD, "statefulFuzz_sortedBidsHighestToLowest_6");
        }
    }

    function sortedAsksLowestToHighest() public view {
        if (diamond.getAsks(asset).length > 1) {
            STypes.Order memory firstAsk = diamond.getAsks(asset)[0];
            STypes.Order memory lastAsk = diamond.getAsks(asset)[diamond.getAsks(asset).length - 1];

            STypes.Order memory prevAsk = firstAsk;
            STypes.Order memory currentAsk;

            for (uint256 i = 0; i < diamond.getAsks(asset).length; i++) {
                currentAsk = diamond.getAsks(asset)[i];
                assertTrue(currentAsk.orderType == O.LimitAsk, "statefulFuzz_sortedAsksLowestToHighest_1");
                if (i == 0) {
                    assertEq(currentAsk.prevId, C.HEAD, "statefulFuzz_sortedAsksLowestToHighest_2");
                } else {
                    assertEq(currentAsk.prevId, prevAsk.id, "statefulFuzz_sortedAsksLowestToHighest_2");
                }
                if (i == 0) {
                    assertEq(diamond.getAskOrder(asset, C.HEAD).nextId, currentAsk.id, "statefulFuzz_sortedAsksLowestToHighest_3");
                } else {
                    assertEq(prevAsk.nextId, currentAsk.id, "statefulFuzz_sortedAsksLowestToHighest_3");
                }
                assertTrue(prevAsk.price <= currentAsk.price, "statefulFuzz_sortedAsksLowestToHighest_4");
                prevAsk = diamond.getAsks(asset)[i];
            }
            assertEq(firstAsk.prevId, C.HEAD, "statefulFuzz_sortedAsksLowestToHighest_5");
            assertEq(lastAsk.nextId, C.HEAD, "statefulFuzz_sortedAsksLowestToHighest_6");
        }
    }

    function sortedShortsLowestToHighest() public view {
        if (diamond.getShorts(asset).length > 1) {
            STypes.Order memory firstShort = diamond.getShorts(asset)[0];
            STypes.Order memory lastShort = diamond.getShorts(asset)[diamond.getShorts(asset).length - 1];

            STypes.Order memory prevShort = diamond.getShorts(asset)[0];
            STypes.Order memory currentShort;

            for (uint256 i = 0; i < diamond.getShorts(asset).length; i++) {
                currentShort = diamond.getShorts(asset)[i];

                assertTrue(currentShort.orderType == O.LimitShort, "statefulFuzz_sortedShortsLowestToHighest_1");
                if (i == 0) {
                    assertEq(currentShort.prevId, C.HEAD, "statefulFuzz_sortedShortsLowestToHighest_2");
                } else {
                    assertEq(currentShort.prevId, prevShort.id, "statefulFuzz_sortedShortsLowestToHighest_2");
                }
                if (i == 0) {
                    assertEq(
                        diamond.getShortOrder(asset, C.HEAD).nextId, currentShort.id, "statefulFuzz_sortedShortsLowestToHighest_3"
                    );
                } else {
                    assertEq(prevShort.nextId, currentShort.id, "statefulFuzz_sortedShortsLowestToHighest_3");
                }
                assertTrue(prevShort.price <= currentShort.price, "statefulFuzz_sortedShortsLowestToHighest_4");
                prevShort = diamond.getShorts(asset)[i];
            }

            assertEq(firstShort.prevId, C.HEAD, "statefulFuzz_sortedShortsLowestToHighest_5");
            assertEq(lastShort.nextId, C.HEAD, "statefulFuzz_sortedShortsLowestToHighest_6");
        }
    }

    function bidHead() public view {
        STypes.Order memory bidHEAD = diamond.getBidOrder(asset, C.HEAD);
        STypes.Order memory bidPrevHEAD = diamond.getBidOrder(asset, bidHEAD.prevId);

        while (bidPrevHEAD.id != C.HEAD) {
            assertTrue(bidPrevHEAD.orderType == O.Cancelled || bidPrevHEAD.orderType == O.Matched, "statefulFuzz_bidHEAD_1");

            if (bidPrevHEAD.prevId != C.HEAD) {
                assertTrue(
                    bidPrevHEAD.prevOrderType == O.Cancelled || bidPrevHEAD.prevOrderType == O.Matched
                        || bidPrevHEAD.prevOrderType == O.Uninitialized,
                    "statefulFuzz_bidHEAD_2"
                );
            }
            bidPrevHEAD = diamond.getBidOrder(asset, bidPrevHEAD.prevId);
        }

        if (diamond.getBids(asset).length > 0) {
            assertTrue(bidHEAD.nextId != C.HEAD, "statefulFuzz_bidHEAD_3");
        } else {
            assertEq(bidHEAD.nextId, C.HEAD, "statefulFuzz_bidHEAD_4");
        }
    }

    function askHead() public view {
        STypes.Order memory askHEAD = diamond.getAskOrder(asset, C.HEAD);
        STypes.Order memory askPrevHEAD = diamond.getAskOrder(asset, askHEAD.prevId);

        while (askPrevHEAD.id != C.HEAD) {
            assertTrue(askPrevHEAD.orderType == O.Cancelled || askPrevHEAD.orderType == O.Matched, "statefulFuzz_askHEAD_1");

            if (askPrevHEAD.prevId != C.HEAD) {
                assertTrue(
                    askPrevHEAD.prevOrderType == O.Cancelled || askPrevHEAD.prevOrderType == O.Matched
                        || askPrevHEAD.prevOrderType == O.Uninitialized,
                    "statefulFuzz_askHEAD_2"
                );
            }
            askPrevHEAD = diamond.getAskOrder(asset, askPrevHEAD.prevId);
        }

        if (diamond.getAsks(asset).length > 0) {
            assertTrue(askHEAD.nextId != C.HEAD, "statefulFuzz_askHEAD_3");
        } else {
            assertEq(askHEAD.nextId, C.HEAD, "statefulFuzz_askHEAD_4");
        }
    }

    function shortHead() public view {
        STypes.Order memory shortHEAD = diamond.getShortOrder(asset, C.HEAD);
        STypes.Order memory shortPrevHEAD = diamond.getShortOrder(asset, shortHEAD.prevId);

        while (shortPrevHEAD.id != C.HEAD) {
            assertTrue(shortPrevHEAD.orderType == O.Cancelled || shortPrevHEAD.orderType == O.Matched, "statefulFuzz_shortHEAD_1");

            if (shortPrevHEAD.prevId != C.HEAD) {
                assertTrue(
                    shortPrevHEAD.prevOrderType == O.Cancelled || shortPrevHEAD.prevOrderType == O.Matched
                        || shortPrevHEAD.prevOrderType == O.Uninitialized,
                    "statefulFuzz_shortHEAD_2"
                );
            }
            shortPrevHEAD = diamond.getShortOrder(asset, shortPrevHEAD.prevId);
        }

        if (diamond.getShorts(asset).length > 0) {
            assertTrue(shortHEAD.nextId != C.HEAD, "statefulFuzz_shortHEAD_3");
        } else {
            assertEq(shortHEAD.nextId, C.HEAD, "statefulFuzz_shortHEAD_4");
        }
    }

    function orderIdGtMarketDepth() public view {
        uint256 marketDepth = diamond.getBids(asset).length + diamond.getAsks(asset).length + diamond.getShorts(asset).length;

        assertTrue(diamond.getAssetNormalizedStruct(asset).orderId > marketDepth, "statefulFuzz_orderIdGtMarketDepth_1");
        assertGe(diamond.getAssetNormalizedStruct(asset).orderId, s_handler.ghost_orderId(), "statefulFuzz_orderIdGtMarketDepth_2");
    }

    function oracleTimeAlwaysIncrease() public view {
        assertEq(s_handler.ghost_checkOracleTime(), 0, "statefulFuzz_oracleTimeAlwaysIncrease");
    }

    function startingShortPriceGteOraclePrice() public view {
        uint16 startingShortId = diamond.getAssetNormalizedStruct(asset).startingShortId;
        STypes.Order memory startingShort = diamond.getShortOrder(asset, startingShortId);
        if (startingShortId > C.HEAD) {
            assertGe(startingShort.price, s_handler.ghost_oraclePrice(), "statefulFuzz_startingShortPriceGteOraclePrice_1");
        }
    }

    function allOrderIdsUnique() public {
        // @dev Unmatched Bids, Asks, Shorts
        uint256 marketDepth = diamond.getBids(asset).length + diamond.getAsks(asset).length + diamond.getShorts(asset).length;

        // @dev Cancelled/Matched Bids, Asks, Shorts
        STypes.Order memory bidHEAD = diamond.getBidOrder(asset, C.HEAD);
        STypes.Order memory bidPrevHEAD = diamond.getBidOrder(asset, bidHEAD.prevId);
        STypes.Order memory askHEAD = diamond.getAskOrder(asset, C.HEAD);
        STypes.Order memory askPrevHEAD = diamond.getAskOrder(asset, askHEAD.prevId);
        STypes.Order memory shortHEAD = diamond.getShortOrder(asset, C.HEAD);
        STypes.Order memory shortPrevHEAD = diamond.getShortOrder(asset, shortHEAD.prevId);

        uint256 counter = 0;
        while (bidPrevHEAD.id != C.HEAD) {
            counter++;
            bidPrevHEAD = diamond.getBidOrder(asset, bidPrevHEAD.prevId);
        }
        while (askPrevHEAD.id != C.HEAD) {
            counter++;
            askPrevHEAD = diamond.getAskOrder(asset, askPrevHEAD.prevId);
        }
        while (shortPrevHEAD.id != C.HEAD) {
            counter++;
            shortPrevHEAD = diamond.getShortOrder(asset, shortPrevHEAD.prevId);
        }
        marketDepth += counter;

        uint16[] memory allOrderIds = new uint16[](marketDepth);

        // @dev Reuse counter to use as index
        counter = 0;
        // @dev Add all orders in OB to allOrdersId
        if (diamond.getBids(asset).length > 0) {
            for (uint256 i = 0; i < diamond.getBids(asset).length; i++) {
                allOrderIds[counter] = diamond.getBids(asset)[i].id;
                counter++;
            }
        }
        if (diamond.getAsks(asset).length > 0) {
            for (uint256 i = 0; i < diamond.getAsks(asset).length; i++) {
                allOrderIds[counter] = diamond.getAsks(asset)[i].id;
                counter++;
            }
        }
        if (diamond.getShorts(asset).length > 0) {
            for (uint256 i = 0; i < diamond.getShorts(asset).length; i++) {
                allOrderIds[counter] = diamond.getShorts(asset)[i].id;
                counter++;
            }
        }

        // @dev Add all cancelled/Matched ids to allOrdersId
        bidPrevHEAD = diamond.getBidOrder(asset, bidHEAD.prevId);
        askPrevHEAD = diamond.getAskOrder(asset, askHEAD.prevId);
        shortPrevHEAD = diamond.getShortOrder(asset, shortHEAD.prevId);

        while (bidPrevHEAD.id != C.HEAD) {
            allOrderIds[counter] = bidPrevHEAD.id;
            bidPrevHEAD = diamond.getBidOrder(asset, bidPrevHEAD.prevId);
            counter++;
        }
        while (askPrevHEAD.id != C.HEAD) {
            allOrderIds[counter] = askPrevHEAD.id;
            askPrevHEAD = diamond.getAskOrder(asset, askPrevHEAD.prevId);
            counter++;
        }

        while (shortPrevHEAD.id != C.HEAD) {
            allOrderIds[counter] = shortPrevHEAD.id;
            shortPrevHEAD = diamond.getShortOrder(asset, shortPrevHEAD.prevId);
            counter++;
        }

        assertEq(marketDepth + C.STARTING_ID, diamond.getAssetNormalizedStruct(asset).orderId);

        for (uint256 i = 0; i < allOrderIds.length; i++) {
            uint16 orderId = allOrderIds[i];
            orderIdMapping[orderId]++;
            if (orderIdMapping[orderId] > 1) {
                revert("Order Id is not unique");
            }
        }
    }

    function shortRecordExists() public view {
        address[] memory users = s_handler.getUsers();

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            STypes.ShortRecord[] memory shortRecords = diamond.getShortRecords(asset, user);
            STypes.ShortRecord memory shortRecordHEAD = diamond.getShortRecord(asset, user, C.HEAD);

            if (diamond.getAssetUserStruct(asset, user).shortRecordCounter == 0) {
                assertEq(shortRecordHEAD.prevId, 0, "statefulFuzz_shortRecordExists_1");
            } else {
                // @dev check all cancelled shorts are indeed canceled
                while (shortRecordHEAD.prevId != C.HEAD) {
                    STypes.ShortRecord memory shortRecordPrevHEAD = diamond.getShortRecord(asset, user, shortRecordHEAD.prevId);
                    assertTrue(shortRecordPrevHEAD.status == SR.Closed, "statefulFuzz_shortRecordExists_2");
                    shortRecordHEAD = diamond.getShortRecord(asset, user, shortRecordHEAD.prevId);
                }
            }

            if (shortRecords.length > 0) {
                // @dev check that all active shortRecords are either full or partial;
                for (uint256 j = 0; j < shortRecords.length; j++) {
                    assertTrue(
                        shortRecords[j].status == SR.PartialFill || shortRecords[j].status == SR.FullyFilled,
                        "statefulFuzz_shortRecordExists_3"
                    );
                }

                // @dev check that all short orders with shortRecordId > 0 is a partial fill
                STypes.Order[] memory shortOrders = diamond.getShorts(asset);

                for (uint256 k = 0; k < shortOrders.length; k++) {
                    if (shortOrders[k].addr == user && shortOrders[k].shortRecordId > 0) {
                        assertTrue(
                            diamond.getShortRecord(asset, user, shortOrders[k].shortRecordId).status != SR.FullyFilled,
                            "statefulFuzz_shortRecordExists_4"
                        );
                    }
                }
            }
        }
    }

    // @dev Vault dethTotal = sum of users ethEscrowed
    function vault_DethTotal() public view {
        IAsset tokenContract = IAsset(deth);
        uint256 dethTotal = diamond.getVaultStruct(vault).dethTotal;
        assertGe(diamond.getDethTotal(vault), dethTotal, "statefulFuzz_Vault_DethTotal_1");

        address[] memory users = s_handler.getUsers();

        // @dev Collateral of matched shorts
        uint256 userDethTotal;
        uint256 dethCollateralTotal;
        for (uint256 i = 0; i < users.length; i++) {
            // @dev wallet balance for deth
            userDethTotal += tokenContract.balanceOf(users[i]);

            STypes.ShortRecord[] memory shorts = diamond.getShortRecords(asset, users[i]);
            for (uint256 j = 0; j < shorts.length; j++) {
                // Collateral in shortRecord
                dethCollateralTotal += shorts[j].collateral;
                // Undistributed yield
                userDethTotal += shorts[j].collateral.mulU88(diamond.getDethYieldRate(vault) - shorts[j].dethYieldRate);
            }
        }

        STypes.ShortRecord memory tappSR = diamond.getShortRecords(asset, address(diamond))[0];
        // Add collateral from TAPP SR
        dethCollateralTotal += tappSR.collateral;
        // Add unrealized yield from TAPP SR
        userDethTotal += tappSR.collateral.mulU88(diamond.getDethYieldRate(vault) - tappSR.dethYieldRate);

        assertEq(diamond.getVaultStruct(vault).dethCollateral, dethCollateralTotal, "statefulFuzz_Vault_DethTotal_2");
        assertEq(diamond.getAssetStruct(asset).dethCollateral, dethCollateralTotal, "statefulFuzz_Vault_DethTotal_3");

        // @dev ...and eth locked up on bid on ob...
        for (uint256 i = 0; i < diamond.getBids(asset).length; i++) {
            uint256 eth = diamond.getBids(asset)[i].price.mul(diamond.getBids(asset)[i].ercAmount);
            userDethTotal += eth;
        }

        // @dev ...and collateral locked up on short on ob...
        for (uint256 i = 0; i < diamond.getShorts(asset).length; i++) {
            uint256 collateral = diamond.getShorts(asset)[i].price.mul(diamond.getShorts(asset)[i].ercAmount).mul(
                LibOrders.convertCR(diamond.getShorts(asset)[i].shortOrderCR)
            );
            userDethTotal += collateral;
        }

        // @dev ...and ethEscrowed of a user...
        for (uint256 i = 0; i < users.length; i++) {
            userDethTotal += diamond.getVaultUserStruct(vault, users[i]).ethEscrowed;
        }

        // @dev ...and ethEscrowed of Tapp...
        userDethTotal += diamond.getVaultUserStruct(vault, address(diamond)).ethEscrowed;
        // @dev ...and dethCollateral from matched shortRecords...
        userDethTotal += dethCollateralTotal;

        // @dev ...and eth set aside for redemptions
        address[] memory redeemers = s_handler.getRedeemers();
        for (uint256 i = 0; i < redeemers.length; i++) {
            MTypes.ProposalData[] memory decodedProposalData;
            (,,,, decodedProposalData) = LibBytes.readProposalData(
                diamond.getAssetUserStruct(asset, redeemers[i]).SSTORE2Pointer,
                diamond.getAssetUserStruct(asset, redeemers[i]).slateLength
            );

            for (uint256 j = 0; j < decodedProposalData.length; j++) {
                userDethTotal += decodedProposalData[j].colRedeemed;
            }
        }

        // @dev it is not perfectly equal due to rounding error
        assertApproxEqAbs(dethTotal, userDethTotal, s_ob.MAX_DELTA_LARGE(), "statefulFuzz_Vault_DethTotal_4");
    }

    // @dev Vault dittoMatchedShares = sum of users dittoMatchedShares
    function dittoMatchedShares() public view {
        uint256 vaultShares = diamond.getVaultStruct(vault).dittoMatchedShares;
        uint256 totalUserShares;
        address[] memory users = s_handler.getUsers();
        for (uint256 i = 0; i < users.length; i++) {
            totalUserShares += diamond.getVaultUserStruct(vault, users[i]).dittoMatchedShares;
        }
        assertEq(vaultShares, totalUserShares, "statefulFuzz_dittoMatchedShares_1");
    }

    // Only valid when claimDittoMatchedReward is NOT called
    function dittoShorterReward() public view {
        uint256 dittoShorterRewardAvail = (s_handler.ghost_protocolTime() + 1).mul(diamond.dittoShorterRate(vault));

        uint256 dittoShorterRewards;
        address[] memory users = s_handler.getUsers();
        for (uint256 i = 0; i < users.length; i++) {
            dittoShorterRewards += diamond.getVaultUserStruct(vault, users[i]).dittoReward;
        }

        assertGe(dittoShorterRewardAvail, dittoShorterRewards, "statefulFuzz_dittoShorterReward_1");
    }

    // @dev Less restrictive than dittoShorterReward()
    function dittoReward() public view {
        uint256 dittoShorterRewardAvail = (s_handler.ghost_protocolTime() + 1).mul(diamond.dittoShorterRate(vault));
        uint256 dittoMatchedRewardAvail = (s_handler.ghost_protocolTime() + 1).mul(diamond.dittoMatchedRate(vault));
        uint256 dittoRewardAvail = dittoShorterRewardAvail + dittoMatchedRewardAvail;

        IAsset tokenContract = IAsset(ditto);
        uint256 dittoRewardUsers;
        address[] memory users = s_handler.getUsers();
        for (uint256 i = 0; i < users.length; i++) {
            dittoRewardUsers += diamond.getVaultUserStruct(vault, users[i]).dittoReward;
            dittoRewardUsers += tokenContract.balanceOf(users[i]);
        }

        assertGe(dittoRewardAvail, dittoRewardUsers, "statefulFuzz_dittoReward_1");
    }

    // @dev Cannot used fundLimitOrders because it will mint assets without going through orderbook
    function vault_ErcEscrowedPlusAssetBalanceEqTotalDebt() public view {
        address[] memory users = s_handler.getUsers();

        IAsset assetContract = IAsset(asset);
        uint256 ercEscrowed;
        uint256 assetBalance;
        uint256 totalDebt;

        console.log("--Open ASKS--");
        STypes.Order[] memory asks = diamond.getAsks(asset);
        for (uint256 i = 0; i < asks.length; i++) {
            ercEscrowed += asks[i].ercAmount;
            console.logErcDebt(asks[i].addr, asks[i].ercAmount);
        }

        console.log("--Users--");
        console.log("User: yDUSD Vault");
        uint256 _balance = assetContract.balanceOf(s_ob.contracts("yDUSD"));
        assetBalance += _balance;
        for (uint256 i = 0; i < users.length; i++) {
            uint256 _escrowed = diamond.getAssetUserStruct(asset, users[i]).ercEscrowed;
            ercEscrowed += _escrowed;
            _balance = assetContract.balanceOf(users[i]);
            assetBalance += _balance;
            console.log("--DUSD--");
            console.logErcDebt(users[i], _escrowed + _balance);

            STypes.ShortRecord[] memory shorts = diamond.getShortRecords(asset, users[i]);
            console.log("--SR--");
            for (uint256 j = 0; j < shorts.length; j++) {
                uint88 _debt = shorts[j].ercDebt;
                totalDebt += _debt;
                // Undistributed debt
                uint256 _unDebt =
                    (_debt - shorts[j].ercDebtFee).mulU88(diamond.getAssetStruct(asset).ercDebtRate - shorts[j].ercDebtRate);
                totalDebt += _unDebt;
                console.logErcDebt(users[i], _debt + _unDebt);
            }
        }

        console.log("--TAPP DUSD--");
        // Add ercDebt from TAPP ercEscrowed and TAPP SR
        ercEscrowed += diamond.getAssetUserStruct(asset, address(diamond)).ercEscrowed;
        totalDebt += diamond.getShortRecords(asset, address(diamond))[0].ercDebt;
        console.logErcDebt(address(diamond), diamond.getAssetUserStruct(asset, address(diamond)).ercEscrowed);

        console.log("--Total--");
        console.log(string.concat("ercEscrowed: ", console.weiToEther(ercEscrowed)));
        console.log(string.concat("assetBalance: ", console.weiToEther(assetBalance)));
        console.log(string.concat("totalDebt: ", console.weiToEther(totalDebt)));

        assertApproxEqAbs(ercEscrowed + assetBalance, totalDebt, s_ob.MAX_DELTA_MEDIUM());
        assertApproxEqAbs(diamond.getAssetStruct(asset).ercDebt, totalDebt, s_ob.MAX_DELTA_MEDIUM());
    }

    function dethCollateralRewardAlwaysIncrease() public view {
        assertGe(diamond.getVaultStruct(vault).dethCollateralReward, s_handler.ghost_dethCollateralReward());
    }

    function dethYieldRateAlwaysIncrease() public view {
        assertGe(diamond.getVaultStruct(vault).dethYieldRate, s_handler.ghost_dethYieldRate());
    }

    // function statefulFuzz_Short_BlankReturnCounter() public {
    //     // vm.writeLine(
    //     //     "./test/invariants/inputs",
    //     //     string.concat(
    //     //         "ghost_secondaryLiquidation: ", vm.toString(s_handler.ghost_secondaryLiquidation())
    //     //     )
    //     // );

    //     // vm.writeLine(
    //     //     "./test/invariants/inputs",
    //     //     string.concat(
    //     //         "ghost_secondaryLiquidationSameUserCounter: ",
    //     //         vm.toString(s_handler.ghost_secondaryLiquidationSameUserCounter())
    //     //     )
    //     // );

    //     // vm.writeLine(
    //     //     "./test/invariants/inputs",
    //     //     string.concat(
    //     //         "ghost_secondaryLiquidationCancelledShortCounter: ",
    //     //         vm.toString(s_handler.ghost_secondaryLiquidationCancelledShortCounter())
    //     //     )
    //     // );

    //     // vm.writeLine(
    //     //     "./test/invariants/inputs",
    //     //     string.concat(
    //     //         "ghost_secondaryLiquidationComplete: ",
    //     //         vm.toString(s_handler.ghost_secondaryLiquidationComplete())
    //     //     )
    //     // );

    //     ////
    //     vm.writeLine(
    //         "./test/invariants/inputs",
    //         string.concat("ghost_primaryLiquidation: ", vm.toString(s_handler.ghost_primaryLiquidation()))
    //     );

    //     vm.writeLine(
    //         "./test/invariants/inputs",
    //         string.concat(
    //             "ghost_primaryLiquidationSameUserCounter: ",
    //             vm.toString(s_handler.ghost_primaryLiquidationSameUserCounter())
    //         )
    //     );

    //     vm.writeLine(
    //         "./test/invariants/inputs",
    //         string.concat(
    //             "ghost_primaryLiquidationCancelledShortCounter: ",
    //             vm.toString(s_handler.ghost_primaryLiquidationCancelledShortCounter())
    //         )
    //     );

    //     vm.writeLine(
    //         "./test/invariants/inputs",
    //         string.concat(
    //             "ghost_primaryLiquidationComplete: ",
    //             vm.toString(s_handler.ghost_primaryLiquidationComplete())
    //         )
    //     );
    // }

    // @dev assumes no price changes in the invariant tests
    // function statefulFuzz_shortRecordCRatioAlwaysAbove1() public {
    //     address[] memory users = s_handler.getUsers();
    //     for (uint256 i = 0; i < users.length; i++) {
    //         STypes.ShortRecord[] memory shorts = diamond.getShortRecords(asset, users[i]);
    //         if (shorts.length > 0) {
    //             for (uint256 j = 0; j < shorts.length; j++) {
    //                 uint256 cRatio = diamond.getCollateralRatio(asset, shorts[j]);
    //                 assertGt(
    //                     cRatio, 1 ether, "statefulFuzz_shortRecordCRatioAlwaysAbove1_1"
    //                 );
    //             }
    //         }
    //     }
    // }

    function shortRecordCounterLtShortMaxId() public view {
        address[] memory users = s_handler.getUsers();

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];

            // vm.writeLine(
            //     "./test/invariants/inputs",
            //     string.concat(
            //         "test:",
            //         vm.toString(
            //             diamond.getAssetUserStruct(asset, user).shortRecordCounter
            //         ),
            //         "test:",
            //         vm.toString(C.SHORT_MAX_ID)
            //     )
            // );

            assertLt(diamond.getAssetUserStruct(asset, user).shortRecordCounter, C.SHORT_MAX_ID);
        }
    }

    function titheBetween10And100() public view {
        uint16 dethTithePercent = diamond.getVaultStruct(vault).dethTithePercent;
        assertTrue(dethTithePercent >= 10_00 && dethTithePercent <= 100_00);
    }

    function shortRecordDebtUnderMinShortErc() public view {
        address[] memory users = s_handler.getUsers();
        uint256 minShortErc = diamond.getMinShortErc(asset);

        for (uint256 i = 0; i < users.length; i++) {
            address user = users[i];
            STypes.ShortRecord[] memory shortRecords = diamond.getShortRecords(asset, user);

            if (shortRecords.length > 0) {
                for (uint256 j = 0; j < shortRecords.length; j++) {
                    STypes.ShortRecord memory shortRecord = shortRecords[j];
                    // @dev check that all shorts under minShortErc is partialFill
                    if (shortRecord.ercDebt > 0 && shortRecord.ercDebt < minShortErc) {
                        // vm.writeLine(
                        //     "./test/invariants/inputs",
                        //     string.concat(
                        //         "id: ",
                        //         vm.toString(shortRecord.id),
                        //         " | ",
                        //         "ercDebt: ",
                        //         vm.toString(shortRecord.ercDebt),
                        //         " | ",
                        //         "minShortErc: ",
                        //         vm.toString(minShortErc)
                        //     )
                        // );

                        assertTrue(shortRecord.status == SR.PartialFill, "statefulFuzz_SRDebtUnderMin_1");

                        //get all the short orders
                        STypes.Order memory shortOrder;
                        for (uint256 k = 0; k < diamond.getShorts(asset).length; k++) {
                            shortOrder = diamond.getShorts(asset)[k];
                            // @dev check that all shorts under minShortErc has a corresponding shortOrder on ob;
                            if (shortOrder.shortRecordId == shortRecord.id && shortOrder.addr == user) {
                                // vm.writeLine(
                                //     "./test/invariants/inputs",
                                //     string.concat("shortOrder.shortRecordId == shortRecord.id", vm.toString(shortRecord.id))
                                // );
                                break;
                            }
                        }

                        assertEq(shortOrder.shortRecordId, shortRecord.id, "statefulFuzz_SRDebtUnderMin_2");
                        assertEq(shortOrder.addr, user, "statefulFuzz_SRDebtUnderMin_3");
                        assertGe(shortRecord.ercDebt + shortOrder.ercAmount, minShortErc, "statefulFuzz_SRDebtUnderMin_4");
                    }
                }
            }
        }
    }

    function minEth() public view {
        STypes.Order memory order;
        uint256 minBidEth = diamond.getAssetNormalizedStruct(asset).minBidEth;
        uint256 minBidEthDust = minBidEth.mul(C.DUST_FACTOR);
        uint256 minAskEth = diamond.getAssetNormalizedStruct(asset).minAskEth;
        uint256 minAskEthDust = minAskEth.mul(C.DUST_FACTOR);

        STypes.Order[] memory bids = diamond.getBids(asset);
        STypes.Order[] memory asks = diamond.getAsks(asset);
        STypes.Order[] memory shorts = diamond.getShorts(asset);

        for (uint16 i = 0; i < bids.length; i++) {
            order = bids[i];
            uint256 eth = order.ercAmount.mul(order.price);
            assertGe(eth, minBidEthDust, "statefulFuzz_minEth_1");
        }

        for (uint16 i = 0; i < asks.length; i++) {
            order = asks[i];
            uint256 eth = order.ercAmount.mul(order.price);
            assertGe(eth, minAskEthDust, "statefulFuzz_minEth_2");
        }

        for (uint16 i = 0; i < shorts.length; i++) {
            order = shorts[i];
            uint256 eth = order.ercAmount.mul(order.price);
            assertGe(eth, minAskEthDust, "statefulFuzz_minEth_3");
        }
    }
}
