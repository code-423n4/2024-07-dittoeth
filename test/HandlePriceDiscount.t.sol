// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {U256, U104, U88, U80} from "contracts/libraries/PRBMathHelper.sol";

import {Errors} from "contracts/libraries/Errors.sol";
import {C, VAULT} from "contracts/libraries/Constants.sol";
import {STypes, MTypes, O, SR} from "contracts/libraries/DataTypes.sol";
import {DiscountLevels} from "test/utils/TestTypes.sol";
import {OBFixture} from "test/utils/OBFixture.sol";
import {LiquidationHelper} from "test/utils/LiquidationHelper.sol";

import {console} from "contracts/libraries/console.sol";

contract HandlePriceDiscountIncomingAskTest is OBFixture {
    using U256 for uint256;
    using U88 for uint88;
    using U80 for uint80;

    bool SAME_PRICE = true;
    bool DIFFERENT_PRICE = false;
    uint88 amount = ERCDEBTSEED;
    uint256 discountCounterGt1 = 91;
    uint256 discountCounterGt2 = 84;
    uint256 discountCounterGt3 = 77;
    uint256 discountCounterGt4 = 71;
    uint256 counter;
    uint64 discountPenaltyFee;

    function setUp() public override {
        super.setUp();

        // @dev Seed the ercDebtAsset with some huge number to prevent the DISCOUNT_THRESHOLD from being applied
        fundLimitBidOpt(DEFAULT_PRICE, amount, extra);
        fundLimitShortOpt(DEFAULT_PRICE, amount, extra);

        // @dev Matching above caused Asset.discountedErcMatched = 1 wei
        if (diamond.getAssetStruct(asset).discountedErcMatched == 1 wei) diamond.setDiscountedErcMatchedAsset(asset, 0);
        discountPenaltyFee = uint64(diamond.getAssetNormalizedStruct(asset).discountPenaltyFee);
    }

    function setUpPricesIncomingAsk(DiscountLevels discountLevel, bool samePrice)
        public
        view
        returns (uint80 askPrice, uint80 bidPrice)
    {
        uint80 savedPrice = uint80(diamond.getProtocolAssetPrice(asset));
        uint256 askMultiplier;
        uint256 bidMultiplier;

        // @dev system matches based on price of order on ob (in these cases, the bid's price)
        if (discountLevel == DiscountLevels.Gte1) {
            if (samePrice) {
                bidMultiplier = askMultiplier = 0.99 ether;
            } else {
                askMultiplier = 0.98 ether;
                bidMultiplier = 0.99 ether;
            }
        } else if (discountLevel == DiscountLevels.Gte2) {
            if (samePrice) {
                bidMultiplier = askMultiplier = 0.98 ether;
            } else {
                askMultiplier = 0.97 ether;
                bidMultiplier = 0.98 ether;
            }
        } else if (discountLevel == DiscountLevels.Gte3) {
            if (samePrice) {
                bidMultiplier = askMultiplier = 0.97 ether;
            } else {
                askMultiplier = 0.96 ether;
                bidMultiplier = 0.97 ether;
            }
        } else if (discountLevel == DiscountLevels.Gte4) {
            if (samePrice) {
                bidMultiplier = askMultiplier = 0.96 ether;
            } else {
                askMultiplier = 0.95 ether;
                bidMultiplier = 0.96 ether;
            }
        }

        askPrice = uint80(savedPrice.mul(askMultiplier));
        bidPrice = uint80(savedPrice.mul(bidMultiplier));
    }

    function test_handleDiscount_IsDiscounted_Gt1Pct_IncomingAsk_SamePrice() public {
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, 0);
        (uint80 askPrice, uint80 bidPrice) = setUpPricesIncomingAsk({discountLevel: DiscountLevels.Gte1, samePrice: SAME_PRICE});

        fundLimitBidOpt(bidPrice, amount, receiver);

        uint256 discountPct;
        uint88 weightedErcAmount;
        uint80 savedPrice = uint80(diamond.getProtocolAssetPrice(asset));
        uint256 ercDebt = diamond.getAssetStruct(asset).ercDebt;
        for (uint256 i = 0; i < 100; i++) {
            fundLimitAskOpt(askPrice, DEFAULT_AMOUNT, sender);
            discountPct = min((savedPrice - bidPrice).div(savedPrice), 0.05 ether) * 10; //bidPrice is used since it was on ob first
            uint256 discount = 1 ether + discountPct;
            weightedErcAmount += DEFAULT_AMOUNT.mulU88(discount);
            ercDebt += DEFAULT_AMOUNT;
            if (diamond.getAssetStruct(asset).ercDebtRate > 0) break;
            assertEq(diamond.getAssetStruct(asset).discountedErcMatched, weightedErcAmount);
            counter++;
        }

        // Confirm that lower discounts take longer to hit threshold
        assertEq(counter, discountCounterGt1);
        assertGt(discountCounterGt1, discountCounterGt2);

        // Fee applied
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, discountPenaltyFee);
        // Reset values
        assertEq(diamond.getAssetStruct(asset).discountedErcMatched, 1 wei);
    }

    function test_handleDiscount_IsDiscounted_Gt1Pct_IncomingAsk_DifferentPrice() public {
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, 0);
        (uint80 askPrice, uint80 bidPrice) =
            setUpPricesIncomingAsk({discountLevel: DiscountLevels.Gte1, samePrice: DIFFERENT_PRICE});

        fundLimitBidOpt(bidPrice, amount, receiver);

        uint256 discountPct;
        uint88 weightedErcAmount;
        uint80 savedPrice = uint80(diamond.getProtocolAssetPrice(asset));
        uint256 ercDebt = diamond.getAssetStruct(asset).ercDebt;
        for (uint256 i = 0; i < 100; i++) {
            fundLimitAskOpt(askPrice, DEFAULT_AMOUNT, sender);
            discountPct = min((savedPrice - bidPrice).div(savedPrice), 0.05 ether) * 10; //bidPrice is used since it was on ob first
            uint256 discount = 1 ether + discountPct;
            weightedErcAmount += DEFAULT_AMOUNT.mulU88(discount);
            ercDebt += DEFAULT_AMOUNT;
            if (diamond.getAssetStruct(asset).ercDebtRate > 0) break;
            assertEq(diamond.getAssetStruct(asset).discountedErcMatched, weightedErcAmount);
            counter++;
        }

        // Confirm that lower discounts take longer to hit threshold
        assertEq(counter, discountCounterGt1);
        assertGt(discountCounterGt1, discountCounterGt2);

        // Fee applied
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, discountPenaltyFee);
        // Reset values
        assertEq(diamond.getAssetStruct(asset).discountedErcMatched, 1 wei);
    }

    function test_handleDiscount_IsDiscounted_Gt2Pct_IncomingAsk_SamePrice() public {
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, 0);
        (uint80 askPrice, uint80 bidPrice) = setUpPricesIncomingAsk({discountLevel: DiscountLevels.Gte2, samePrice: SAME_PRICE});

        fundLimitBidOpt(bidPrice, amount, receiver);

        uint256 discountPct;
        uint88 weightedErcAmount;
        uint80 savedPrice = uint80(diamond.getProtocolAssetPrice(asset));
        uint256 ercDebt = diamond.getAssetStruct(asset).ercDebt;
        for (uint256 i = 0; i < 100; i++) {
            fundLimitAskOpt(askPrice, DEFAULT_AMOUNT, sender);
            discountPct = min((savedPrice - bidPrice).div(savedPrice), 0.05 ether) * 10; //bidPrice is used since it was on ob first
            uint256 discount = 1 ether + discountPct;
            weightedErcAmount += DEFAULT_AMOUNT.mulU88(discount);
            ercDebt += DEFAULT_AMOUNT;
            if (diamond.getAssetStruct(asset).ercDebtRate > 0) break;
            assertEq(diamond.getAssetStruct(asset).discountedErcMatched, weightedErcAmount);
            counter++;
        }

        // Confirm that lower discounts take longer to hit threshold
        assertEq(counter, discountCounterGt2);
        assertGt(discountCounterGt2, discountCounterGt3);

        // Fee applied
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, discountPenaltyFee);
        // Reset values
        assertEq(diamond.getAssetStruct(asset).discountedErcMatched, 1 wei);
    }

    function test_handleDiscount_IsDiscounted_Gt2Pct_IncomingAsk_DifferentPrice() public {
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, 0);
        (uint80 askPrice, uint80 bidPrice) =
            setUpPricesIncomingAsk({discountLevel: DiscountLevels.Gte2, samePrice: DIFFERENT_PRICE});

        fundLimitBidOpt(bidPrice, amount, receiver);

        uint256 discountPct;
        uint88 weightedErcAmount;
        uint80 savedPrice = uint80(diamond.getProtocolAssetPrice(asset));
        uint256 ercDebt = diamond.getAssetStruct(asset).ercDebt;
        for (uint256 i = 0; i < 100; i++) {
            fundLimitAskOpt(askPrice, DEFAULT_AMOUNT, sender);
            discountPct = min((savedPrice - bidPrice).div(savedPrice), 0.05 ether) * 10; //bidPrice is used since it was on ob first
            uint256 discount = 1 ether + discountPct;
            weightedErcAmount += DEFAULT_AMOUNT.mulU88(discount);
            ercDebt += DEFAULT_AMOUNT;
            if (diamond.getAssetStruct(asset).ercDebtRate > 0) break;
            assertEq(diamond.getAssetStruct(asset).discountedErcMatched, weightedErcAmount);
            counter++;
        }

        // Confirm that lower discounts take longer to hit threshold
        assertEq(counter, discountCounterGt2);
        assertGt(discountCounterGt2, discountCounterGt3);

        // Fee applied
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, discountPenaltyFee);
        // Reset values
        assertEq(diamond.getAssetStruct(asset).discountedErcMatched, 1 wei);
    }

    function test_handleDiscount_IsDiscounted_Gt3Pct_IncomingAsk_SamePrice() public {
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, 0);
        (uint80 askPrice, uint80 bidPrice) = setUpPricesIncomingAsk({discountLevel: DiscountLevels.Gte3, samePrice: SAME_PRICE});

        fundLimitBidOpt(bidPrice, amount, receiver);

        uint256 discountPct;
        uint88 weightedErcAmount;
        uint80 savedPrice = uint80(diamond.getProtocolAssetPrice(asset));
        uint256 ercDebt = diamond.getAssetStruct(asset).ercDebt;
        for (uint256 i = 0; i < 100; i++) {
            fundLimitAskOpt(askPrice, DEFAULT_AMOUNT, sender);
            discountPct = min((savedPrice - bidPrice).div(savedPrice), 0.05 ether) * 10; //bidPrice is used since it was on ob first
            uint256 discount = 1 ether + discountPct;
            weightedErcAmount += DEFAULT_AMOUNT.mulU88(discount);
            ercDebt += DEFAULT_AMOUNT;
            if (diamond.getAssetStruct(asset).ercDebtRate > 0) break;
            assertEq(diamond.getAssetStruct(asset).discountedErcMatched, weightedErcAmount);
            counter++;
        }

        // Confirm that lower discounts take longer to hit threshold
        assertEq(counter, discountCounterGt3);
        assertGt(discountCounterGt3, discountCounterGt4);

        // Fee applied
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, discountPenaltyFee);
        // Reset values
        assertEq(diamond.getAssetStruct(asset).discountedErcMatched, 1 wei);
    }

    function test_handleDiscount_IsDiscounted_Gt3Pct_IncomingAsk_DifferentPrice() public {
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, 0);
        (uint80 askPrice, uint80 bidPrice) =
            setUpPricesIncomingAsk({discountLevel: DiscountLevels.Gte3, samePrice: DIFFERENT_PRICE});

        fundLimitBidOpt(bidPrice, amount, receiver);

        uint256 discountPct;
        uint88 weightedErcAmount;
        uint80 savedPrice = uint80(diamond.getProtocolAssetPrice(asset));
        uint256 ercDebt = diamond.getAssetStruct(asset).ercDebt;
        for (uint256 i = 0; i < 100; i++) {
            fundLimitAskOpt(askPrice, DEFAULT_AMOUNT, sender);
            discountPct = min((savedPrice - bidPrice).div(savedPrice), 0.05 ether) * 10; //bidPrice is used since it was on ob first
            uint256 discount = 1 ether + discountPct;
            weightedErcAmount += DEFAULT_AMOUNT.mulU88(discount);
            ercDebt += DEFAULT_AMOUNT;
            if (diamond.getAssetStruct(asset).ercDebtRate > 0) break;
            assertEq(diamond.getAssetStruct(asset).discountedErcMatched, weightedErcAmount);
            counter++;
        }

        // Confirm that lower discounts take longer to hit threshold
        assertEq(counter, discountCounterGt3);
        assertGt(discountCounterGt3, discountCounterGt4);

        // Fee applied
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, discountPenaltyFee);
        // Reset values
        assertEq(diamond.getAssetStruct(asset).discountedErcMatched, 1 wei);
    }

    function test_handleDiscount_IsDiscounted_Gt4Pct_IncomingAsk_SamePrice() public {
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, 0);
        (uint80 askPrice, uint80 bidPrice) = setUpPricesIncomingAsk({discountLevel: DiscountLevels.Gte4, samePrice: SAME_PRICE});

        fundLimitBidOpt(bidPrice, amount, receiver);

        uint256 discountPct;
        uint88 weightedErcAmount;
        uint80 savedPrice = uint80(diamond.getProtocolAssetPrice(asset));
        uint256 ercDebt = diamond.getAssetStruct(asset).ercDebt;
        for (uint256 i = 0; i < 100; i++) {
            fundLimitAskOpt(askPrice, DEFAULT_AMOUNT, sender);
            discountPct = min((savedPrice - bidPrice).div(savedPrice), 0.05 ether) * 10; //bidPrice is used since it was on ob first
            uint256 discount = 1 ether + discountPct;
            weightedErcAmount += DEFAULT_AMOUNT.mulU88(discount);
            ercDebt += DEFAULT_AMOUNT;
            if (diamond.getAssetStruct(asset).ercDebtRate > 0) break;
            assertEq(diamond.getAssetStruct(asset).discountedErcMatched, weightedErcAmount);
            counter++;
        }

        // Confirm that lower discounts take longer to hit threshold
        assertEq(counter, discountCounterGt4);

        // Fee applied
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, discountPenaltyFee);
        // Reset values
        assertEq(diamond.getAssetStruct(asset).discountedErcMatched, 1 wei);
    }

    function test_handleDiscount_IsDiscounted_Gt4Pct_IncomingAsk_DifferentPrice() public {
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, 0);
        (uint80 askPrice, uint80 bidPrice) =
            setUpPricesIncomingAsk({discountLevel: DiscountLevels.Gte4, samePrice: DIFFERENT_PRICE});

        fundLimitBidOpt(bidPrice, amount, receiver);

        uint256 discountPct;
        uint88 weightedErcAmount;
        uint80 savedPrice = uint80(diamond.getProtocolAssetPrice(asset));
        uint256 ercDebt = diamond.getAssetStruct(asset).ercDebt;
        for (uint256 i = 0; i < 100; i++) {
            fundLimitAskOpt(askPrice, DEFAULT_AMOUNT, sender);
            discountPct = min((savedPrice - bidPrice).div(savedPrice), 0.05 ether) * 10; //bidPrice is used since it was on ob first
            uint256 discount = 1 ether + discountPct;
            weightedErcAmount += DEFAULT_AMOUNT.mulU88(discount);
            ercDebt += DEFAULT_AMOUNT;
            if (diamond.getAssetStruct(asset).ercDebtRate > 0) break;
            assertEq(diamond.getAssetStruct(asset).discountedErcMatched, weightedErcAmount);
            counter++;
        }

        // Confirm that lower discounts take longer to hit threshold
        assertEq(counter, discountCounterGt4);

        // Fee applied
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, discountPenaltyFee);
        // Reset values
        assertEq(diamond.getAssetStruct(asset).discountedErcMatched, 1 wei);
    }

    // @dev Discounted matches increase discountedErcMatched but non discounted matches decrease discountedErcMatched
    function test_handleDiscount_FirstIsDiscounted_IncomingAsk_LaterIsNotDiscounted() public {
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, 0);
        (uint80 askPrice, uint80 bidPrice) = setUpPricesIncomingAsk({discountLevel: DiscountLevels.Gte1, samePrice: SAME_PRICE});

        fundLimitBidOpt(bidPrice, amount, receiver);

        uint256 discountPct;
        uint88 weightedErcAmount;
        uint80 savedPrice = uint80(diamond.getProtocolAssetPrice(asset));

        // increase discountedErcMatched to a non-zero value
        for (uint256 i = 0; i < 50; i++) {
            fundLimitAskOpt(askPrice, DEFAULT_AMOUNT, sender);
            discountPct = min((savedPrice - bidPrice).div(savedPrice), 0.05 ether) * 10; //bidPrice is used since it was on ob first
            uint256 discount = 1 ether + discountPct;
            weightedErcAmount += DEFAULT_AMOUNT.mulU88(discount);
        }

        uint104 initialDiscountedDebt = 275000000000000000000000;
        assertTrue(diamond.getAssetStruct(asset).discountedErcMatched > 0);
        assertEq(diamond.getAssetStruct(asset).discountedErcMatched, initialDiscountedDebt);

        // Match at non discounted price
        fundLimitBidOpt(savedPrice, amount, receiver);
        for (uint256 i = 0; i < 1000; i++) {
            fundLimitAskOpt(savedPrice, DEFAULT_AMOUNT, sender);
            //check that discountedErcMatched is decreased with EACH match
            assertLt(diamond.getAssetStruct(asset).discountedErcMatched, initialDiscountedDebt);
            counter++;
            // 1 wei instead of 0 to keep slot warm
            if (diamond.getAssetStruct(asset).discountedErcMatched == 1 wei) break;
            initialDiscountedDebt = diamond.getAssetStruct(asset).discountedErcMatched;
        }
        // discountedErcMatched back to zero after many matches not at discounted
        assertEq(diamond.getAssetStruct(asset).discountedErcMatched, 1 wei);
        assertEq(counter, 55);
    }
}

