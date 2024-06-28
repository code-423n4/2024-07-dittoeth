// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {U256, U88, U80} from "contracts/libraries/PRBMathHelper.sol";

import {STypes, MTypes, SR, O} from "contracts/libraries/DataTypes.sol";

import {OBFixture} from "test/utils/OBFixture.sol";
import {C} from "contracts/libraries/Constants.sol";
import {LibOrders} from "contracts/libraries/LibOrders.sol";
import {Errors} from "contracts/libraries/Errors.sol";

import {console} from "contracts/libraries/console.sol";

contract CapitalEfficiency is OBFixture {
    using U256 for uint256;
    using U88 for uint88;
    using U80 for uint80;

    function setUp() public override {
        super.setUp();

        // Allow capital efficient SR
        vm.prank(owner);
        diamond.setInitialCR(asset, 170); // 1.7
        initialCR = diamond.getAssetStruct(asset).initialCR;
    }

    function test_revert_CapitalEfficiency_InsufficientETHEscrowed() public {
        // When shortOrderCR >= initialCR, no extra funding requirements for shorter
        depositEthAndPrank(sender, DEFAULT_PRICE.mulU88(DEFAULT_AMOUNT).mulU88(diamond.getAssetNormalizedStruct(asset).initialCR));
        diamond.createLimitShort(asset, DEFAULT_PRICE, DEFAULT_AMOUNT, badOrderHintArray, shortHintArrayStorage, initialCR);

        // When shortOrderCR < initialCR, extra collateral is required to seed the SR
        uint256 shortOrderCRNormalized = diamond.getAssetNormalizedStruct(asset).initialCR - 1 ether;
        uint16 shortOrderCR = 70;
        depositEthAndPrank(sender, DEFAULT_PRICE.mulU88(DEFAULT_AMOUNT).mulU88(shortOrderCRNormalized));
        vm.expectRevert(Errors.InsufficientETHEscrowed.selector);
        diamond.createLimitShort(asset, DEFAULT_PRICE, DEFAULT_AMOUNT, badOrderHintArray, shortHintArrayStorage, shortOrderCR);
    }

    function test_CapitalEfficiency_CancelUpToMinShortErc() public {
        uint256 minShortErc = diamond.getMinShortErc(asset);
        uint88 underMinShortErc = uint88(minShortErc / 2);
        uint16 shortOrderCR = initialCR - 100; // 1.7 - 1.0 = 0.7

        // Create SR with low shortOrderCR
        depositEthAndPrank(sender, DEFAULT_AMOUNT);
        diamond.createLimitShort(asset, DEFAULT_PRICE, DEFAULT_AMOUNT, badOrderHintArray, shortHintArrayStorage, shortOrderCR);
        // Check seed collateral
        STypes.ShortRecord memory shortRecord = getShortRecord(sender, C.SHORT_STARTING_ID);
        assertEq(shortRecord.collateral, DEFAULT_PRICE.mul(diamond.getAssetNormalizedStruct(asset).minShortErc));
        assertEq(shortRecord.ercDebt, 0);

        fundLimitBid(DEFAULT_PRICE, underMinShortErc, receiver);
        shortRecord = getShortRecord(sender, C.SHORT_STARTING_ID);
        assertEq(shortRecord.ercDebt, underMinShortErc);
        // 1 ether == difference between initialCR and shortOrderCR
        uint256 intermediateCR = (1 ether) * (minShortErc / underMinShortErc) + diamond.getAssetNormalizedStruct(asset).initialCR;
        assertApproxEqAbs(diamond.getCollateralRatio(asset, shortRecord), intermediateCR, MAX_DELTA_SMALL);

        vm.prank(sender);
        cancelShort(C.STARTING_ID);

        // Ensure that a capital efficient SR when cancelled...
        shortRecord = getShortRecord(sender, C.SHORT_STARTING_ID);
        // ..still provides minShortErc
        assertEq(shortRecord.ercDebt, minShortErc);
        // ..still collateralizes minShortErc >= initialCR
        assertGe(diamond.getCollateralRatio(asset, shortRecord), diamond.getAssetNormalizedStruct(asset).initialCR);
        // Resulting CR is initialCR plus whatever was brought by the bid
        uint256 finalCR = diamond.getAssetNormalizedStruct(asset).initialCR + C.BID_CR * underMinShortErc / minShortErc;
        assertEq(diamond.getCollateralRatio(asset, shortRecord), finalCR);
    }

    // SR @ initialCR should behave exactly like SR @ initialCR-1 at minShortErc size
    function test_CapitalEfficiency_EquivalentAtMinShortErc() public {
        uint88 minShortErc = uint88(diamond.getMinShortErc(asset));
        uint16 shortOrderCR = initialCR - 100; // 1.7 - 1.0 = 0.7
        uint256 initialCRNormalized = diamond.getAssetNormalizedStruct(asset).initialCR;
        uint88 collateral = DEFAULT_PRICE.mulU88(minShortErc).mulU88(initialCRNormalized + 1 ether);

        // Create SR @ intialCR with minShortErc
        fundLimitShort(DEFAULT_PRICE, minShortErc, extra);
        // Create SR @ initialCR-1 with minShortErc
        depositEthAndPrank(sender, DEFAULT_PRICE.mulU88(minShortErc).mulU88(initialCRNormalized));
        diamond.createLimitShort(asset, DEFAULT_PRICE, minShortErc, badOrderHintArray, shortHintArrayStorage, shortOrderCR);
        // Generate ditto matched shares
        skip(C.MIN_DURATION + 1);
        setETH(4000 ether);
        // Match both SR
        fundLimitBid(DEFAULT_PRICE, minShortErc, extra);
        fundLimitBid(DEFAULT_PRICE, minShortErc, sender);

        // Check global balances
        assertEq(diamond.getAssetStruct(asset).ercDebt, minShortErc * 2);
        assertEq(diamond.getAssetStruct(asset).dethCollateral, collateral * 2);
        assertEq(diamond.getVaultStruct(vault).dethCollateral, collateral * 2);

        // Exit both SR
        exitShortErcEscrowed(C.SHORT_STARTING_ID, minShortErc, extra);
        exitShortErcEscrowed(C.SHORT_STARTING_ID, minShortErc, sender);

        // Check user balances
        assertEq(diamond.getAssetUserStruct(asset, extra).ercEscrowed, diamond.getAssetUserStruct(asset, sender).ercEscrowed);
        assertEq(diamond.getVaultUserStruct(vault, extra).ethEscrowed, diamond.getVaultUserStruct(vault, sender).ethEscrowed);
        // These are different bc collateral from ethSeed does not accrue dittoMatchedShares (no ob liquidity)
        assertGt(
            diamond.getVaultUserStruct(vault, extra).dittoMatchedShares,
            diamond.getVaultUserStruct(vault, sender).dittoMatchedShares
        );
    }

    // Capital Efficient SR has lower CR at debt levels above minShortErc
    function test_CapitalEfficiency_LowerCRAboveMinShortErc() public {
        uint256 minShortErc = diamond.getMinShortErc(asset);
        uint16 shortOrderCR = initialCR - 100; // 1.7 - 1.0 = 0.7
        uint256 initialCRNormalized = diamond.getAssetNormalizedStruct(asset).initialCR;
        uint88 collateral1 = DEFAULT_PRICE.mulU88(DEFAULT_AMOUNT).mulU88(initialCRNormalized + 1 ether);
        uint88 collateral2 = collateral1 - DEFAULT_PRICE.mulU88(DEFAULT_AMOUNT - minShortErc);
        uint88 shorterCollateral = DEFAULT_PRICE.mulU88(minShortErc).mulU88(initialCRNormalized)
            + DEFAULT_PRICE.mulU88(DEFAULT_AMOUNT - minShortErc).mulU88(initialCRNormalized - 1 ether);

        // Create SR @ intialCR
        fundLimitShort(DEFAULT_PRICE, DEFAULT_AMOUNT, extra);
        // Create SR @ initialCR-1
        depositEthAndPrank(sender, shorterCollateral);
        diamond.createLimitShort(asset, DEFAULT_PRICE, DEFAULT_AMOUNT, badOrderHintArray, shortHintArrayStorage, shortOrderCR);
        // Generate ditto matched shares
        skip(C.MIN_DURATION + 1);
        setETH(4000 ether);
        // Match both SR
        fundLimitBid(DEFAULT_PRICE, DEFAULT_AMOUNT, extra);
        fundLimitBid(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);

        // Check global balances
        assertEq(diamond.getAssetStruct(asset).ercDebt, DEFAULT_AMOUNT * 2);
        assertEq(diamond.getAssetStruct(asset).dethCollateral, collateral1 + collateral2);
        assertEq(diamond.getVaultStruct(vault).dethCollateral, collateral1 + collateral2);

        // Exit both SR
        exitShortErcEscrowed(C.SHORT_STARTING_ID, DEFAULT_AMOUNT, extra);
        exitShortErcEscrowed(C.SHORT_STARTING_ID, DEFAULT_AMOUNT, sender);

        // Check user balances
        assertEq(diamond.getAssetUserStruct(asset, extra).ercEscrowed, diamond.getAssetUserStruct(asset, sender).ercEscrowed);
        assertGt(diamond.getVaultUserStruct(vault, extra).ethEscrowed, diamond.getVaultUserStruct(vault, sender).ethEscrowed);
        // These are different bc collateral from ethSeed does not accrue dittoMatchedShares (no ob liquidity)
        assertGt(
            diamond.getVaultUserStruct(vault, extra).dittoMatchedShares,
            diamond.getVaultUserStruct(vault, sender).dittoMatchedShares
        );
    }

    // Check to prevent exploit of combining shorts to over max CR due to ethSeed
    function test_revert_CapitalEfficiency_CombinedShortsOverMaxCRUsingEthSeed() public {
        uint88 minShortErc = uint88(diamond.getMinShortErc(asset));
        uint16 highCR = 1400 - 1;
        uint16 lowCR = initialCR - 100;

        // Create SR with high CR
        depositEthAndPrank(sender, DEFAULT_AMOUNT);
        diamond.createLimitShort(asset, DEFAULT_PRICE, minShortErc, badOrderHintArray, shortHintArrayStorage, highCR); // SR2
        // Create SR with low CR beneath initialCR, attempt to use ethSeed to get around CRATIO_MAX
        badOrderHintArray.push(MTypes.OrderHint({hintId: 0, creationTime: 0}));
        vm.prank(sender);
        diamond.createLimitShort(asset, DEFAULT_PRICE, minShortErc, badOrderHintArray, shortHintArrayStorage, lowCR); // SR3
        // Match both SR
        fundLimitBid(DEFAULT_PRICE, minShortErc + 1 ether, receiver);

        // Check matches
        STypes.ShortRecord memory short = getShortRecord(sender, C.SHORT_STARTING_ID);
        assertEq(diamond.getCollateralRatio(asset, short) + 0.01 ether, C.CRATIO_MAX);
        assertTrue(short.status == SR.FullyFilled);
        short = getShortRecord(sender, C.SHORT_STARTING_ID + 1);
        assertGt(diamond.getCollateralRatio(asset, short), C.CRATIO_MAX);
        assertTrue(short.status == SR.PartialFill);

        // Attempt to combine shorts, transfer of ethSeed from SR3 to SR2 causes CR to breach threshold
        uint8[] memory shortRecords = new uint8[](2);
        shortRecords[0] = C.SHORT_STARTING_ID;
        shortRecords[1] = C.SHORT_STARTING_ID + 1;
        uint16[] memory shortOrderIds = new uint16[](2);
        shortOrderIds[0] = 0;
        shortOrderIds[1] = 101;
        vm.prank(sender);
        vm.expectRevert(Errors.CollateralHigherThanMax.selector);
        diamond.combineShorts(asset, shortRecords, shortOrderIds);
    }

    function makeCapitalEfficientSR() public returns (uint88 minShortErc) {
        minShortErc = uint88(diamond.getMinShortErc(asset));
        uint16 shortOrderCR = initialCR - 100; // 1.7 - 1.0 = 0.7
        uint88 amount = DEFAULT_AMOUNT + 1000 ether; // need extra for redemption scenario
        depositEthAndPrank(sender, amount);
        diamond.createLimitShort(asset, DEFAULT_PRICE, amount, badOrderHintArray, shortHintArrayStorage, shortOrderCR);
        fundLimitBid(DEFAULT_PRICE, minShortErc, sender);
    }

    function fullExitAsserts() public view {
        STypes.ShortRecord memory shortRecord = getShortRecord(sender, C.SHORT_STARTING_ID);
        assertTrue(shortRecord.status == SR.Closed);
        // Short Order is closed even though it has more than minShortErc because of low CR
        STypes.Order memory shortOrder = diamond.getShortOrder(asset, C.STARTING_ID);
        assertGe(shortOrder.ercAmount, diamond.getMinShortErc(asset));
        shortOrder = diamond.getShortOrder(asset, C.HEAD);
        assertEq(shortOrder.prevId, C.STARTING_ID);
    }

    function test_CapitalEfficiency_ExitShortErcEscrowed() public {
        uint88 minShortErc = makeCapitalEfficientSR();

        // Before Partial Exit
        STypes.ShortRecord memory shortRecord = getShortRecord(sender, C.SHORT_STARTING_ID);
        uint256 cRatioBeforeExit = diamond.getCollateralRatio(asset, shortRecord);
        uint256 collBeforeExit = shortRecord.collateral;
        STypes.Order memory shortOrder = diamond.getShortOrder(asset, C.STARTING_ID);
        assertTrue(shortOrder.orderType == O.LimitShort);
        // Partial Exit
        vm.prank(sender);
        diamond.exitShortErcEscrowed(asset, C.SHORT_STARTING_ID, minShortErc / 2, C.STARTING_ID);
        // After Partial Exit
        shortRecord = getShortRecord(sender, C.SHORT_STARTING_ID);
        assertGt(diamond.getCollateralRatio(asset, shortRecord), cRatioBeforeExit);
        assertEq(shortRecord.collateral, collBeforeExit); // ethSeed is untouched so partial exit is ok

        // Full Exit
        vm.prank(sender);
        diamond.exitShortErcEscrowed(asset, C.SHORT_STARTING_ID, minShortErc / 2, C.STARTING_ID);
        fullExitAsserts();
    }

    function test_CapitalEfficiency_ExitShortWallet() public {
        uint88 minShortErc = makeCapitalEfficientSR();

        // Fund wallet
        vm.prank(sender);
        diamond.withdrawAsset(asset, minShortErc);

        // Before Partial Exit
        STypes.ShortRecord memory shortRecord = getShortRecord(sender, C.SHORT_STARTING_ID);
        uint256 cRatioBeforeExit = diamond.getCollateralRatio(asset, shortRecord);
        uint256 collBeforeExit = shortRecord.collateral;
        STypes.Order memory shortOrder = diamond.getShortOrder(asset, C.STARTING_ID);
        assertTrue(shortOrder.orderType == O.LimitShort);
        // Partial Exit
        vm.prank(sender);
        diamond.exitShortWallet(asset, C.SHORT_STARTING_ID, minShortErc / 2, C.STARTING_ID);
        // After Partial Exit
        shortRecord = getShortRecord(sender, C.SHORT_STARTING_ID);
        assertGt(diamond.getCollateralRatio(asset, shortRecord), cRatioBeforeExit);
        assertEq(shortRecord.collateral, collBeforeExit); // ethSeed is untouched so partial exit is ok

        // Full Exit
        vm.prank(sender);
        diamond.exitShortWallet(asset, C.SHORT_STARTING_ID, minShortErc / 2, C.STARTING_ID);
        fullExitAsserts();
    }

    function test_CapitalEfficiency_PrimaryLiquidation() public {
        uint88 minShortErc = makeCapitalEfficientSR();

        // Set Up Partial Liquidation
        setETHChainlinkOnly(3000 ether);
        skip(15 minutes);
        fundLimitBid(DEFAULT_PRICE, minShortErc, extra);
        fundLimitAsk(DEFAULT_PRICE, minShortErc + 1000 ether, extra); // leaves 1000 ether in the ask
        // Partial Liquidation fails for capital efficient SR
        vm.prank(extra);
        vm.expectRevert(Errors.CannotLeaveDustAmount.selector);
        diamond.liquidate(asset, sender, C.SHORT_STARTING_ID, shortHintArrayStorage, C.STARTING_ID);

        // Full Liquidation
        fundLimitAsk(DEFAULT_PRICE, minShortErc, extra);
        vm.prank(extra);
        diamond.liquidate(asset, sender, C.SHORT_STARTING_ID, shortHintArrayStorage, C.STARTING_ID);
        fullExitAsserts();
    }

    function test_CapitalEfficiency_SecondaryLiquidation() public {
        uint88 minShortErc = makeCapitalEfficientSR();
        depositUsd(extra, DEFAULT_AMOUNT);

        // Secondary Liquidation (only full)
        setETHChainlinkOnly(3000 ether);
        MTypes.BatchLiquidation[] memory batches = new MTypes.BatchLiquidation[](1);
        batches[0] = MTypes.BatchLiquidation({shorter: sender, shortId: C.SHORT_STARTING_ID, shortOrderId: C.STARTING_ID});
        vm.prank(extra);
        diamond.liquidateSecondary(asset, batches, minShortErc, false);
        fullExitAsserts();
    }

    function test_CapitalEfficiency_ProposeRedemption() public {
        uint88 minShortErc = makeCapitalEfficientSR();
        fundLimitBid(DEFAULT_PRICE, minShortErc, sender); // Fill another minShortErc
        depositUsd(receiver, minShortErc);
        depositEth(receiver, MAX_REDEMPTION_FEE);
        depositUsd(extra, minShortErc);
        depositEth(extra, MAX_REDEMPTION_FEE);

        // Set Up Partial Redemption
        setETHChainlinkOnly(2500 ether);
        skip(15 minutes);
        // Partial Redemptions leaves  fails for capital efficient SR
        MTypes.ProposalInput[] memory proposalInputs = new MTypes.ProposalInput[](1);
        proposalInputs[0] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID, shortOrderId: C.STARTING_ID});
        proposeRedemption(proposalInputs, minShortErc, receiver);
        // Short Order still exists after partial redemption
        STypes.Order memory shortOrder = diamond.getShortOrder(asset, C.HEAD);
        assertEq(shortOrder.nextId, C.STARTING_ID);

        // Full Liquidation
        proposeRedemption(proposalInputs, minShortErc, extra);
        // SR is not closed (bc of pending redemption) but ercDebt is gone
        STypes.ShortRecord memory shortRecord = getShortRecord(sender, C.SHORT_STARTING_ID);
        assertEq(shortRecord.ercDebt, 0);
        // Short Order is closed even though it has more than minShortErc because of low CR
        shortOrder = diamond.getShortOrder(asset, C.STARTING_ID);
        assertGe(shortOrder.ercAmount, diamond.getMinShortErc(asset));
        shortOrder = diamond.getShortOrder(asset, C.HEAD);
        assertEq(shortOrder.prevId, C.STARTING_ID);
    }
}
