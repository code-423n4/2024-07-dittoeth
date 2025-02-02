// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {U256, U88, U80} from "contracts/libraries/PRBMathHelper.sol";
import {Errors} from "contracts/libraries/Errors.sol";
import {OBFixture} from "test/utils/OBFixture.sol";
import {MTypes, O} from "contracts/libraries/DataTypes.sol";
import {C} from "contracts/libraries/Constants.sol";

// import {console} from "contracts/libraries/console.sol";

contract ShortHintIdTest is OBFixture {
    using U256 for uint256;
    using U88 for uint88;
    using U80 for uint80;

    function setUp() public override {
        super.setUp();
    }

    function makeShorts() public {
        fundLimitShortOpt(DEFAULT_PRICE - 1 wei, DEFAULT_AMOUNT, sender); //100
        fundLimitShortOpt(DEFAULT_PRICE + 0.0000065 ether, DEFAULT_AMOUNT, sender); //101
        fundLimitShortOpt(DEFAULT_PRICE + 0.00000655 ether, DEFAULT_AMOUNT, sender); //102
        fundLimitShortOpt(DEFAULT_PRICE + 0.00000655 ether, DEFAULT_AMOUNT, sender); //103
        fundLimitShortOpt(DEFAULT_PRICE + 0.0000066 ether, DEFAULT_AMOUNT, sender); //104
        fundLimitShortOpt(DEFAULT_PRICE * 2, DEFAULT_AMOUNT, sender); //105
        skip(1 hours);
        ethAggregator.setRoundData(
            92233720368547778907 wei,
            3900 ether / C.BASE_ORACLE_DECIMALS,
            block.timestamp,
            block.timestamp,
            92233720368547778907 wei
        );
    }

    //Testing adding shorts to market
    function test_IncomingShortPriceLtStartingShortPriceAndOraclePrice() public {
        makeShorts();
        assertEq(diamond.getAssetStruct(asset).startingShortId, 101);

        fundLimitShortOpt(DEFAULT_PRICE - 1 wei, DEFAULT_AMOUNT, sender);
        assertEq(diamond.getAssetStruct(asset).startingShortId, 101);
    }

    function test_IncomingShortPriceLtStartingShortPriceAndGtOrEqualOraclePrice() public {
        fundLimitShortOpt(DEFAULT_PRICE + 0.00000655 ether, DEFAULT_AMOUNT, sender); //100
        fundLimitShortOpt(DEFAULT_PRICE - 1 wei, DEFAULT_AMOUNT, sender); //101
        fundLimitShortOpt(DEFAULT_PRICE + 0.00000655 ether, DEFAULT_AMOUNT, sender); //102

        assertEq(diamond.getAssetStruct(asset).startingShortId, 100);

        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);
        assertEq(diamond.getAssetStruct(asset).startingShortId, 103);
    }

    function test_IncomingShortPriceGtOrEqualStartingShortPriceAndLtOraclePrice() public {
        fundLimitShortOpt(DEFAULT_PRICE - 2 wei, DEFAULT_AMOUNT, sender); //100
        fundLimitShortOpt(DEFAULT_PRICE - 2 wei, DEFAULT_AMOUNT, sender); //101
        fundLimitShortOpt(DEFAULT_PRICE - 2 wei, DEFAULT_AMOUNT, sender); //102

        assertEq(diamond.getAssetStruct(asset).startingShortId, 1);

        fundLimitShortOpt(DEFAULT_PRICE - 1 wei, DEFAULT_AMOUNT, sender);
        assertEq(diamond.getAssetStruct(asset).startingShortId, 1);
    }

    function test_IncomingShortPriceGtOrEqualStartingShortPriceAndGtOrEqualOraclePrice() public {
        makeShorts();
        assertEq(diamond.getAssetStruct(asset).startingShortId, 101);

        fundLimitShortOpt(DEFAULT_PRICE + 0.00000655 ether, DEFAULT_AMOUNT, sender);
        assertEq(diamond.getAssetStruct(asset).startingShortId, 101);
    }

    function test_CreateIncomingShortWhenShortOrdersIsEmpty1() public {
        assertEq(getShorts().length, 0);

        // @dev Shorts under oracle price should not become startingShortId
        fundLimitShortOpt(DEFAULT_PRICE - 1 wei, DEFAULT_AMOUNT, sender);
        assertEq(diamond.getAssetStruct(asset).startingShortId, 1);

        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);
        assertEq(diamond.getAssetStruct(asset).startingShortId, 101);
    }

    function test_CreateIncomingShortWhenShortOrdersIsEmpty2() public {
        assertEq(getShorts().length, 0);

        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);
        assertEq(diamond.getAssetStruct(asset).startingShortId, 100);
    }

    //Creating Shorts and Matching Bids
    function test_UpdateStartingShortIdAfterMatchFull() public {
        makeShorts();
        assertEq(diamond.getAssetStruct(asset).startingShortId, 101);

        fundLimitBidOpt(DEFAULT_PRICE + 0.0000065 ether, DEFAULT_AMOUNT, receiver);
        assertEq(diamond.getAssetStruct(asset).startingShortId, 102);
    }

    function test_UpdateStartingShortIdAfterMatchDustAmount() public {
        makeShorts();
        assertEq(diamond.getAssetStruct(asset).startingShortId, 101);

        fundLimitBidOpt(DEFAULT_PRICE + 0.0000065 ether, DEFAULT_AMOUNT - 1, receiver);
        fundLimitBidOpt(DEFAULT_PRICE + 0.0000065 ether, DEFAULT_AMOUNT / 2, receiver);
        assertEq(diamond.getAssetStruct(asset).startingShortId, 102);
    }

    function test_UpdateStartingShortIdAfterMatchMultipleShorts() public {
        makeShorts();
        assertEq(diamond.getAssetStruct(asset).startingShortId, 101);

        fundLimitBidOpt(DEFAULT_PRICE + 0.0000066 ether, DEFAULT_AMOUNT * 4, receiver);
        assertEq(diamond.getAssetStruct(asset).startingShortId, 105);
    }

    //cancelShorts
    function test_UpdateStartingShortIdAfterCancelStartingShort() public {
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender); //100
        fundLimitShortOpt(DEFAULT_PRICE - 1 wei, DEFAULT_AMOUNT, sender); //101
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender); //102
        //101 - [100] - 102//

        assertEq(diamond.getAssetStruct(asset).startingShortId, 100);
        skip(1 hours);
        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, receiver);
        //101 - [102]//
        assertEq(diamond.getAssetStruct(asset).startingShortId, 102);

        vm.prank(sender);
        cancelShort(102);
        assertEq(diamond.getAssetStruct(asset).startingShortId, 1);
    }

    function test_UpdateStartingShortIdAfterCancelStartingShortBelowOracle() public {
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender); //100
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender); //101
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender); //102

        assertEq(diamond.getAssetStruct(asset).startingShortId, 100);

        _setETHChainlinkOnly(3999 ether); // All short orders under oracle now
        fundLimitBidOpt(DEFAULT_PRICE * 10, DEFAULT_AMOUNT, receiver);

        vm.prank(sender);
        cancelShort(100);
        assertEq(diamond.getAssetStruct(asset).startingShortId, 1);
    }

    function test_UpdateStartingShortIdAfterCancelShortNotStartingShort() public {
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender); //100
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender); //101
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender); //102

        assertEq(diamond.getAssetStruct(asset).startingShortId, 100);

        vm.prank(sender);
        cancelShort(102);
        assertEq(diamond.getAssetStruct(asset).startingShortId, 100);
    }

    function test_UpdateStartingShortIdAfterCancelStartingShortNextIdIsExact() public {
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender); //100
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender); //101
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender); //102

        assertEq(diamond.getAssetStruct(asset).startingShortId, 100);

        vm.prank(sender);
        cancelShort(100);

        assertEq(diamond.getAssetStruct(asset).startingShortId, 101);
    }

    function test_UpdateStartingShortIdAfterCancelStartingShortPrevIdIsBetter() public {
        fundLimitShortOpt(DEFAULT_PRICE + 0.00000655 ether, DEFAULT_AMOUNT, sender); //100
        fundLimitShortOpt(DEFAULT_PRICE + 0.00000655 ether, DEFAULT_AMOUNT, sender); //101
        fundLimitShortOpt(DEFAULT_PRICE + 0.00000655 ether, DEFAULT_AMOUNT, sender); //102

        assertEq(diamond.getAssetStruct(asset).startingShortId, 100);

        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender); //103
        assertEq(diamond.getAssetStruct(asset).startingShortId, 103);

        // @dev Need to change state manually to properly test this
        testFacet.setStartingShortId(asset, 100);
        assertEq(diamond.getAssetStruct(asset).startingShortId, 100);

        vm.prank(sender);
        cancelShort(100);
        assertEq(diamond.getAssetStruct(asset).startingShortId, 103);
    }

    function test_UpdateStartingShortIdWithoutMatchingShort() public {
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);
        fundLimitAskOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender); //should match this

        assertEq(getShorts()[0].id, 100);
        assertEq(getAsks()[0].id, 101);

        assertEq(diamond.getAssetStruct(asset).startingShortId, 100);
        skip(1 hours);
        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, receiver);

        // @dev matched with ask, not short. Nevertheless updated short Id
        assertEq(diamond.getAssetStruct(asset).startingShortId, 100);
    }

    //Testing general shortHintId behavior (validateAndUpdateStartingShort)
    //Revert//
    function test_RevertBadShortHintPassingHEAD() public {
        uint16[] memory shortHintArray = new uint16[](10);
        shortHintArray[0] = ZERO;
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender); //100
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender); //101
        skip(1 hours);
        ethAggregator.setRoundData(
            92233720368547778907 wei,
            3900 ether / C.BASE_ORACLE_DECIMALS,
            block.timestamp,
            block.timestamp,
            92233720368547778907 wei
        );
        depositEthAndPrank(sender, DEFAULT_PRICE.mulU88(DEFAULT_AMOUNT));
        vm.expectRevert(Errors.BadShortHint.selector);
        diamond.createBid(asset, DEFAULT_PRICE, DEFAULT_AMOUNT, C.LIMIT_ORDER, badOrderHintArray, shortHintArray);
    }

    function test_RevertShortHintAbove1PctThreshold() public {
        uint16[] memory shortHintArray = new uint16[](1);
        shortHintArray[0] = 105;
        makeShorts();
        assertEq(getShorts().length, 6);

        depositEth(receiver, DEFAULT_AMOUNT); // more than necessary
        ethAggregator.setRoundData(
            92233720368547778907 wei,
            3900 ether / C.BASE_ORACLE_DECIMALS,
            block.timestamp,
            block.timestamp,
            92233720368547778907 wei
        );
        vm.prank(receiver);
        vm.expectRevert(Errors.BadShortHint.selector);
        diamond.createBid(
            asset, DEFAULT_PRICE + 0.0000066 ether, DEFAULT_AMOUNT * 4, C.LIMIT_ORDER, badOrderHintArray, shortHintArray
        );
    }

    function test_RevertShortHintPriceIsLowerThanOracle() public {
        uint16[] memory shortHintArray = new uint16[](10);
        shortHintArray[0] = DEFAULT_SHORT_HINT_ID;
        makeShorts();
        assertEq(getShorts().length, 6);

        depositEth(receiver, DEFAULT_AMOUNT); // more than necessary
        ethAggregator.setRoundData(
            92233720368547778907 wei,
            3900 ether / C.BASE_ORACLE_DECIMALS,
            block.timestamp,
            block.timestamp,
            92233720368547778907 wei
        );
        vm.prank(receiver);
        vm.expectRevert(Errors.BadShortHint.selector);
        diamond.createBid(asset, DEFAULT_PRICE - 1 wei, DEFAULT_AMOUNT * 4, C.LIMIT_ORDER, badOrderHintArray, shortHintArray);
    }

    function test_RevertBadShortHintCancelledOrMatched() public {
        uint16[] memory shortHintArray = new uint16[](10);
        shortHintArray[0] = ZERO;
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender); //100
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender); //101
        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender); //Matches 100
        skip(1 hours);
        ethAggregator.setRoundData(
            92233720368547778907 wei,
            3900 ether / C.BASE_ORACLE_DECIMALS,
            block.timestamp,
            block.timestamp,
            92233720368547778907 wei
        );
        depositEthAndPrank(sender, DEFAULT_PRICE.mulU88(DEFAULT_AMOUNT));
        vm.expectRevert(Errors.BadShortHint.selector);
        diamond.createBid(asset, DEFAULT_PRICE, DEFAULT_AMOUNT, C.LIMIT_ORDER, badOrderHintArray, shortHintArray);
    }

    //Non-Revert//

    function test_ShortHintShortOrdersIsEmpty() public {
        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);
        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);
        assertEq(getBids().length, 2);
        assertEq(diamond.getAssetStruct(asset).startingShortId, 1);
    }

    function test_ShortHintAllShortsUnderOraclePrice() public {
        fundLimitShortOpt(DEFAULT_PRICE - 1 wei, DEFAULT_AMOUNT, sender); //100
        fundLimitShortOpt(DEFAULT_PRICE - 1 wei, DEFAULT_AMOUNT, sender); //101
        assertEq(diamond.getAssetStruct(asset).startingShortId, 1);
        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, receiver);
        assertEq(diamond.getAssetStruct(asset).startingShortId, 1);

        assertEq(getShorts().length, 2);
        assertEq(getBids().length, 1);
    }

    function test_ShortHintIsExactStartingShort() public {
        fundLimitShortOpt(DEFAULT_PRICE - 1 wei, DEFAULT_AMOUNT, sender); //100
        fundLimitShortOpt(DEFAULT_PRICE + 0.00000655 ether, DEFAULT_AMOUNT, sender); //101
        fundLimitBidOpt(DEFAULT_PRICE + 0.00000655 ether, DEFAULT_AMOUNT, receiver);
        assertEq(diamond.getAssetStruct(asset).startingShortId, 1);
    }

    function test_ShortHintStartingShortWithinOracleRange() public {
        uint16[] memory shortHintArray = new uint16[](10);
        shortHintArray[0] = DEFAULT_SHORT_HINT_ID;
        fundLimitShortOpt(DEFAULT_PRICE - 1 wei, DEFAULT_AMOUNT, sender); //100
        fundLimitShortOpt(DEFAULT_PRICE + 0.00000655 ether, DEFAULT_AMOUNT, sender); //101
        fundLimitShortOpt(DEFAULT_PRICE + 0.0000066 ether, DEFAULT_AMOUNT, sender); //102
        fundLimitShortOpt(1 ether, DEFAULT_AMOUNT, sender); //103
        skip(1 hours);
        depositEth(receiver, DEFAULT_PRICE.mulU80(DEFAULT_AMOUNT) * 5);
        ethAggregator.setRoundData(
            92233720368547778907 wei,
            3900 ether / C.BASE_ORACLE_DECIMALS,
            block.timestamp,
            block.timestamp,
            92233720368547778907 wei
        );
        vm.startPrank(receiver);
        vm.expectRevert(Errors.BadShortHint.selector);
        diamond.createBid(asset, DEFAULT_PRICE + 0.00000655 ether, DEFAULT_AMOUNT, C.LIMIT_ORDER, badOrderHintArray, shortHintArray);
        MTypes.OrderHint[] memory orderHintArray = diamond.getHintArray(asset, DEFAULT_PRICE + 0.0000066 ether, O.LimitBid, 1);
        shortHintArray[1] = 102;
        //passes even though 101 would have been exact match
        diamond.createBid(asset, DEFAULT_PRICE + 0.0000066 ether, DEFAULT_AMOUNT, C.LIMIT_ORDER, orderHintArray, shortHintArray);
        assertEq(diamond.getAssetStruct(asset).startingShortId, 102);
    }

    function test_ShortOrdersEmptyOrAllShortsUnderOraclePrice() public {
        //create ask so it doesn't revert early
        fundLimitAskOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);
        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, receiver);
        assertEq(diamond.getAssetStruct(asset).startingShortId, 1); //set to HEAD

        //make short under oracle price
        fundLimitShortOpt(testFacet.getOraclePriceT(asset) - 1 wei, DEFAULT_AMOUNT, sender);
        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, receiver);
        assertEq(diamond.getAssetStruct(asset).startingShortId, 1); //set to HEAD
        assertEq(getBids().length, 1); //did not match
    }

    //Test matching backward and then forward
    function test_MatchingBackwardOnly() public {
        makeShorts();

        assertEq(getShorts().length, 6);

        fundLimitBidOpt(DEFAULT_PRICE + 0.0000066 ether, DEFAULT_AMOUNT * 4, receiver);

        assertEq(getShorts().length, 2);
        assertEq(getShorts()[0].id, 100);
        assertEq(getShorts()[1].id, 105);
        assertEq(getBids().length, 0);

        assertEq(diamond.getAssetStruct(asset).startingShortId, 105);
    }

    function test_MatchingBackwardOnlyWithSomeEligibleShortsRemaining() public {
        uint16[] memory shortHintArray = new uint16[](1);
        shortHintArray[0] = 104;

        fundLimitShortOpt(DEFAULT_PRICE - 1 wei, DEFAULT_AMOUNT, sender); //100
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender); //101
        fundLimitShortOpt(DEFAULT_PRICE + 1 wei, DEFAULT_AMOUNT, sender); //102
        fundLimitShortOpt(DEFAULT_PRICE + 1 wei, DEFAULT_AMOUNT, sender); //103
        fundLimitShortOpt(DEFAULT_PRICE + 2 wei, DEFAULT_AMOUNT, sender); //104
        fundLimitShortOpt(DEFAULT_PRICE * 2, DEFAULT_AMOUNT, sender); //105

        ethAggregator.setRoundData(
            92233720368547778907 wei,
            4001 ether / C.BASE_ORACLE_DECIMALS,
            block.timestamp,
            block.timestamp,
            92233720368547778907 wei
        );
        skip(1 hours);

        assertEq(getShorts().length, 6);

        depositEth(receiver, DEFAULT_PRICE.mulU80(DEFAULT_AMOUNT) * 5);
        vm.startPrank(receiver);

        diamond.createBid(asset, DEFAULT_PRICE + 2 wei, DEFAULT_AMOUNT * 3, C.LIMIT_ORDER, badOrderHintArray, shortHintArray);

        assertEq(getShorts().length, 3);
        assertEq(getShorts()[0].id, 100);
        assertEq(getShorts()[1].id, 104);
        assertEq(getShorts()[2].id, 105);
        assertEq(getBids().length, 0);

        assertEq(diamond.getAssetStruct(asset).startingShortId, 100);
    }

    function test_MatchingBackwardThenForward() public {
        makeShorts();
        assertEq(getShorts().length, 6);
        fundLimitBidOpt(DEFAULT_PRICE + 0.0000066 ether, DEFAULT_AMOUNT * 4, receiver);
        assertEq(getShorts().length, 2);
        assertEq(getShorts()[0].id, 100);
        assertEq(getShorts()[1].id, 105);
        assertEq(getBids().length, 0);
        assertEq(diamond.getAssetStruct(asset).startingShortId, 105);
    }

    function test_MatchingBackwardThenForwardWithSomeEligibleShortsRemaining() public {
        makeShorts();

        assertEq(getShorts().length, 6);
        fundLimitBidOpt(DEFAULT_PRICE + 0.00000655 ether, DEFAULT_AMOUNT * 3, receiver);
        assertEq(getShorts().length, 3);
        assertEq(getShorts()[0].id, 100);
        assertEq(getShorts()[1].id, 104);
        assertEq(getShorts()[2].id, 105);
        assertEq(getBids().length, 0);

        assertEq(diamond.getAssetStruct(asset).startingShortId, 104);
    }

    //Matching incomingShorts with existing Bids
    function test_ShortHintMatchIncomingShortsWithExistingBids() public {
        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, receiver);
        assertEq(diamond.getAssetStruct(asset).startingShortId, 1);

        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);
        assertEq(diamond.getAssetStruct(asset).startingShortId, 1);
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);
        assertEq(diamond.getAssetStruct(asset).startingShortId, 101);

        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, receiver);
        assertEq(diamond.getAssetStruct(asset).startingShortId, 1);

        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, receiver);
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);
        assertEq(diamond.getAssetStruct(asset).startingShortId, 1);
    }

    function test_RevertAllBadShortHintsInArray() public {
        uint16[] memory shortHintArray = new uint16[](10);

        for (uint16 i = 0; i < shortHintArray.length; i++) {
            shortHintArray[i] = 101 + i;
        }

        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);
        skip(1 hours);
        depositEthAndPrank(receiver, 10 ether);
        ethAggregator.setRoundData(
            92233720368547778907 wei,
            3900 ether / C.BASE_ORACLE_DECIMALS,
            block.timestamp,
            block.timestamp,
            92233720368547778907 wei
        );
        vm.expectRevert(Errors.BadShortHint.selector);
        diamond.createBid(
            asset, DEFAULT_PRICE + 0.00000655 ether, DEFAULT_AMOUNT * 3, C.LIMIT_ORDER, badOrderHintArray, shortHintArray
        );
    }

    //Scenario testing
    function makeShortsScenarioTesting() public {
        fundLimitShortOpt(DEFAULT_PRICE - 1 wei, DEFAULT_AMOUNT, sender); //100
        fundLimitShortOpt(DEFAULT_PRICE + 0.0000065 ether, DEFAULT_AMOUNT, sender); //101
        fundLimitShortOpt(DEFAULT_PRICE + 0.00000655 ether, DEFAULT_AMOUNT, sender); //102
        fundLimitShortOpt(DEFAULT_PRICE + 0.00000655 ether, DEFAULT_AMOUNT, sender); //103
        fundLimitShortOpt(DEFAULT_PRICE + 0.0000066 ether, DEFAULT_AMOUNT, sender); //104
        fundLimitShortOpt(DEFAULT_PRICE + 0.00000665 ether, DEFAULT_AMOUNT, sender); //105
        skip(1 hours);
        ethAggregator.setRoundData(
            92233720368547778907 wei,
            3900 ether / C.BASE_ORACLE_DECIMALS,
            block.timestamp,
            block.timestamp,
            92233720368547778907 wei
        );
    }

    // @dev Starts at 101. Fills 101, 102, 103, 104, 105. Some bid leftover
    function test_Scenario1_MovingFwd_bidErcGtSellErc() public {
        uint16[] memory shortHintArray = new uint16[](1);
        shortHintArray[0] = 101;
        makeShortsScenarioTesting();
        depositEthAndPrank(receiver, 100 ether);
        diamond.createBid(
            asset, DEFAULT_PRICE * 5, DEFAULT_AMOUNT.mulU88(6.5 ether), C.LIMIT_ORDER, badOrderHintArray, shortHintArray
        );
        assertEq(getShorts().length, 1);
        assertEq(getBids().length, 1);
        assertEq(getBids()[0].ercAmount, DEFAULT_AMOUNT.mulU88(1.5 ether));
        assertEq(diamond.getAssetStruct(asset).startingShortId, C.HEAD);
        // Fill Order
        assertEq(diamond.getShortOrder(asset, C.HEAD).prevId, 105);
        assertEq(diamond.getShortOrder(asset, 105).prevId, 104);
        assertEq(diamond.getShortOrder(asset, 104).prevId, 103);
        assertEq(diamond.getShortOrder(asset, 103).prevId, 102);
        assertEq(diamond.getShortOrder(asset, 102).prevId, 101);
    }

    // @dev Starts at 101. Fills 101, 102, 103, 104, 105
    function test_Scenario2_MovingFwd_bidErcEqSellErc() public {
        uint16[] memory shortHintArray = new uint16[](1);
        shortHintArray[0] = 101;
        makeShortsScenarioTesting();
        depositEthAndPrank(receiver, 100 ether);
        diamond.createBid(asset, DEFAULT_PRICE * 5, DEFAULT_AMOUNT * 5, C.LIMIT_ORDER, badOrderHintArray, shortHintArray);
        assertEq(getShorts().length, 1);
        assertEq(getShorts()[0].id, 100);
        assertEq(getBids().length, 0);
        assertEq(diamond.getAssetStruct(asset).startingShortId, C.HEAD);
        // Fill Order
        assertEq(diamond.getShortOrder(asset, C.HEAD).prevId, 105);
        assertEq(diamond.getShortOrder(asset, 105).prevId, 104);
        assertEq(diamond.getShortOrder(asset, 104).prevId, 103);
        assertEq(diamond.getShortOrder(asset, 103).prevId, 102);
        assertEq(diamond.getShortOrder(asset, 102).prevId, 101);
    }

    // @dev Starts at 101. Fills 101, 102. Partially fills 103
    function test_Scenario3_MovingFwd_bidErcLtSellErc() public {
        uint16[] memory shortHintArray = new uint16[](1);
        shortHintArray[0] = 101;
        makeShortsScenarioTesting();
        depositEthAndPrank(receiver, 100 ether);
        diamond.createBid(
            asset, DEFAULT_PRICE * 5, DEFAULT_AMOUNT.mulU88(2.5 ether), C.LIMIT_ORDER, badOrderHintArray, shortHintArray
        );
        assertEq(getShorts().length, 4);
        assertEq(getShorts()[0].id, 100);
        assertEq(getShorts()[1].id, 103);
        assertEq(getShorts()[2].id, 104);
        assertEq(getShorts()[3].id, 105);
        assertEq(getShorts()[1].ercAmount, DEFAULT_AMOUNT.mulU88(0.5 ether)); //103
        assertEq(getBids().length, 0);
        assertEq(diamond.getAssetStruct(asset).startingShortId, 103);
        // Fill Order
        assertEq(diamond.getShortOrder(asset, C.HEAD).prevId, 102);
        assertEq(diamond.getShortOrder(asset, 102).prevId, 101);
    }

    // @dev Starts at (105-1)=104. Fills 104, 103, 102, 101, 105. Some bid leftover
    function test_Scenario4_MovingBack_bidErcGtSellErc() public {
        uint16[] memory shortHintArray = new uint16[](1);
        shortHintArray[0] = 105;
        makeShortsScenarioTesting();
        depositEthAndPrank(receiver, 100 ether);
        diamond.createBid(
            asset, DEFAULT_PRICE * 5, DEFAULT_AMOUNT.mulU88(6.5 ether), C.LIMIT_ORDER, badOrderHintArray, shortHintArray
        );
        assertEq(getShorts().length, 1);
        assertEq(getShorts()[0].id, 100);
        assertEq(getBids().length, 1);
        assertEq(getBids()[0].ercAmount, DEFAULT_AMOUNT.mulU88(1.5 ether));
        assertEq(diamond.getAssetStruct(asset).startingShortId, C.HEAD);
        // Fill Order
        assertEq(diamond.getShortOrder(asset, C.HEAD).prevId, 105);
        assertEq(diamond.getShortOrder(asset, 105).prevId, 101);
        assertEq(diamond.getShortOrder(asset, 101).prevId, 102);
        assertEq(diamond.getShortOrder(asset, 102).prevId, 103);
        assertEq(diamond.getShortOrder(asset, 103).prevId, 104);
    }

    // @dev Starts at (105-1)=104. Fills 104, 103, 102, 101.
    function test_Scenario5_MovingBack_bidErcEqSellErc() public {
        uint16[] memory shortHintArray = new uint16[](1);
        shortHintArray[0] = 105;
        makeShortsScenarioTesting();
        depositEthAndPrank(receiver, 100 ether);
        diamond.createBid(asset, DEFAULT_PRICE * 5, DEFAULT_AMOUNT * 4, C.LIMIT_ORDER, badOrderHintArray, shortHintArray);
        assertEq(getShorts().length, 2);
        assertEq(getShorts()[0].id, 100);
        assertEq(getShorts()[1].id, 105);
        assertEq(getBids().length, 0);
        assertEq(diamond.getAssetStruct(asset).startingShortId, 105);
        // Fill Order
        assertEq(diamond.getShortOrder(asset, C.HEAD).prevId, 101);
        assertEq(diamond.getShortOrder(asset, 101).prevId, 102);
        assertEq(diamond.getShortOrder(asset, 102).prevId, 103);
        assertEq(diamond.getShortOrder(asset, 103).prevId, 104);
    }

    // @dev Starts at (105-1)=104. Fills 104, 103. Partially fills 102
    function test_Scenario6_MovingBack_bidErcLtSellErc() public {
        uint16[] memory shortHintArray = new uint16[](1);
        shortHintArray[0] = 105;
        makeShortsScenarioTesting();
        depositEthAndPrank(receiver, 100 ether);
        diamond.createBid(
            asset, DEFAULT_PRICE * 5, DEFAULT_AMOUNT.mulU88(2.5 ether), C.LIMIT_ORDER, badOrderHintArray, shortHintArray
        );
        assertEq(getShorts().length, 4);
        assertEq(getShorts()[0].id, 100);
        assertEq(getShorts()[1].id, 101);
        assertEq(getShorts()[2].id, 102);
        assertEq(getShorts()[3].id, 105);
        assertEq(getShorts()[2].ercAmount, DEFAULT_AMOUNT.mulU88(0.5 ether)); //102
        assertEq(getBids().length, 0);
        assertEq(diamond.getAssetStruct(asset).startingShortId, 102);
        // Fill Order
        assertEq(diamond.getShortOrder(asset, C.HEAD).prevId, 103);
        assertEq(diamond.getShortOrder(asset, 103).prevId, 104);
    }

    // @dev Starts at (104-1)=103. Fills 103, 102, 101, 104, 105. Some bid leftover
    function test_Scenario7_MovingBackThenFwd_bidErcGtSellErc() public {
        uint16[] memory shortHintArray = new uint16[](1);
        shortHintArray[0] = 104;
        makeShortsScenarioTesting();
        depositEthAndPrank(receiver, 100 ether);
        diamond.createBid(
            asset, DEFAULT_PRICE * 5, DEFAULT_AMOUNT.mulU88(6.5 ether), C.LIMIT_ORDER, badOrderHintArray, shortHintArray
        );
        assertEq(getShorts().length, 1);
        assertEq(getShorts()[0].id, 100);
        assertEq(getBids().length, 1);
        assertEq(getBids()[0].ercAmount, DEFAULT_AMOUNT.mulU88(1.5 ether));
        assertEq(diamond.getAssetStruct(asset).startingShortId, C.HEAD);
        // Fill Order
        assertEq(diamond.getShortOrder(asset, C.HEAD).prevId, 105);
        assertEq(diamond.getShortOrder(asset, 105).prevId, 104);
        assertEq(diamond.getShortOrder(asset, 104).prevId, 101);
        assertEq(diamond.getShortOrder(asset, 101).prevId, 102);
        assertEq(diamond.getShortOrder(asset, 102).prevId, 103);
    }

    // @dev Starts at (104-1)=103. Fills 103, 102, 101, 104, 105.
    function test_Scenario8_MovingBackThenFwd_bidErcEqSellErc() public {
        uint16[] memory shortHintArray = new uint16[](1);
        shortHintArray[0] = 104;
        makeShortsScenarioTesting();
        depositEthAndPrank(receiver, 100 ether);
        diamond.createBid(asset, DEFAULT_PRICE * 5, DEFAULT_AMOUNT * 5, C.LIMIT_ORDER, badOrderHintArray, shortHintArray);
        assertEq(getShorts().length, 1);
        assertEq(getShorts()[0].id, 100);
        assertEq(getBids().length, 0);
        assertEq(diamond.getAssetStruct(asset).startingShortId, C.HEAD);
        // Fill Order
        assertEq(diamond.getShortOrder(asset, C.HEAD).prevId, 105);
        assertEq(diamond.getShortOrder(asset, 105).prevId, 104);
        assertEq(diamond.getShortOrder(asset, 104).prevId, 101);
        assertEq(diamond.getShortOrder(asset, 101).prevId, 102);
        assertEq(diamond.getShortOrder(asset, 102).prevId, 103);
    }

    // @dev Starts at (104-1)=103. Fills 103, 102. Partially fills 101
    function test_Scenario9_MovingBackThenFwd_bidErcLtSellErc() public {
        uint16[] memory shortHintArray = new uint16[](1);
        shortHintArray[0] = 104;
        makeShortsScenarioTesting();
        depositEthAndPrank(receiver, 100 ether);
        diamond.createBid(
            asset, DEFAULT_PRICE * 5, DEFAULT_AMOUNT.mulU88(2.5 ether), C.LIMIT_ORDER, badOrderHintArray, shortHintArray
        );
        assertEq(getShorts().length, 4);
        assertEq(getShorts()[0].id, 100);
        assertEq(getShorts()[1].id, 101);
        assertEq(getShorts()[2].id, 104);
        assertEq(getShorts()[3].id, 105);
        assertEq(getShorts()[1].ercAmount, DEFAULT_AMOUNT.mulU88(0.5 ether)); //101
        assertEq(getBids().length, 0);
        assertEq(diamond.getAssetStruct(asset).startingShortId, 101);
        // Fill Order
        assertEq(diamond.getShortOrder(asset, C.HEAD).prevId, 102);
        assertEq(diamond.getShortOrder(asset, 102).prevId, 103);
    }

    // @dev Starts at (104-1)=103. Fills 103. Partially Fills 102
    function test_Scenario10_MatchOnlyOne_bidErcGtSellErc() public {
        uint16[] memory shortHintArray = new uint16[](1);
        shortHintArray[0] = 104;
        makeShortsScenarioTesting();
        depositEthAndPrank(receiver, 100 ether);
        diamond.createBid(
            asset, DEFAULT_PRICE * 5, DEFAULT_AMOUNT.mulU88(1.5 ether), C.LIMIT_ORDER, badOrderHintArray, shortHintArray
        );
        assertEq(getShorts().length, 5);
        assertEq(getShorts()[0].id, 100);
        assertEq(getShorts()[1].id, 101);
        assertEq(getShorts()[2].id, 102);
        assertEq(getShorts()[3].id, 104);
        assertEq(getShorts()[4].id, 105);
        assertEq(getShorts()[2].ercAmount, DEFAULT_AMOUNT.mulU88(0.5 ether));
        assertEq(getBids().length, 0);
        assertEq(diamond.getAssetStruct(asset).startingShortId, 102);
    }

    // @dev Starts at (104-1)=103. Fills 103.
    function test_Scenario11_MatchOnlyOne_bidErcEqSellErc() public {
        uint16[] memory shortHintArray = new uint16[](1);
        shortHintArray[0] = 104;
        makeShortsScenarioTesting();
        depositEthAndPrank(receiver, 100 ether);
        diamond.createBid(asset, DEFAULT_PRICE * 5, DEFAULT_AMOUNT, C.LIMIT_ORDER, badOrderHintArray, shortHintArray);
        assertEq(getShorts().length, 5);
        assertEq(getShorts()[0].id, 100);
        assertEq(getShorts()[1].id, 101);
        assertEq(getShorts()[2].id, 102);
        assertEq(getShorts()[3].id, 104);
        assertEq(getShorts()[4].id, 105);
        assertEq(getShorts()[2].ercAmount, DEFAULT_AMOUNT);
        assertEq(getBids().length, 0);
        assertEq(diamond.getAssetStruct(asset).startingShortId, 102);
    }

    // @dev Starts at (104-1)=103. Partially Fills 103.
    function test_Scenario12_MatchOnlyOne_bidErcLtSellErc() public {
        uint16[] memory shortHintArray = new uint16[](1);
        shortHintArray[0] = 104;
        makeShortsScenarioTesting();
        depositEthAndPrank(receiver, 100 ether);
        diamond.createBid(
            asset, DEFAULT_PRICE * 5, DEFAULT_AMOUNT.mulU88(0.5 ether), C.LIMIT_ORDER, badOrderHintArray, shortHintArray
        );
        assertEq(getShorts().length, 6);
        assertEq(getShorts()[0].id, 100);
        assertEq(getShorts()[1].id, 101);
        assertEq(getShorts()[2].id, 102);
        assertEq(getShorts()[3].id, 103);
        assertEq(getShorts()[4].id, 104);
        assertEq(getShorts()[5].id, 105);
        assertEq(getShorts()[3].ercAmount, DEFAULT_AMOUNT.mulU88(0.5 ether));
        assertEq(getBids().length, 0);
        assertEq(diamond.getAssetStruct(asset).startingShortId, 103);
    }
}