// @dev Split up contract because I need to seed in one instance, but not in another
contract HandlePriceDiscountIncomingBidTest is OBFixture {
    using U256 for uint256;
    using U88 for uint88;
    using U80 for uint80;

    bool SAME_PRICE = true;
    bool DIFFERENT_PRICE = false;
    uint88 amount = ERCDEBTSEED;
    // @dev These values are high because I needed to set the Asset.ercDebt high. Thus, more matches at discount needs to occur before triggering penalty
    uint256 discountCounterGt1 = 181;
    uint256 discountCounterGt2 = 166;
    uint256 discountCounterGt3 = 153;
    uint256 discountCounterGt4 = 142;
    uint256 counter;
    uint64 discountPenaltyFee;

    function setUpPricesIncomingBid(DiscountLevels discountLevel, bool samePrice)
        public
        view
        returns (uint80 askPrice, uint80 bidPrice)
    {
        uint80 savedPrice = uint80(diamond.getProtocolAssetPrice(asset));
        uint256 askMultiplier;
        uint256 bidMultiplier;
        // @dev system matches based on price of order on ob (in these cases, the ask's price)
        if (discountLevel == DiscountLevels.Gte1) {
            if (samePrice) {
                bidMultiplier = askMultiplier = 0.99 ether;
            } else {
                askMultiplier = 0.99 ether;
                bidMultiplier = 1 ether;
            }
        } else if (discountLevel == DiscountLevels.Gte2) {
            if (samePrice) {
                bidMultiplier = askMultiplier = 0.98 ether;
            } else {
                askMultiplier = 0.98 ether;
                bidMultiplier = 0.99 ether;
            }
        } else if (discountLevel == DiscountLevels.Gte3) {
            if (samePrice) {
                bidMultiplier = askMultiplier = 0.97 ether;
            } else {
                askMultiplier = 0.97 ether;
                bidMultiplier = 0.98 ether;
            }
        } else if (discountLevel == DiscountLevels.Gte4) {
            if (samePrice) {
                bidMultiplier = askMultiplier = 0.96 ether;
            } else {
                askMultiplier = 0.96 ether;
                bidMultiplier = 0.97 ether;
            }
        }

        askPrice = uint80(savedPrice.mul(askMultiplier));
        bidPrice = uint80(savedPrice.mul(bidMultiplier));
    }

    function setUp() public override {
        super.setUp();

        // @dev Make dethCollateral non zero
        fundLimitBidOpt(DEFAULT_PRICE, amount, extra);
        fundLimitShortOpt(DEFAULT_PRICE, amount, extra);

        // @dev Matching above caused Asset.discountedErcMatched = 1 wei
        if (diamond.getAssetStruct(asset).discountedErcMatched == 1 wei) diamond.setDiscountedErcMatchedAsset(asset, 0);
        discountPenaltyFee = uint64(diamond.getAssetNormalizedStruct(asset).discountPenaltyFee);
    }

    function test_handleDiscount_IsDiscounted_Gt1Pct_IncomingBid_SamePrice() public {
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, 0);
        (uint80 askPrice, uint80 bidPrice) = setUpPricesIncomingBid({discountLevel: DiscountLevels.Gte1, samePrice: SAME_PRICE});

        fundLimitAskOpt(askPrice, amount, sender);

        uint256 discountPct;
        uint88 weightedErcAmount;
        uint80 savedPrice = uint80(diamond.getProtocolAssetPrice(asset));
        for (uint256 i = 0; i < 1000; i++) {
            fundLimitBidOpt(bidPrice, DEFAULT_AMOUNT, receiver);
            discountPct = min((savedPrice - askPrice).div(savedPrice), 0.05 ether) * 10; //askPrice is used since it was on ob first
            uint256 discount = 1 ether + discountPct;
            weightedErcAmount += DEFAULT_AMOUNT.mulU88(discount);
            if (diamond.getAssetStruct(asset).ercDebtRate > 0) break;
            assertEq(diamond.getAssetStruct(asset).discountedErcMatched, weightedErcAmount);
            counter++;
        }

        // Confirm that lower discounts take longer to hit threshold
        assertEq(counter, discountCounterGt1);
        assertGt(discountCounterGt1, discountCounterGt2);

        // Fee applied
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, discountPenaltyFee);
        // Reset values
        assertEq(diamond.getAssetStruct(asset).discountedErcMatched, 1 wei);
    }

    function test_handleDiscount_IsDiscounted_Gt1Pct_IncomingBid_DifferentPrice() public {
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, 0);
        (uint80 askPrice, uint80 bidPrice) =
            setUpPricesIncomingBid({discountLevel: DiscountLevels.Gte1, samePrice: DIFFERENT_PRICE});

        fundLimitAskOpt(askPrice, amount, sender);

        uint256 discountPct;
        uint88 weightedErcAmount;
        uint80 savedPrice = uint80(diamond.getProtocolAssetPrice(asset));
        for (uint256 i = 0; i < 1000; i++) {
            fundLimitBidOpt(bidPrice, DEFAULT_AMOUNT, receiver);
            discountPct = min((savedPrice - askPrice).div(savedPrice), 0.05 ether) * 10; //askPrice is used since it was on ob first
            uint256 discount = 1 ether + discountPct;
            weightedErcAmount += DEFAULT_AMOUNT.mulU88(discount);
            if (diamond.getAssetStruct(asset).ercDebtRate > 0) break;
            assertEq(diamond.getAssetStruct(asset).discountedErcMatched, weightedErcAmount);
            counter++;
        }

        // Confirm that lower discounts take longer to hit threshold
        assertEq(counter, discountCounterGt1);
        assertGt(discountCounterGt1, discountCounterGt2);

        // Fee applied
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, discountPenaltyFee);
        // Reset values
        assertEq(diamond.getAssetStruct(asset).discountedErcMatched, 1 wei);
    }

    function test_handleDiscount_IsDiscounted_Gt2Pct_IncomingBid_SamePrice() public {
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, 0);
        (uint80 askPrice, uint80 bidPrice) = setUpPricesIncomingBid({discountLevel: DiscountLevels.Gte2, samePrice: SAME_PRICE});

        fundLimitAskOpt(askPrice, amount, sender);

        uint256 discountPct;
        uint88 weightedErcAmount;
        uint80 savedPrice = uint80(diamond.getProtocolAssetPrice(asset));
        for (uint256 i = 0; i < 1000; i++) {
            fundLimitBidOpt(bidPrice, DEFAULT_AMOUNT, receiver);
            discountPct = min((savedPrice - askPrice).div(savedPrice), 0.05 ether) * 10; //askPrice is used since it was on ob first
            uint256 discount = 1 ether + discountPct;
            weightedErcAmount += DEFAULT_AMOUNT.mulU88(discount);
            if (diamond.getAssetStruct(asset).ercDebtRate > 0) break;
            assertEq(diamond.getAssetStruct(asset).discountedErcMatched, weightedErcAmount);
            counter++;
        }

        // Confirm that lower discounts take longer to hit threshold
        assertEq(counter, discountCounterGt2);
        assertGt(discountCounterGt2, discountCounterGt3);

        // Fee applied
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, discountPenaltyFee);
        // Reset values
        assertEq(diamond.getAssetStruct(asset).discountedErcMatched, 1 wei);
    }

    function test_handleDiscount_IsDiscounted_Gt2Pct_IncomingBid_DifferentPrice() public {
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, 0);
        (uint80 askPrice, uint80 bidPrice) =
            setUpPricesIncomingBid({discountLevel: DiscountLevels.Gte2, samePrice: DIFFERENT_PRICE});

        fundLimitAskOpt(askPrice, amount, sender);

        uint256 discountPct;
        uint88 weightedErcAmount;
        uint80 savedPrice = uint80(diamond.getProtocolAssetPrice(asset));
        for (uint256 i = 0; i < 1000; i++) {
            fundLimitBidOpt(bidPrice, DEFAULT_AMOUNT, receiver);
            discountPct = min((savedPrice - askPrice).div(savedPrice), 0.05 ether) * 10; //askPrice is used since it was on ob first
            uint256 discount = 1 ether + discountPct;
            weightedErcAmount += DEFAULT_AMOUNT.mulU88(discount);
            if (diamond.getAssetStruct(asset).ercDebtRate > 0) break;
            assertEq(diamond.getAssetStruct(asset).discountedErcMatched, weightedErcAmount);
            counter++;
        }

        // Confirm that lower discounts take longer to hit threshold
        assertEq(counter, discountCounterGt2);
        assertGt(discountCounterGt2, discountCounterGt3);

        // Fee applied
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, discountPenaltyFee);
        // Reset values
        assertEq(diamond.getAssetStruct(asset).discountedErcMatched, 1 wei);
    }

    function test_handleDiscount_IsDiscounted_Gt3Pct_IncomingBid_SamePrice() public {
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, 0);
        (uint80 askPrice, uint80 bidPrice) = setUpPricesIncomingBid({discountLevel: DiscountLevels.Gte3, samePrice: SAME_PRICE});

        fundLimitAskOpt(askPrice, amount, sender);

        uint256 discountPct;
        uint88 weightedErcAmount;
        uint80 savedPrice = uint80(diamond.getProtocolAssetPrice(asset));
        for (uint256 i = 0; i < 1000; i++) {
            fundLimitBidOpt(bidPrice, DEFAULT_AMOUNT, receiver);
            discountPct = min((savedPrice - askPrice).div(savedPrice), 0.05 ether) * 10; //askPrice is used since it was on ob first
            uint256 discount = 1 ether + discountPct;
            weightedErcAmount += DEFAULT_AMOUNT.mulU88(discount);
            if (diamond.getAssetStruct(asset).ercDebtRate > 0) break;
            assertEq(diamond.getAssetStruct(asset).discountedErcMatched, weightedErcAmount);
            counter++;
        }

        // Confirm that lower discounts take longer to hit threshold
        assertEq(counter, discountCounterGt3);
        assertGt(discountCounterGt3, discountCounterGt4);

        // Fee applied
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, discountPenaltyFee);
        // Reset values
        assertEq(diamond.getAssetStruct(asset).discountedErcMatched, 1 wei);
    }

    function test_handleDiscount_IsDiscounted_Gt3Pct_IncomingBid_DifferentPrice() public {
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, 0);
        (uint80 askPrice, uint80 bidPrice) =
            setUpPricesIncomingBid({discountLevel: DiscountLevels.Gte3, samePrice: DIFFERENT_PRICE});

        fundLimitAskOpt(askPrice, amount, sender);

        uint256 discountPct;
        uint88 weightedErcAmount;
        uint80 savedPrice = uint80(diamond.getProtocolAssetPrice(asset));
        for (uint256 i = 0; i < 1000; i++) {
            fundLimitBidOpt(bidPrice, DEFAULT_AMOUNT, receiver);
            discountPct = min((savedPrice - askPrice).div(savedPrice), 0.05 ether) * 10; //askPrice is used since it was on ob first
            uint256 discount = 1 ether + discountPct;
            weightedErcAmount += DEFAULT_AMOUNT.mulU88(discount);
            if (diamond.getAssetStruct(asset).ercDebtRate > 0) break;
            assertEq(diamond.getAssetStruct(asset).discountedErcMatched, weightedErcAmount);
            counter++;
        }

        // Confirm that lower discounts take longer to hit threshold
        assertEq(counter, discountCounterGt3);
        assertGt(discountCounterGt3, discountCounterGt4);

        // Fee applied
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, discountPenaltyFee);
        // Reset values
        assertEq(diamond.getAssetStruct(asset).discountedErcMatched, 1 wei);
    }

    function test_handleDiscount_IsDiscounted_Gt4Pct_IncomingBid_SamePrice() public {
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, 0);
        (uint80 askPrice, uint80 bidPrice) = setUpPricesIncomingBid({discountLevel: DiscountLevels.Gte4, samePrice: SAME_PRICE});

        fundLimitAskOpt(askPrice, amount, sender);

        uint256 discountPct;
        uint88 weightedErcAmount;
        uint80 savedPrice = uint80(diamond.getProtocolAssetPrice(asset));
        for (uint256 i = 0; i < 1000; i++) {
            fundLimitBidOpt(bidPrice, DEFAULT_AMOUNT, receiver);
            discountPct = min((savedPrice - askPrice).div(savedPrice), 0.05 ether) * 10; //askPrice is used since it was on ob first
            uint256 discount = 1 ether + discountPct;
            weightedErcAmount += DEFAULT_AMOUNT.mulU88(discount);
            if (diamond.getAssetStruct(asset).ercDebtRate > 0) break;
            assertEq(diamond.getAssetStruct(asset).discountedErcMatched, weightedErcAmount);
            counter++;
        }

        // Confirm that lower discounts take longer to hit threshold
        assertEq(counter, discountCounterGt4);

        // Fee applied
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, discountPenaltyFee);
        // Reset values
        assertEq(diamond.getAssetStruct(asset).discountedErcMatched, 1 wei);
    }

    function test_handleDiscount_IsDiscounted_Gt4Pct_IncomingBid_DifferentPrice() public {
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, 0);
        (uint80 askPrice, uint80 bidPrice) =
            setUpPricesIncomingBid({discountLevel: DiscountLevels.Gte4, samePrice: DIFFERENT_PRICE});

        fundLimitAskOpt(askPrice, amount, sender);

        uint256 discountPct;
        uint88 weightedErcAmount;
        uint80 savedPrice = uint80(diamond.getProtocolAssetPrice(asset));
        for (uint256 i = 0; i < 1000; i++) {
            fundLimitBidOpt(bidPrice, DEFAULT_AMOUNT, receiver);
            discountPct = min((savedPrice - askPrice).div(savedPrice), 0.05 ether) * 10; //askPrice is used since it was on ob first
            uint256 discount = 1 ether + discountPct;
            weightedErcAmount += DEFAULT_AMOUNT.mulU88(discount);
            if (diamond.getAssetStruct(asset).ercDebtRate > 0) break;
            assertEq(diamond.getAssetStruct(asset).discountedErcMatched, weightedErcAmount);
            counter++;
        }

        // Confirm that lower discounts take longer to hit threshold
        assertEq(counter, discountCounterGt4);

        // Fee applied
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, discountPenaltyFee);
        // Reset values
        assertEq(diamond.getAssetStruct(asset).discountedErcMatched, 1 wei);
    }

    // @dev Discounted matches increase discountedErcMatched but non discounted matches decrease discountedErcMatched
    function test_handleDiscount_FirstIsDiscounted_IncomingBid_LaterIsNotDiscounted() public {
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, 0);
        (uint80 askPrice, uint80 bidPrice) = setUpPricesIncomingBid({discountLevel: DiscountLevels.Gte1, samePrice: SAME_PRICE});

        fundLimitAskOpt(askPrice, amount, sender);

        uint256 discountPct;
        uint88 weightedErcAmount;
        uint80 savedPrice = uint80(diamond.getProtocolAssetPrice(asset));
        // increase discountedErcMatched to a non-zero value
        for (uint256 i = 0; i < 50; i++) {
            fundLimitBidOpt(bidPrice, DEFAULT_AMOUNT, receiver);
            discountPct = min((savedPrice - askPrice).div(savedPrice), 0.05 ether) * 10; //askPrice is used since it was on ob first
            uint256 discount = 1 ether + discountPct;
            weightedErcAmount += DEFAULT_AMOUNT.mulU88(discount);
        }

        uint88 initialDiscountedDebt = 275000000000000000000000;
        assertTrue(diamond.getAssetStruct(asset).discountedErcMatched > 0);
        assertEq(diamond.getAssetStruct(asset).discountedErcMatched, initialDiscountedDebt);

        vm.prank(sender);
        cancelAsk(101);
        // Match at non discounted price
        fundLimitBidOpt(savedPrice, amount, receiver);
        for (uint256 i = 0; i < 1000; i++) {
            fundLimitAskOpt(savedPrice, DEFAULT_AMOUNT, sender);
            //check that discountedErcMatched is decreased with EACH match
            assertLt(diamond.getAssetStruct(asset).discountedErcMatched, initialDiscountedDebt);
            if (diamond.getAssetStruct(asset).discountedErcMatched == 1 wei) break;
        }

        // discountedErcMatched back to zero after many matches not at discounted
        assertEq(diamond.getAssetStruct(asset).discountedErcMatched, 1 wei);
    }
}

// @dev Split up contract because I need to seed in one instance, but not in another
contract HandlePriceDiscountGeneralTest is LiquidationHelper {
    using U256 for uint256;
    using U104 for uint104;
    using U88 for uint88;
    using U80 for uint80;

    uint88 amount = ERCDEBTSEED;
    uint64 discountPenaltyFee;

    function setUp() public override {
        super.setUp();

        // @dev Make dethCollateral non zero
        fundLimitBidOpt(DEFAULT_PRICE, amount, extra);
        fundLimitShortOpt(DEFAULT_PRICE, amount, extra);

        // @dev Matching above caused Asset.discountedErcMatched = 1 wei
        if (diamond.getAssetStruct(asset).discountedErcMatched == 1 wei) diamond.setDiscountedErcMatchedAsset(asset, 0);
        discountPenaltyFee = uint64(diamond.getAssetNormalizedStruct(asset).discountPenaltyFee);
    }

    function getPrices(uint256 discountAmount) public view returns (uint80 askPrice, uint80 bidPrice) {
        uint80 savedPrice = uint80(diamond.getProtocolAssetPrice(asset));
        askPrice = uint80(savedPrice.mul(discountAmount));
        bidPrice = uint80(savedPrice.mul(discountAmount));
    }

    function giveTAPPSRErcDebt() public {
        address liqAddress = address(123456789101112);
        assertEq(diamond.getAssetStruct(asset).ercDebt, amount); //account for short matched by extra in setUp
        //fund the TAPP to avoid socialization thing
        depositEth(tapp, 100 ether);
        assertEq(diamond.getAssetStruct(asset).ercDebt, ERCDEBTSEED);

        STypes.ShortRecord memory tappSR = getShortRecord(tapp, C.SHORT_STARTING_ID);
        assertEq(tappSR.ercDebt, 0);

        //Create SR to seed TappSR ercDEbt via liquidation
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, liqAddress);
        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, liqAddress);
        assertEq(diamond.getAssetStruct(asset).ercDebt, ERCDEBTSEED + DEFAULT_AMOUNT);

        //create ask for liquidation
        MTypes.OrderHint[] memory orderHintArray = diamond.getHintArray(asset, DEFAULT_PRICE, O.LimitAsk, 1);
        createAsk(DEFAULT_PRICE, DEFAULT_AMOUNT.mulU88(0.5 ether), C.LIMIT_ORDER, orderHintArray, extra);

        _setETH(730 ether);
        vm.startPrank(extra2);
        diamond.liquidate(asset, liqAddress, C.SHORT_STARTING_ID, shortHintArrayStorage, 0);

        tappSR = getShortRecord(tapp, C.SHORT_STARTING_ID);
        //absorbed the debt
        assertEq(tappSR.ercDebt, DEFAULT_AMOUNT.mulU88(0.5 ether));
        assertEq(getShorts().length, 0);
        assertEq(getAsks().length, 0);
        assertEq(getBids().length, 0);

        STypes.ShortRecord memory shortRecord = getShortRecord(liqAddress, C.SHORT_STARTING_ID);
        assertTrue(shortRecord.status == SR.Closed);
        //confirm global ercDebt after liquidation
        assertEq(diamond.getAssetStruct(asset).ercDebt, ERCDEBTSEED + DEFAULT_AMOUNT.mulU88(0.5 ether));

        //reset eth price
        _setETH(4000 ether);
    }

    function test_revert_matchIsDiscounted_OnlyDiamond() public {
        MTypes.HandleDiscount memory h;
        vm.expectRevert(Errors.NotDiamond.selector);
        diamond._matchIsDiscounted(h);
    }

    function test_handleDiscount_TappSRUnaffected() public {
        giveTAPPSRErcDebt();

        STypes.ShortRecord memory tappSR = getShortRecord(tapp, C.SHORT_STARTING_ID);
        assertEq(tappSR.ercDebt, DEFAULT_AMOUNT.mulU88(0.5 ether));
        assertEq(tappSR.ercDebtRate, 0);
        assertEq(diamond.getAssetStruct(asset).ercDebt, ERCDEBTSEED + DEFAULT_AMOUNT.mulU88(0.5 ether));

        //Give receiver dusd to sell
        fundLimitShortOpt(DEFAULT_PRICE, amount, sender);
        fundLimitBidOpt(DEFAULT_PRICE, amount, receiver);
        assertEq(diamond.getAssetStruct(asset).ercDebt, ERCDEBTSEED + DEFAULT_AMOUNT.mulU88(0.5 ether) + amount);

        //compare global ercDebt to total SR debt
        STypes.ShortRecord memory TappSR = diamond.getShortRecords(asset, tapp)[0];
        STypes.ShortRecord memory SenderSR = diamond.getShortRecords(asset, sender)[0];
        assertEq(diamond.getAssetStruct(asset).ercDebt, ERCDEBTSEED + TappSR.ercDebt + SenderSR.ercDebt);

        // Create discount
        (uint80 askPrice, uint80 bidPrice) = getPrices(0.96 ether);

        MTypes.OrderHint[] memory orderHintArray = diamond.getHintArray(asset, askPrice, O.LimitAsk, 1);
        createAsk(askPrice, amount, C.LIMIT_ORDER, orderHintArray, receiver);
        uint104 ercDebtMinusTapp = diamond.getAssetStruct(asset).ercDebt - tappSR.ercDebt;
        for (uint256 i = 0; i < 10000; i++) {
            fundLimitBidOpt(bidPrice, DEFAULT_AMOUNT, receiver);
            if (diamond.getAssetStruct(asset).ercDebtRate > 0) break;
        }

        // @dev Mock increase the tappSR debt to non zero (Typically tappSR's collateral and debt are impacted only by liquidation)
        depositEthAndPrank(tapp, 1 ether);
        increaseCollateral(C.SHORT_STARTING_ID, 1 wei);

        //Tapp SR's ercDebt is unnaffected by updateErcDebt()
        tappSR = getShortRecord(tapp, C.SHORT_STARTING_ID);
        assertEq(tappSR.ercDebt, DEFAULT_AMOUNT.mulU88(0.5 ether));
        assertEq(tappSR.ercDebtRate, discountPenaltyFee);

        //compare global ercDebt to total SR debt
        //Asset.ercDebt updated by newDebt, which is not affected by TAPP SR debt
        uint104 newDebt = ercDebtMinusTapp.mulU104(discountPenaltyFee);
        assertEq(diamond.getAssetStruct(asset).ercDebt, ERCDEBTSEED + TappSR.ercDebt + SenderSR.ercDebt + newDebt);
    }

    function test_handleDiscount_GlobalDebtEqSRDebt() public {
        //use this SR to check against global debt
        fundLimitShortOpt(DEFAULT_PRICE, amount, sender);
        fundLimitBidOpt(DEFAULT_PRICE, amount, receiver);

        STypes.ShortRecord memory shortRecord = getShortRecord(sender, C.SHORT_STARTING_ID);
        STypes.ShortRecord memory extraSR = getShortRecord(extra, C.SHORT_STARTING_ID);
        assertEq(shortRecord.ercDebt, amount);

        assertEq(diamond.getAssetStruct(asset).ercDebt, amount * 2); //account for short matched by extra in setUp
        assertEq(diamond.getAssetStruct(asset).ercDebt, shortRecord.ercDebt + extraSR.ercDebt);
        assertEq(token.balanceOf(_yDUSD), 0);

        (uint80 askPrice, uint80 bidPrice) = getPrices(0.96 ether);

        MTypes.OrderHint[] memory orderHintArray = diamond.getHintArray(asset, askPrice, O.LimitAsk, 1);
        createAsk(askPrice, amount, C.LIMIT_ORDER, orderHintArray, receiver);

        for (uint256 i = 0; i < 1000; i++) {
            fundLimitBidOpt(bidPrice, DEFAULT_AMOUNT, receiver);
            if (diamond.getAssetStruct(asset).ercDebtRate > 0) break;
        }

        //call updateErcDebt to increase the SR's ercDebt
        vm.prank(sender);
        decreaseCollateral(C.SHORT_STARTING_ID, 1 wei);
        vm.prank(extra);
        decreaseCollateral(C.SHORT_STARTING_ID, 1 wei);

        //check to see if global and SR debt reflects the discount
        uint88 newDebt = (amount * 2).mulU88(discountPenaltyFee);
        assertEq(newDebt, 100000000000000000000000);
        shortRecord = getShortRecord(sender, C.SHORT_STARTING_ID);
        extraSR = getShortRecord(extra, C.SHORT_STARTING_ID);
        assertEq(shortRecord.ercDebt + extraSR.ercDebt, (amount * 2) + newDebt);
        assertEq(diamond.getAssetStruct(asset).ercDebt, (amount * 2) + newDebt); //account for short matched by extra in setUp
        assertEq(diamond.getAssetStruct(asset).ercDebt, shortRecord.ercDebt + extraSR.ercDebt);

        //get the balance of yDUSD
        assertEq(token.balanceOf(_yDUSD), newDebt);
    }

    function test_handleDiscount_EarlyReturn_ErcDebtLtUpdateThreshold() public {
        (uint80 askPrice, uint80 bidPrice) = getPrices(0.96 ether);

        // Match at discount but have ercDebt be below C.DISCOUNT_UPDATE_THRESHOLD
        fundLimitBidOpt(bidPrice, uint88(C.DISCOUNT_UPDATE_THRESHOLD), receiver);
        fundLimitAskOpt(askPrice, uint88(C.DISCOUNT_UPDATE_THRESHOLD) - 1, sender);

        assertEq(diamond.getAssetStruct(asset).ercDebtRate, 0);
    }

    function resetAssetValues() public {
        diamond.setDiscountedErcMatchedAsset(asset, 0);
        diamond.setInitialDiscountTimeAsset(asset, 0);
        diamond.setErcDebtAsset(asset, 0);
        diamond.setErcDebtRateAsset(asset, 0);

        // @dev Seed the ercDebtAsset with some huge number to prevent the DISCOUNT_THRESHOLD from being applied
        diamond.addErcDebtAsset(asset, ERCDEBTSEED);

        assertEq(diamond.getAssetStruct(asset).discountedErcMatched, 0);
        assertEq(diamond.getAssetStruct(asset).initialDiscountTime, 0);
        assertEq(diamond.getAssetStruct(asset).ercDebt, ERCDEBTSEED);
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, 0);
    }

    // @dev discount should increase by 10% each day that passes and the discount is 1% or more
    function test_handleDiscount_DiscountMultiplier() public {
        // Make the protocol time > 1
        skip(1 days);
        _setETH(4000 ether);
        (uint80 askPrice, uint80 bidPrice) = getPrices(0.98 ether);

        resetAssetValues();
        // Check how long it takes to hit the threshold at 1% (no days passed)
        uint256 noDaysCounter;
        fundLimitBidOpt(bidPrice, amount, receiver);
        for (uint256 i = 0; i < 100; i++) {
            fundLimitAskOpt(askPrice, DEFAULT_AMOUNT, sender);
            if (diamond.getAssetStruct(asset).ercDebtRate > 0) break;
            noDaysCounter++;
        }
        vm.prank(receiver);
        cancelBid(100);
        resetAssetValues();

        // Check how long it takes to hit the threshold at 1% (2 days passed)
        uint256 twoDaysCounter;
        fundLimitBidOpt(bidPrice, amount, receiver);
        for (uint256 i = 0; i < 100; i++) {
            if (i == 1) {
                skip(2 days);
                _setETH(4000 ether);
            }

            fundLimitAskOpt(askPrice, DEFAULT_AMOUNT, sender);
            if (diamond.getAssetStruct(asset).ercDebtRate > 0) break;
            twoDaysCounter++;
        }

        vm.prank(receiver);
        cancelBid(100);
        assertLt(twoDaysCounter, noDaysCounter);
        resetAssetValues();

        // Check how long it takes to hit the threshold at 1% (many days passed)
        uint256 manyDaysCounter;
        fundLimitBidOpt(bidPrice, amount, receiver);
        for (uint256 i = 0; i < 100; i++) {
            skip(5 hours);
            _setETH(4000 ether);
            fundLimitAskOpt(askPrice, DEFAULT_AMOUNT, sender);
            if (diamond.getAssetStruct(asset).ercDebtRate > 0) break;
            manyDaysCounter++;
        }
        vm.prank(receiver);
        cancelBid(100);
        assertLt(manyDaysCounter, twoDaysCounter);
    }

    function test_handleDiscount_ResettingInitialDiscountTime_MatchNotAtDiscount() public {
        // Make the protocol time > 1
        skip(1 days);
        _setETH(4000 ether);
        (uint80 askPrice, uint80 bidPrice) = getPrices(0.98 ether);

        resetAssetValues();

        // Increase the initialDiscountTime to a non zero value
        fundLimitBidOpt(bidPrice, amount, receiver);
        for (uint256 i = 0; i < 10; i++) {
            fundLimitAskOpt(askPrice, DEFAULT_AMOUNT, sender);
        }
        vm.prank(receiver);
        cancelBid(100);

        assertEq(diamond.getAssetStruct(asset).initialDiscountTime, 86401);
        fundLimitBidOpt(DEFAULT_PRICE, amount, receiver);

        // Match at non discounted price
        fundLimitAskOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);

        // initialDiscountTime has been reset
        assertEq(diamond.getAssetStruct(asset).initialDiscountTime, 1 seconds);
    }

    function test_handleDiscount_ResettingInitialDiscountTime_DiscountExceeds7Days() public {
        // Make the protocol time > 1
        skip(1 days);
        _setETH(4000 ether);
        (uint80 askPrice, uint80 bidPrice) = getPrices(0.98 ether);

        resetAssetValues();

        // Increase the initialDiscountTime to a non zero value
        fundLimitBidOpt(bidPrice, amount, receiver);
        for (uint256 i = 0; i < 7; i++) {
            skip(1 days);
            _setETH(4000 ether);
            fundLimitAskOpt(askPrice, DEFAULT_AMOUNT, sender);
        }

        assertEq(diamond.getAssetStruct(asset).initialDiscountTime, 172801);

        // @dev initialDiscountTime is unchanged
        skip(1 days);
        _setETH(4000 ether);
        fundLimitAskOpt(askPrice, DEFAULT_AMOUNT, sender);
        assertEq(diamond.getAssetStruct(asset).initialDiscountTime, 172801);

        skip(1 days);
        _setETH(4000 ether);
        fundLimitAskOpt(askPrice, DEFAULT_AMOUNT, sender);
        // initialDiscountTime has been updated if timeDiff > 7 days
        assertGt(diamond.getAssetStruct(asset).initialDiscountTime, 172801);
    }

    function test_handleDiscount_SkipDiscountWhenUnderRecoveryMode() public {
        uint80 savedPrice = uint80(diamond.getProtocolAssetPrice(asset));
        // Steep discount (10% discount)
        uint80 askPrice = uint80(savedPrice.mul(0.9 ether));
        uint80 bidPrice = uint80(savedPrice.mul(0.9 ether));
        resetAssetValues();

        //Mint a ton of debt to cause Asset level CR to be low
        depositUsd(receiver, amount * 2);

        // Match at discount
        fundLimitBidOpt(bidPrice, amount * 2, receiver);
        fundLimitAskOpt(askPrice, amount * 2, sender);

        // Discounts don't trigger because the Asset CR is under recoveryMode
        uint256 assetCR = diamond.getAssetStruct(asset).dethCollateral.div(savedPrice.mul(diamond.getAssetStruct(asset).ercDebt));
        assertLe(assetCR, diamond.getAssetNormalizedStruct(asset).recoveryCR);
        assertLe(diamond.getAssetStruct(asset).initialDiscountTime, 1 wei);
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, 0);
    }

    function test_handleDiscount_ForcedBidTriggerDiscount_ExitShort() public {
        (uint80 askPrice, uint80 bidPrice) = getPrices(0.98 ether);
        resetAssetValues();

        //Create Short for sender
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);
        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, receiver);

        // Increase the initialDiscountTime to a non zero value
        fundLimitBidOpt(bidPrice, amount, receiver);
        // @dev Found 84 to be number of matches that occur before discount is triggered (trial and error)
        for (uint256 i = 0; i < 84; i++) {
            skip(1 minutes);
            setETH(4000 ether);
            fundLimitAskOpt(askPrice, DEFAULT_AMOUNT, sender);
        }

        uint104 discountedErcMatched = 504000000000000000000001;
        assertLt(
            diamond.getAssetStruct(asset).discountedErcMatched.div(diamond.getAssetStruct(asset).ercDebt), C.DISCOUNT_THRESHOLD
        );
        assertEq(diamond.getAssetStruct(asset).discountedErcMatched, discountedErcMatched);
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, 0);

        // Cancel bid to prevent next ask from matching
        vm.prank(receiver);
        cancelBid(100);

        // trigger discount via exitShort. Partial first then full
        assertEq(getShortRecordCount(sender), 1);
        fundLimitAskOpt(askPrice, DEFAULT_AMOUNT, receiver);
        vm.startPrank(sender);
        exitShort(C.SHORT_STARTING_ID, DEFAULT_AMOUNT / 2, bidPrice);
        exitShort(C.SHORT_STARTING_ID, DEFAULT_AMOUNT / 2, bidPrice);
        assertEq(getShortRecordCount(sender), 0);
        vm.stopPrank();

        // discountedErcMatched increased because the exitShort was a discounted match...
        // ...but ercDebtRate was unchanged due to early return
        assertGt(
            diamond.getAssetStruct(asset).discountedErcMatched.div(diamond.getAssetStruct(asset).ercDebt), C.DISCOUNT_THRESHOLD
        );
        assertGt(diamond.getAssetStruct(asset).discountedErcMatched, discountedErcMatched);
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, 0);
    }

    function test_handleDiscount_ForcedBidBeforeTriggerThenForcedBidTriggerDiscount_ExitShort() public {
        (uint80 askPrice, uint80 bidPrice) = getPrices(0.98 ether);
        resetAssetValues();

        //Create Shorts for sender
        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT * 2, receiver);
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);

        // Increase the initialDiscountTime to a non zero value
        fundLimitBidOpt(bidPrice, amount, receiver);

        // @dev Found 83 to be number of matches that occur 2 matches before discount is triggered (trial and error)
        for (uint256 i = 0; i < 83; i++) {
            skip(1 minutes);
            setETH(4000 ether);
            fundLimitAskOpt(askPrice, DEFAULT_AMOUNT, sender);
        }

        // Cancel bid to prevent next ask from matching
        vm.prank(receiver);
        cancelBid(100);

        uint104 discountedErcMatched0 = 498000000000000000000001;
        assertEq(diamond.getAssetStruct(asset).discountedErcMatched, discountedErcMatched0);

        // Do a forcedBid prior to triggering discount
        fundLimitAskOpt(askPrice, DEFAULT_AMOUNT * 2, receiver);
        vm.startPrank(sender);
        assertEq(getShortRecordCount(sender), 2);
        exitShort(C.SHORT_STARTING_ID, DEFAULT_AMOUNT, bidPrice);
        assertEq(getShortRecordCount(sender), 1);

        uint104 discountedErcMatched1 = 504000000000000000000001;
        // discountErcMatched increases but no discount triggered yet
        assertLt(
            diamond.getAssetStruct(asset).discountedErcMatched.div(diamond.getAssetStruct(asset).ercDebt), C.DISCOUNT_THRESHOLD
        );
        assertGt(diamond.getAssetStruct(asset).discountedErcMatched, discountedErcMatched0);
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, 0);

        // trigger discount via exitShort
        exitShort(C.SHORT_STARTING_ID + 1, DEFAULT_AMOUNT, bidPrice);
        assertEq(getShortRecordCount(sender), 0);
        vm.stopPrank();

        // discountedErcMatched increased because the exitShort was a discounted match...
        // ...but ercDebtRate was unchanged due to early return
        assertGt(
            diamond.getAssetStruct(asset).discountedErcMatched.div(diamond.getAssetStruct(asset).ercDebt), C.DISCOUNT_THRESHOLD
        );
        assertGt(diamond.getAssetStruct(asset).discountedErcMatched, discountedErcMatched1);
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, 0);
    }

    function test_handleDiscount_ForcedBidTriggerDiscount_PrimaryLiquidate() public {
        (uint80 askPrice, uint80 bidPrice) = getPrices(0.98 ether);
        resetAssetValues();

        //Create Short for sender
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);
        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, receiver);

        // Increase the initialDiscountTime to a non zero value
        fundLimitBidOpt(bidPrice, amount, receiver);
        // @dev Found 84 to be number of matches that occur before discount is triggered (trial and error)
        for (uint256 i = 0; i < 84; i++) {
            skip(1 minutes);
            setETH(4000 ether);
            fundLimitAskOpt(askPrice, DEFAULT_AMOUNT, sender);
        }

        uint104 discountedErcMatched = 504000000000000000000001;
        assertLt(
            diamond.getAssetStruct(asset).discountedErcMatched.div(diamond.getAssetStruct(asset).ercDebt), C.DISCOUNT_THRESHOLD
        );
        assertEq(diamond.getAssetStruct(asset).discountedErcMatched, discountedErcMatched);
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, 0);

        // Cancel bid to prevent next ask from matching
        vm.prank(receiver);
        cancelBid(100);

        setETH(2600 ether);
        (askPrice, bidPrice) = getPrices(0.98 ether);

        // seed tapp ethEscrowed to prevent socialization
        depositEth(tapp, FUNDED_TAPP);

        // trigger discount via primaryLiquidate. Partial first then full
        assertEq(getShortRecordCount(sender), 1);
        fundLimitAskOpt(askPrice, DEFAULT_AMOUNT / 2, receiver);
        vm.prank(receiver);
        diamond.liquidate(asset, sender, C.SHORT_STARTING_ID, shortHintArrayStorage, 0);

        setETH(1000 ether);
        (askPrice, bidPrice) = getPrices(0.98 ether);

        fundLimitAskOpt(askPrice, DEFAULT_AMOUNT / 2, receiver);
        vm.prank(receiver);
        diamond.liquidate(asset, sender, C.SHORT_STARTING_ID, shortHintArrayStorage, 0);
        assertEq(getShortRecordCount(sender), 0);

        // discountedErcMatched increased because the exitShort was a discounted match...
        // ...but ercDebtRate was unchanged due to early return
        assertGt(
            diamond.getAssetStruct(asset).discountedErcMatched.div(diamond.getAssetStruct(asset).ercDebt), C.DISCOUNT_THRESHOLD
        );
        assertGt(diamond.getAssetStruct(asset).discountedErcMatched, discountedErcMatched);
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, 0);
    }

    function test_handleDiscount_ForcedBidBeforeTriggerThenForcedBidTriggerDiscount_PrimaryLiquidate() public {
        (uint80 askPrice, uint80 bidPrice) = getPrices(0.98 ether);
        resetAssetValues();

        //Create Short for sender
        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT * 2, receiver);
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);

        // Increase the initialDiscountTime to a non zero value
        fundLimitBidOpt(bidPrice, amount, receiver);
        // @dev Found 83 to be number of matches that occur 2 matches before discount is triggered (trial and error)
        for (uint256 i = 0; i < 83; i++) {
            skip(1 minutes);
            setETH(4000 ether);
            fundLimitAskOpt(askPrice, DEFAULT_AMOUNT, sender);
        }

        // Cancel bid to prevent next ask from matching
        vm.prank(receiver);
        cancelBid(100);

        uint104 discountedErcMatched0 = 498000000000000000000001;
        assertEq(diamond.getAssetStruct(asset).discountedErcMatched, discountedErcMatched0);

        // Do a forcedBid prior to triggering discount
        fundLimitAskOpt(askPrice, DEFAULT_AMOUNT * 2, receiver);
        vm.startPrank(sender);
        assertEq(getShortRecordCount(sender), 2);
        exitShort(C.SHORT_STARTING_ID, DEFAULT_AMOUNT, bidPrice);
        assertEq(getShortRecordCount(sender), 1);
        vm.stopPrank();

        uint104 discountedErcMatched1 = 504000000000000000000001;
        // discountErcMatched increases but no discount triggered yet
        assertLt(
            diamond.getAssetStruct(asset).discountedErcMatched.div(diamond.getAssetStruct(asset).ercDebt), C.DISCOUNT_THRESHOLD
        );
        assertGt(diamond.getAssetStruct(asset).discountedErcMatched, discountedErcMatched0);
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, 0);

        setETH(2600 ether);
        (askPrice, bidPrice) = getPrices(0.98 ether);
        // seed tapp ethEscrowed to prevent socialization
        depositEth(tapp, FUNDED_TAPP);

        // trigger discount via primaryLiquidate
        assertEq(getShortRecordCount(sender), 1);
        vm.prank(receiver);
        diamond.liquidate(asset, sender, C.SHORT_STARTING_ID + 1, shortHintArrayStorage, 0);
        assertEq(getShortRecordCount(sender), 0);

        // discountedErcMatched increased because the exitShort was a discounted match...
        // ...but ercDebtRate was unchanged due to early return
        assertGt(
            diamond.getAssetStruct(asset).discountedErcMatched.div(diamond.getAssetStruct(asset).ercDebt), C.DISCOUNT_THRESHOLD
        );
        assertGt(diamond.getAssetStruct(asset).discountedErcMatched, discountedErcMatched1);
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, 0);
    }

    function test_handleDiscount_AssetLastDiscountTime() public {
        // Make the protocol time > 1
        skip(1 days - 1 seconds);
        _setETH(4000 ether);
        (uint80 askPrice, uint80 bidPrice) = getPrices(0.98 ether);
        resetAssetValues();
        assertEq(diamond.getOffsetTime(), 1 days);
        assertEq(diamond.getAssetStruct(asset).lastDiscountTime, 0);
        assertLt(diamond.getAssetStruct(asset).initialDiscountTime, 1 seconds);

        fundLimitBidOpt(bidPrice, amount, receiver);
        for (uint256 i = 0; i < 100; i++) {
            fundLimitAskOpt(askPrice, DEFAULT_AMOUNT, sender);
            if (diamond.getAssetStruct(asset).ercDebtRate > 0) break;
        }

        skip(1 days);
        _setETH(4000 ether);
        assertEq(diamond.getOffsetTime(), 2 days);
        assertEq(diamond.getAssetStruct(asset).lastDiscountTime, 1 days);
        assertEq(diamond.getAssetStruct(asset).initialDiscountTime, 1 days);

        // Match at oracle
        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, receiver);
        fundLimitAskOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);

        skip(1 days);
        assertEq(diamond.getOffsetTime(), 3 days);
        assertEq(diamond.getAssetStruct(asset).lastDiscountTime, 1 days);
        assertEq(diamond.getAssetStruct(asset).initialDiscountTime, 1 seconds);
    }
}
