// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {U256, U104, U88, U80} from "contracts/libraries/PRBMathHelper.sol";

import {STypes, MTypes, O, SR} from "contracts/libraries/DataTypes.sol";

import {OBFixture} from "test/utils/OBFixture.sol";
import {C} from "contracts/libraries/Constants.sol";
import {Errors} from "contracts/libraries/Errors.sol";
import {Events} from "contracts/libraries/Events.sol";
import {LibBytes} from "contracts/libraries/LibBytes.sol";

import {console} from "contracts/libraries/console.sol";

import {SSTORE2} from "solmate/utils/SSTORE2.sol";

contract RedemptionTest is OBFixture {
    using U256 for uint256;
    using U104 for uint104;
    using U88 for uint88;
    using U80 for uint80;

    uint88 DEF_REDEMPTION_AMOUNT = DEFAULT_AMOUNT * 3;
    uint88 partialRedemptionAmount = DEFAULT_AMOUNT * 2 + 2000 ether;
    uint88 INITIAL_ETH_AMOUNT = 100 ether;
    bool IS_PARTIAL = true;
    bool IS_FULL = false;

    function setUp() public override {
        super.setUp();

        // @dev give potential redeemer some ethEscrowed for the fee
        depositEth(receiver, INITIAL_ETH_AMOUNT);
        depositEth(extra, INITIAL_ETH_AMOUNT);
    }

    function makeShorts(bool singleShorter) public {
        if (singleShorter) {
            fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, receiver);
            fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);
            fundLimitBidOpt(DEFAULT_PRICE + 1, DEFAULT_AMOUNT, receiver);
            fundLimitShortOpt(DEFAULT_PRICE + 1, DEFAULT_AMOUNT, sender);
            fundLimitBidOpt(DEFAULT_PRICE + 2, DEFAULT_AMOUNT, receiver);
            fundLimitShortOpt(DEFAULT_PRICE + 2, DEFAULT_AMOUNT, sender);
        } else {
            fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, receiver);
            fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);
            fundLimitBidOpt(DEFAULT_PRICE + 1, DEFAULT_AMOUNT, receiver);
            fundLimitShortOpt(DEFAULT_PRICE + 1, DEFAULT_AMOUNT, extra);
            fundLimitBidOpt(DEFAULT_PRICE + 2, DEFAULT_AMOUNT, receiver);
            fundLimitShortOpt(DEFAULT_PRICE + 2, DEFAULT_AMOUNT, extra2);
        }
    }

    function makeProposalInputs(bool singleShorter) public view returns (MTypes.ProposalInput[] memory proposalInputs) {
        proposalInputs = new MTypes.ProposalInput[](3);
        proposalInputs[0] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID, shortOrderId: 0});
        if (singleShorter) {
            proposalInputs[1] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 1, shortOrderId: 0});
            proposalInputs[2] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 2, shortOrderId: 0});
        } else {
            proposalInputs[1] = MTypes.ProposalInput({shorter: extra, shortId: C.SHORT_STARTING_ID, shortOrderId: 0});
            proposalInputs[2] = MTypes.ProposalInput({shorter: extra2, shortId: C.SHORT_STARTING_ID, shortOrderId: 0});
        }
    }

    function checkEscrowed(address redeemer, uint88 ercEscrowed) public view {
        assertEq(diamond.getAssetUserStruct(asset, redeemer).ercEscrowed, ercEscrowed);
    }

    function getSlate(address redeemer) public view returns (uint32, uint32, uint80, uint80, MTypes.ProposalData[] memory) {
        address sstore2Pointer = diamond.getAssetUserStruct(asset, redeemer).SSTORE2Pointer;
        uint8 slateLength = diamond.getAssetUserStruct(asset, redeemer).slateLength;
        (
            uint32 timeProposed,
            uint32 timeToDispute,
            uint80 oraclePrice,
            uint80 ercDebtRate,
            MTypes.ProposalData[] memory decodedProposalData
        ) = LibBytes.readProposalData(sstore2Pointer, slateLength);
        return (timeProposed, timeToDispute, oraclePrice, ercDebtRate, decodedProposalData);
    }

    function checkRedemptionSSTORE(
        address redeemer,
        MTypes.ProposalInput[] memory proposalInputs,
        bool isPartialFirst,
        bool isPartialLast
    ) public view {
        (,,,, MTypes.ProposalData[] memory decodedProposalData) = getSlate(redeemer);

        for (uint8 i = 0; i < proposalInputs.length; i++) {
            assertEq(decodedProposalData[i].shorter, proposalInputs[i].shorter);
            assertEq(decodedProposalData[i].shortId, proposalInputs[i].shortId);

            STypes.ShortRecord memory currentShort =
                diamond.getShortRecord(asset, proposalInputs[i].shorter, proposalInputs[i].shortId);

            if (i == 0 && isPartialFirst) {
                assertGt(currentShort.ercDebt, 0);
            } else if (i < proposalInputs.length - 1) {
                assertGt(decodedProposalData[i].ercDebtRedeemed, 0);
                assertEq(currentShort.ercDebt, 0);
                assertLe(decodedProposalData[i].CR, decodedProposalData[i + 1].CR);
            } else {
                uint256 lastIndex = proposalInputs.length - 1;
                if (isPartialLast) {
                    assertGt(decodedProposalData[lastIndex].ercDebtRedeemed, 0);
                    assertGt(currentShort.ercDebt, 0);
                } else {
                    assertGt(decodedProposalData[lastIndex].ercDebtRedeemed, 0);
                    assertEq(currentShort.ercDebt, 0);
                }
            }
        }
    }

    //Revert
    function test_revert_ProposalExpired() public {
        uint256 currentTime = block.timestamp;
        makeShorts({singleShorter: true});
        MTypes.ProposalInput[] memory proposalInputs = makeProposalInputs({singleShorter: true});
        address redeemer = receiver;
        _setETH(1000 ether);
        skip(1 seconds);
        vm.prank(redeemer);
        vm.expectRevert(abi.encodeWithSelector(Errors.ProposalExpired.selector, currentTime));
        diamond.proposeRedemption(asset, proposalInputs, DEFAULT_AMOUNT, MAX_REDEMPTION_FEE, currentTime);
    }

    function test_revert_TooManyProposals() public {
        uint16 len = 256;
        assertEq(len - 1, type(uint8).max);
        MTypes.ProposalInput[] memory proposalInputs = new MTypes.ProposalInput[](len);

        for (uint8 i = 0; i < len - 2; i++) {
            proposalInputs[i] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + i, shortOrderId: 0});
        }
        //add in last two
        proposalInputs[len - 2] = MTypes.ProposalInput({shorter: extra, shortId: C.SHORT_STARTING_ID, shortOrderId: 0});

        proposalInputs[len - 1] = MTypes.ProposalInput({shorter: extra, shortId: C.SHORT_STARTING_ID + 1, shortOrderId: 0});
        address redeemer = receiver;
        vm.prank(redeemer);
        vm.expectRevert(Errors.TooManyProposals.selector);
        proposeRedemption(proposalInputs, DEFAULT_AMOUNT);
    }

    function test_revert_RedemptionUnderMinShortErc() public {
        uint88 underMinShortErc = uint88(diamond.getMinShortErc(asset)) - 1;
        makeShorts({singleShorter: true});
        MTypes.ProposalInput[] memory proposalInputs = makeProposalInputs({singleShorter: true});
        address redeemer = receiver;
        _setETH(1000 ether);
        vm.prank(redeemer);
        vm.expectRevert(Errors.RedemptionUnderMinShortErc.selector);
        proposeRedemption(proposalInputs, underMinShortErc);
    }

    function test_Revert_RedemptionUnderMinShortErc_ErcDebtLowAfterProposal() public {
        address redeemer = receiver;

        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, receiver);
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);

        _setETH(1000 ether);
        MTypes.ProposalInput[] memory proposalInputs = new MTypes.ProposalInput[](1);
        proposalInputs[0] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID, shortOrderId: 0});

        uint88 amount = DEFAULT_AMOUNT - uint88(diamond.getMinShortErc(asset)) + 1;

        vm.prank(redeemer);
        vm.expectRevert(Errors.RedemptionUnderMinShortErc.selector);
        proposeRedemption(proposalInputs, amount);
    }

    function test_revert_InsufficientERCEscrowed() public {
        makeShorts({singleShorter: true});
        MTypes.ProposalInput[] memory proposalInputs = makeProposalInputs({singleShorter: true});
        address redeemer = extra;
        _setETH(1000 ether);
        vm.prank(redeemer);
        vm.expectRevert(Errors.InsufficientERCEscrowed.selector);
        proposeRedemption(proposalInputs, DEF_REDEMPTION_AMOUNT);
    }

    function test_revert_ExistingProposedRedemptions() public {
        makeShorts({singleShorter: true});
        MTypes.ProposalInput[] memory proposalInputs = makeProposalInputs({singleShorter: true});
        address redeemer = receiver;
        _setETH(1000 ether);
        proposeRedemption(proposalInputs, DEF_REDEMPTION_AMOUNT, redeemer);

        // @dev try to flag again before getting rid of existing flags
        depositUsdAndPrank(redeemer, DEF_REDEMPTION_AMOUNT);
        vm.expectRevert(Errors.ExistingProposedRedemptions.selector);
        proposeRedemption(proposalInputs, DEF_REDEMPTION_AMOUNT);
    }

    function test_revert_RedemptionFee_InsufficientETHEscrowed() public {
        makeShorts({singleShorter: true});
        MTypes.ProposalInput[] memory proposalInputs = makeProposalInputs({singleShorter: true});

        _setETH(1000 ether);
        depositUsdAndPrank(extra2, DEFAULT_AMOUNT * 3);
        vm.expectRevert(Errors.InsufficientETHEscrowed.selector);
        proposeRedemption(proposalInputs, DEF_REDEMPTION_AMOUNT);
    }

    //Non revert
    function getColRedeemed(address asset, address redeemer) public view returns (uint88 colRedeemed) {
        (,,,, MTypes.ProposalData[] memory decodedProposalData) = getSlate(redeemer);

        for (uint256 i = 0; i < decodedProposalData.length; i++) {
            colRedeemed += decodedProposalData[i].ercDebtRedeemed.mulU88(diamond.getOraclePriceT(asset));
        }
    }

    //Global Collateral and debt
    function test_proposeRedemption_GlobalVars() public {
        uint88 totalPrice = (DEFAULT_PRICE * 3 + 3) * 2;
        uint88 redemptionCollateral = DEF_REDEMPTION_AMOUNT.mulU88(totalPrice);
        address redeemer = receiver;

        makeShorts({singleShorter: true});
        MTypes.ProposalInput[] memory proposalInputs = makeProposalInputs({singleShorter: true});
        assertEq(diamond.getAssetStruct(asset).ercDebt, DEF_REDEMPTION_AMOUNT);
        assertEq(diamond.getAssetStruct(asset).dethCollateral, redemptionCollateral);
        assertEq(diamond.getVaultStruct(vault).dethCollateral, redemptionCollateral);

        _setETH(1000 ether);
        proposeRedemption(proposalInputs, DEF_REDEMPTION_AMOUNT, redeemer);

        // @dev calculated based on oracle price
        uint88 colRedeemed = getColRedeemed(asset, redeemer);

        assertEq(diamond.getAssetStruct(asset).ercDebt, 0);
        assertEq(diamond.getAssetStruct(asset).dethCollateral, redemptionCollateral - colRedeemed);
        assertEq(diamond.getVaultStruct(vault).dethCollateral, redemptionCollateral - colRedeemed);
    }

    function test_CheckSlate() public {
        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, receiver);
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);

        STypes.ShortRecord memory shortRecord = getShortRecord(sender, C.SHORT_STARTING_ID);
        MTypes.ProposalInput[] memory proposalInputs = new MTypes.ProposalInput[](1);
        proposalInputs[0] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID, shortOrderId: 0});
        testFacet.addErcDebtFee(asset, sender, C.SHORT_STARTING_ID, 1 ether);
        _setETH(1000 ether);
        uint256 cr = diamond.getCollateralRatio(asset, shortRecord);
        proposeRedemption(proposalInputs, DEFAULT_AMOUNT, receiver);
        diamond.setErcDebtRateAsset(asset, 1 ether);

        (
            uint32 timeProposed,
            uint32 timeToDispute,
            uint80 oraclePrice,
            uint80 ercDebtRate,
            MTypes.ProposalData[] memory decodedProposalData
        ) = getSlate(receiver);

        assertEq(decodedProposalData[0].shorter, sender);
        assertEq(decodedProposalData[0].shortId, shortRecord.id);
        assertEq(decodedProposalData[0].CR, cr);
        assertEq(decodedProposalData[0].colRedeemed, 5000000000000000000); //5000000000000000000 was logged in RedemptionFacet
        assertEq(decodedProposalData[0].ercDebtRedeemed, shortRecord.ercDebt);
        assertEq(decodedProposalData[0].ercDebtFee, 1 ether);

        // @dev These values were logged in RedemptionFacet
        assertEq(timeProposed, 1);
        assertEq(timeToDispute, 5401);
        assertEq(oraclePrice, 1000000000000000);
        // ercDebtRate is saved at time of proposal
        assertEq(ercDebtRate, 0);
        assertEq(diamond.getAssetStruct(asset).ercDebtRate, 1 ether);
    }

    function test_Revert_Propose_GetSavedOrSpotOraclePrice() public {
        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, receiver);
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);

        _setETH(1000 ether);
        _setETHChainlinkOnly(4000 ether);
        skip(1 hours);

        MTypes.ProposalInput[] memory proposalInputs = new MTypes.ProposalInput[](1);
        proposalInputs[0] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID, shortOrderId: 0});

        // @dev confirm that I am getting correct oraclePrice by failing
        vm.prank(receiver);
        vm.expectRevert(Errors.RedemptionUnderMinShortErc.selector);
        proposeRedemption(proposalInputs, DEFAULT_AMOUNT);

        // @dev passing now
        _setETHChainlinkOnly(1000 ether);
        proposeRedemption(proposalInputs, DEFAULT_AMOUNT, receiver);
    }

    //Skipping SRs

    function test_revert_skipRedemptions_AlreadyFullyRedeemed() public {
        makeShorts({singleShorter: true});

        //Fully propose/redeem C.SHORT_STARTING_ID + 1
        MTypes.ProposalInput[] memory proposalInputs = new MTypes.ProposalInput[](1);

        proposalInputs[0] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 1, shortOrderId: 0});

        address redeemer = receiver;
        STypes.ShortRecord memory shortRecord = getShortRecord(proposalInputs[0].shorter, proposalInputs[0].shortId);

        _setETH(1000 ether);
        proposeRedemption(proposalInputs, shortRecord.ercDebt, redeemer);
        address sstore2Pointer = diamond.getAssetUserStruct(asset, redeemer).SSTORE2Pointer;
        assertTrue(sstore2Pointer != address(0));
        shortRecord = getShortRecord(proposalInputs[0].shorter, proposalInputs[0].shortId);
        assertEq(shortRecord.ercDebt, 0);

        //Make new proposal and include a fully proposed input
        proposalInputs = makeProposalInputs({singleShorter: true});

        redeemer = extra;
        depositUsdAndPrank(redeemer, DEF_REDEMPTION_AMOUNT);
        proposeRedemption(proposalInputs, DEF_REDEMPTION_AMOUNT);
        sstore2Pointer = diamond.getAssetUserStruct(asset, redeemer).SSTORE2Pointer;
        assertFalse(sstore2Pointer == address(0));
        (,,,, MTypes.ProposalData[] memory decodedProposalData) = getSlate(redeemer);

        // @dev skip C.SHORT_STARTING_ID + 1
        assertEq(decodedProposalData.length, 2);
        assertEq(decodedProposalData[0].shortId, C.SHORT_STARTING_ID);
        assertEq(decodedProposalData[1].shortId, C.SHORT_STARTING_ID + 2);
    }

    function test_revert_skipRedemptions_AlreadyFullyRedeemed_SkipAll() public {
        makeShorts({singleShorter: true});

        //Fully propose/redeem all shorts
        MTypes.ProposalInput[] memory proposalInputs = makeProposalInputs({singleShorter: true});

        address redeemer = receiver;

        _setETH(1000 ether);
        proposeRedemption(proposalInputs, DEF_REDEMPTION_AMOUNT, redeemer);
        address sstore2Pointer = diamond.getAssetUserStruct(asset, redeemer).SSTORE2Pointer;
        assertTrue(sstore2Pointer != address(0));

        STypes.ShortRecord memory shortRecord;
        for (uint256 i = 0; i < proposalInputs.length; i++) {
            shortRecord = getShortRecord(proposalInputs[i].shorter, proposalInputs[i].shortId);

            assertEq(shortRecord.ercDebt, 0);
        }

        //Make new proposal and include the fully proposed inputs
        redeemer = extra;
        depositUsdAndPrank(redeemer, DEF_REDEMPTION_AMOUNT);
        vm.expectRevert(Errors.RedemptionUnderMinShortErc.selector);
        proposeRedemption(proposalInputs, DEF_REDEMPTION_AMOUNT);
    }

    function test_revert_skipRedemptions_ErcDebtZero() public {
        address redeemer = receiver;

        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, receiver);
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);

        _setETH(1000 ether);
        MTypes.ProposalInput[] memory proposalInputs = new MTypes.ProposalInput[](1);
        proposalInputs[0] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID, shortOrderId: 0});

        proposeRedemption(proposalInputs, DEFAULT_AMOUNT, redeemer);

        depositUsd(extra, DEFAULT_AMOUNT);
        vm.prank(extra);
        vm.expectRevert(Errors.RedemptionUnderMinShortErc.selector);
        proposeRedemption(proposalInputs, DEFAULT_AMOUNT);
    }

    function test_revert_skipRedemptions_ShortIsClosed() public {
        address redeemer = receiver;

        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, receiver);
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);

        fundLimitAskOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, receiver);
        exitShort(C.SHORT_STARTING_ID, DEFAULT_AMOUNT, DEFAULT_PRICE, sender);

        _setETH(1000 ether);
        MTypes.ProposalInput[] memory proposalInputs = new MTypes.ProposalInput[](1);
        proposalInputs[0] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID, shortOrderId: 0});

        vm.prank(redeemer);
        vm.expectRevert(Errors.RedemptionUnderMinShortErc.selector);
        proposeRedemption(proposalInputs, DEFAULT_AMOUNT);
    }

    function test_revert_skipRedemptions_CannotRedeemYourself() public {
        makeShorts({singleShorter: true});

        //Fully propose/redeem C.SHORT_STARTING_ID + 1
        MTypes.ProposalInput[] memory proposalInputs = new MTypes.ProposalInput[](1);

        proposalInputs[0] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 1, shortOrderId: 0});

        address redeemer = sender;
        STypes.ShortRecord memory shortRecord = getShortRecord(proposalInputs[0].shorter, proposalInputs[0].shortId);

        _setETH(1000 ether);
        depositUsdAndPrank(redeemer, DEF_REDEMPTION_AMOUNT);
        vm.expectRevert(Errors.RedemptionUnderMinShortErc.selector);
        proposeRedemption(proposalInputs, shortRecord.ercDebt);
    }

    function test_revert_skipRedemptions_ShorterIsTappSR() public {
        address redeemer = sender;
        depositUsd(sender, DEFAULT_AMOUNT);

        _setETH(1000 ether);
        MTypes.ProposalInput[] memory proposalInputs = new MTypes.ProposalInput[](1);
        proposalInputs[0] = MTypes.ProposalInput({shorter: tapp, shortId: C.SHORT_STARTING_ID, shortOrderId: 0});

        vm.prank(redeemer);
        vm.expectRevert(Errors.RedemptionUnderMinShortErc.selector);
        proposeRedemption(proposalInputs, DEFAULT_AMOUNT);
    }

    function test_revert_skipRedemptions_CRUnder1x() public {
        makeShorts({singleShorter: true});
        address redeemer = extra;
        depositUsd(extra, DEFAULT_AMOUNT);

        _setETH(100 ether);
        MTypes.ProposalInput[] memory proposalInputs = new MTypes.ProposalInput[](1);
        proposalInputs[0] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID, shortOrderId: 0});

        vm.prank(redeemer);
        vm.expectRevert(Errors.RedemptionUnderMinShortErc.selector);
        proposeRedemption(proposalInputs, DEFAULT_AMOUNT);
    }

    function test_revert_SkipRedemptions_ProposalInputsNotSorted() public {
        makeShorts({singleShorter: true});
        assertEq(getShortRecordCount(sender), 3);

        MTypes.ProposalInput[] memory proposalInputs = new MTypes.ProposalInput[](3);
        proposalInputs[0] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID, shortOrderId: 0});
        proposalInputs[1] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 2, shortOrderId: 0});
        proposalInputs[2] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 1, shortOrderId: 0});
        address redeemer = receiver;
        _setETH(1000 ether);
        proposeRedemption(proposalInputs, DEF_REDEMPTION_AMOUNT, redeemer);

        (,,,, MTypes.ProposalData[] memory decodedProposalData) = getSlate(redeemer);
        // @dev skipped 1 out of 3
        assertEq(decodedProposalData.length, 2);
    }

    function test_revert_SkipRedemptions_AboveMaxRedemptionCR_skipAll() public {
        makeShorts({singleShorter: true});
        assertEq(getShortRecordCount(sender), 3);
        MTypes.ProposalInput[] memory proposalInputs = makeProposalInputs({singleShorter: true});
        address redeemer = receiver;

        vm.prank(redeemer);
        vm.expectRevert(Errors.RedemptionUnderMinShortErc.selector);
        proposeRedemption(proposalInputs, DEF_REDEMPTION_AMOUNT);
    }

    function test_revert_SkipRedemptions_AboveMaxRedemptionCR_SkipSome() public {
        uint32 initialUpdatedAt = uint32(diamond.getOffsetTime());
        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, receiver);
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);
        fundLimitBidOpt(DEFAULT_PRICE + 1, DEFAULT_AMOUNT + 1, receiver);
        fundLimitShortOpt(DEFAULT_PRICE + 1, DEFAULT_AMOUNT + 1, sender);
        // @dev will skip this one
        fundLimitBidOpt(DEFAULT_PRICE * 2, DEFAULT_AMOUNT + 2, receiver);
        fundLimitShortOpt(DEFAULT_PRICE * 2, DEFAULT_AMOUNT + 2, sender);

        // All updatedAt should be the same
        STypes.ShortRecord[] memory shortRecords = diamond.getShortRecords(asset, sender);
        assertEq(shortRecords[0].updatedAt, initialUpdatedAt);
        assertEq(shortRecords[1].updatedAt, initialUpdatedAt);
        assertEq(shortRecords[2].updatedAt, initialUpdatedAt);

        MTypes.ProposalInput[] memory proposalInputs = makeProposalInputs({singleShorter: true});

        _setETH(1000 ether);
        address redeemer = receiver;
        skip(1 seconds);
        proposeRedemption(proposalInputs, DEF_REDEMPTION_AMOUNT, redeemer);

        (,,,, MTypes.ProposalData[] memory decodedProposalData) = getSlate(redeemer);
        // @dev skipped 1 out of 3
        assertEq(decodedProposalData.length, 2);
        checkEscrowed({redeemer: redeemer, ercEscrowed: DEFAULT_AMOUNT + 2});

        //check updatedAt after proposal
        shortRecords = diamond.getShortRecords(asset, sender);
        assertEq(shortRecords[0].updatedAt, initialUpdatedAt); //skipped
        assertGt(shortRecords[1].updatedAt, initialUpdatedAt);
        assertGt(shortRecords[2].updatedAt, initialUpdatedAt);
    }

    function test_revert_SkipRedemptions_ProposalAmountRemainderTooSmall_SkipLast() public {
        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, receiver);
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);
        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, receiver);
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);
        // @dev will skip this one
        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT + 1, receiver);
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT + 1, sender);
        MTypes.ProposalInput[] memory proposalInputs = makeProposalInputs({singleShorter: true});

        _setETH(1000 ether);
        address redeemer = receiver;

        uint88 amount = DEFAULT_AMOUNT * 2 + 1;
        proposeRedemption(proposalInputs, amount, redeemer);

        (,,,, MTypes.ProposalData[] memory decodedProposalData) = getSlate(redeemer);
        // @dev skipped 1 out of 3
        assertEq(decodedProposalData.length, 2);
        checkEscrowed({redeemer: redeemer, ercEscrowed: DEFAULT_AMOUNT + 1});
    }

    //proposeRedemption - general

    function test_proposeRedemption_shortOrderCancelled() public {
        // Fill shortRecord with > minShortErc, remaining shortOrder < minShortErc
        uint88 underMinShortErc = uint88(diamond.getMinShortErc(asset)) - 1;
        uint88 fillAmount = DEFAULT_AMOUNT - underMinShortErc;
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);
        fundLimitBidOpt(DEFAULT_PRICE, fillAmount, receiver);
        assertEq(diamond.getShortOrder(asset, C.STARTING_ID).ercAmount, underMinShortErc);
        assertEq(getShortRecord(sender, C.SHORT_STARTING_ID).ercDebt, fillAmount);

        MTypes.ProposalInput[] memory proposalInputs = new MTypes.ProposalInput[](1);
        address redeemer = receiver;
        _setETH(1000 ether);

        // Invalid shortOrderId
        proposalInputs[0] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID, shortOrderId: 0});
        vm.prank(redeemer);
        vm.expectRevert(Errors.RedemptionUnderMinShortErc.selector);
        proposeRedemption(proposalInputs, fillAmount);
        // Valid shortOrderId
        proposalInputs[0] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID, shortOrderId: C.STARTING_ID});
        proposeRedemption(proposalInputs, fillAmount, redeemer);

        // Verify cancelled shortOrder
        assertEq(diamond.getShortOrder(asset, C.HEAD).prevId, C.STARTING_ID);
    }

    function test_proposeRedemption_SingleShorter() public {
        makeShorts({singleShorter: true});
        assertEq(getShortRecordCount(sender), 3);

        MTypes.ProposalInput[] memory proposalInputs = makeProposalInputs({singleShorter: true});

        address redeemer = receiver;

        checkEscrowed({redeemer: redeemer, ercEscrowed: DEF_REDEMPTION_AMOUNT});

        _setETH(1000 ether);
        proposeRedemption(proposalInputs, DEF_REDEMPTION_AMOUNT, redeemer);

        checkRedemptionSSTORE(redeemer, proposalInputs, IS_FULL, IS_FULL);

        // @dev locks up ercEscrowed to use for later redemption
        checkEscrowed({redeemer: redeemer, ercEscrowed: 0});
    }

    function test_proposeRedemption_SingleShorter_Partial() public {
        makeShorts({singleShorter: true});
        assertEq(getShortRecordCount(sender), 3);

        MTypes.ProposalInput[] memory proposalInputs = makeProposalInputs({singleShorter: true});

        address redeemer = receiver;

        checkEscrowed({redeemer: redeemer, ercEscrowed: DEF_REDEMPTION_AMOUNT});

        _setETH(1000 ether);
        proposeRedemption(proposalInputs, partialRedemptionAmount, redeemer);

        checkRedemptionSSTORE(redeemer, proposalInputs, IS_FULL, IS_PARTIAL);

        // @dev locks up ercEscrowed to use for later redemption
        checkEscrowed({redeemer: redeemer, ercEscrowed: DEF_REDEMPTION_AMOUNT - partialRedemptionAmount});
    }

    function test_proposeRedemption_SingleShorter_PartialThenFull() public {
        test_proposeRedemption_SingleShorter_Partial();

        MTypes.ProposalInput[] memory proposalInputs = new MTypes.ProposalInput[](1);
        proposalInputs[0] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 2, shortOrderId: 0});

        address redeemer = extra;
        uint88 amount = DEF_REDEMPTION_AMOUNT - partialRedemptionAmount;
        depositUsd(redeemer, amount);

        proposeRedemption(proposalInputs, amount, redeemer);

        checkRedemptionSSTORE(redeemer, proposalInputs, IS_FULL, IS_FULL);

        checkEscrowed({redeemer: redeemer, ercEscrowed: 0});
    }

    function test_proposeRedemption_SingleShorter_PartialThenPartial() public {
        test_proposeRedemption_SingleShorter_Partial();

        MTypes.ProposalInput[] memory proposalInputs = new MTypes.ProposalInput[](1);
        proposalInputs[0] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 2, shortOrderId: 0});

        address redeemer = extra;
        uint88 amount = uint88(diamond.getMinShortErc(asset));
        depositUsd(redeemer, amount);

        // @dev Artificially increase debt in sender SR to ensure it meets minShortErc reqs
        assertEq(diamond.getShortRecords(asset, sender)[0].ercDebt, 3000 ether);
        diamond.setErcDebtRateAsset(asset, 1 ether); // Doubles from 3k ether to 6k ether of ercDebt
        _setETH(2000 ether);
        proposeRedemption(proposalInputs, amount, redeemer);
        assertEq(diamond.getShortRecords(asset, sender)[0].ercDebt, 4000 ether); // 6000 - 2000

        checkRedemptionSSTORE(redeemer, proposalInputs, IS_PARTIAL, IS_PARTIAL);

        checkEscrowed({redeemer: redeemer, ercEscrowed: 0});
    }

    function test_proposeRedemption_SingleShorter_PartialThenFullThenPartial() public {
        test_proposeRedemption_SingleShorter_Partial();
        // Make one more SR for sender
        _setETH(4000 ether);
        fundLimitBidOpt(DEFAULT_PRICE * 5 / 4, DEFAULT_AMOUNT, receiver); // @dev price to get correct sorting
        fundLimitShortOpt(DEFAULT_PRICE * 5 / 4, DEFAULT_AMOUNT, sender);
        _setETH(1000 ether);

        MTypes.ProposalInput[] memory proposalInputs = new MTypes.ProposalInput[](2);
        proposalInputs[0] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 2, shortOrderId: 0});
        proposalInputs[1] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 3, shortOrderId: 0});

        address redeemer = extra;
        uint88 amount = DEF_REDEMPTION_AMOUNT - partialRedemptionAmount + DEFAULT_AMOUNT / 2;
        depositUsd(redeemer, amount);

        proposeRedemption(proposalInputs, amount, redeemer);

        checkRedemptionSSTORE(redeemer, proposalInputs, IS_FULL, IS_PARTIAL);

        checkEscrowed({redeemer: redeemer, ercEscrowed: 0});
    }

    function test_proposeRedemption_SingleShorter_PartialThenFullThenFull() public {
        test_proposeRedemption_SingleShorter_Partial();
        // Make one more SR for sender
        _setETH(4000 ether);
        fundLimitBidOpt(DEFAULT_PRICE * 5 / 4, DEFAULT_AMOUNT, receiver); // @dev price to get correct sorting
        fundLimitShortOpt(DEFAULT_PRICE * 5 / 4, DEFAULT_AMOUNT, sender);
        _setETH(1000 ether);

        MTypes.ProposalInput[] memory proposalInputs = new MTypes.ProposalInput[](2);
        proposalInputs[0] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 2, shortOrderId: 0});
        proposalInputs[1] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 3, shortOrderId: 0});

        address redeemer = extra;
        uint88 amount = DEF_REDEMPTION_AMOUNT - partialRedemptionAmount + DEFAULT_AMOUNT;
        depositUsd(redeemer, amount);

        proposeRedemption(proposalInputs, amount, redeemer);

        checkRedemptionSSTORE(redeemer, proposalInputs, IS_FULL, IS_FULL);

        checkEscrowed({redeemer: redeemer, ercEscrowed: 0});
    }

    function test_proposeRedemption_MultipleShorters() public {
        makeShorts({singleShorter: false});
        assertEq(getShortRecordCount(sender), 1);
        assertEq(getShortRecordCount(extra), 1);
        assertEq(getShortRecordCount(extra2), 1);

        MTypes.ProposalInput[] memory proposalInputs = makeProposalInputs({singleShorter: false});

        address redeemer = receiver;

        checkEscrowed({redeemer: redeemer, ercEscrowed: DEF_REDEMPTION_AMOUNT});

        _setETH(1000 ether);
        proposeRedemption(proposalInputs, DEF_REDEMPTION_AMOUNT, redeemer);

        checkRedemptionSSTORE(redeemer, proposalInputs, IS_FULL, IS_FULL);

        // @dev locks up ercEscrowed to use for later redemption
        checkEscrowed({redeemer: redeemer, ercEscrowed: 0});
    }

    function test_proposeRedemption_MultipleShorters_Partial() public {
        makeShorts({singleShorter: false});
        assertEq(getShortRecordCount(sender), 1);
        assertEq(getShortRecordCount(extra), 1);
        assertEq(getShortRecordCount(extra2), 1);

        MTypes.ProposalInput[] memory proposalInputs = makeProposalInputs({singleShorter: false});

        address redeemer = receiver;

        checkEscrowed({redeemer: redeemer, ercEscrowed: DEF_REDEMPTION_AMOUNT});

        _setETH(1000 ether);
        proposeRedemption(proposalInputs, partialRedemptionAmount, redeemer);

        checkRedemptionSSTORE(redeemer, proposalInputs, IS_FULL, IS_PARTIAL);

        // @dev locks up ercEscrowed to use for later redemption
        checkEscrowed({redeemer: redeemer, ercEscrowed: DEF_REDEMPTION_AMOUNT - partialRedemptionAmount});
    }

    //proposeRedemption - timeToDispute

    // @dev 1.1 ether < CR <= 1.2 ether
    function test_proposeRedemption_TimeToDispute_1() public {
        makeShorts({singleShorter: true});
        MTypes.ProposalInput[] memory proposalInputs = makeProposalInputs({singleShorter: true});

        address redeemer = receiver;

        _setETH(750 ether);
        proposeRedemption(proposalInputs, DEF_REDEMPTION_AMOUNT, redeemer);

        (, uint32 timeToDispute,,, MTypes.ProposalData[] memory decodedProposalData) = getSlate(redeemer);
        uint64 highestCR = decodedProposalData[decodedProposalData.length - 1].CR;
        assertGt(highestCR, 1.1 ether);
        assertLe(highestCR, 1.2 ether);
        assertEq(timeToDispute, 301 seconds); // @dev time already skipped 1 second in set up
        assertGt(timeToDispute, 0 hours);
        assertLe(timeToDispute, 0.33 hours);

        //try to claim
        vm.startPrank(redeemer);

        skip(299 seconds);
        vm.expectRevert(Errors.TimeToDisputeHasNotElapsed.selector);
        diamond.claimRedemption(asset);
        skip(1 seconds);
        diamond.claimRedemption(asset);
    }

    // @dev 1.2 ether < CR <= 1.3 ether
    function test_proposeRedemption_TimeToDispute_2() public {
        makeShorts({singleShorter: true});
        MTypes.ProposalInput[] memory proposalInputs = makeProposalInputs({singleShorter: true});

        address redeemer = receiver;

        _setETH(800 ether);
        proposeRedemption(proposalInputs, DEF_REDEMPTION_AMOUNT, redeemer);

        (, uint32 timeToDispute,,, MTypes.ProposalData[] memory decodedProposalData) = getSlate(redeemer);
        uint64 highestCR = decodedProposalData[decodedProposalData.length - 1].CR;
        assertGt(highestCR, 1.2 ether);
        assertLe(highestCR, 1.3 ether);
        assertEq(timeToDispute, 1201 seconds); // @dev time already skipped 1 second in set up
        assertGt(timeToDispute, 0.33 hours);
        assertLe(timeToDispute, 0.75 hours);

        //try to claim
        vm.startPrank(redeemer);
        skip(1199 seconds);
        vm.expectRevert(Errors.TimeToDisputeHasNotElapsed.selector);
        diamond.claimRedemption(asset);
        skip(1 seconds);
        diamond.claimRedemption(asset);
    }

    // @dev 1.3 ether < CR <= 1.5 ether
    function test_proposeRedemption_TimeToDispute_3() public {
        makeShorts({singleShorter: true});
        MTypes.ProposalInput[] memory proposalInputs = makeProposalInputs({singleShorter: true});

        address redeemer = receiver;

        _setETH(900 ether);
        proposeRedemption(proposalInputs, DEF_REDEMPTION_AMOUNT, redeemer);

        (, uint32 timeToDispute,,, MTypes.ProposalData[] memory decodedProposalData) = getSlate(redeemer);
        uint64 highestCR = decodedProposalData[decodedProposalData.length - 1].CR;
        assertGt(highestCR, 1.3 ether);
        assertLe(highestCR, 1.5 ether);
        assertEq(timeToDispute, 3376 seconds); // @dev time already skipped 1 second in set up
        assertGt(timeToDispute, 0.75 hours);
        assertLe(timeToDispute, 1.5 hours);

        //try to claim
        vm.startPrank(redeemer);
        skip(3374 seconds);
        vm.expectRevert(Errors.TimeToDisputeHasNotElapsed.selector);
        diamond.claimRedemption(asset);
        skip(1 seconds);
        diamond.claimRedemption(asset);
    }

    // @dev 1.5 ether < CR <= 1.7 ether
    function test_proposeRedemption_TimeToDispute_4() public {
        makeShorts({singleShorter: true});
        MTypes.ProposalInput[] memory proposalInputs = makeProposalInputs({singleShorter: true});

        address redeemer = receiver;

        _setETH(1100 ether);
        proposeRedemption(proposalInputs, DEF_REDEMPTION_AMOUNT, redeemer);

        (, uint32 timeToDispute,,, MTypes.ProposalData[] memory decodedProposalData) = getSlate(redeemer);
        uint64 highestCR = decodedProposalData[decodedProposalData.length - 1].CR;
        assertGt(highestCR, 1.5 ether);
        assertLe(highestCR, 1.7 ether);
        assertEq(timeToDispute, 9451 seconds); // @dev time already skipped 1 second in set up
        assertGt(timeToDispute, 1.5 hours);
        assertLe(timeToDispute, 3 hours);

        //try to claim
        vm.startPrank(redeemer);
        skip(9449 seconds);
        vm.expectRevert(Errors.TimeToDisputeHasNotElapsed.selector);
        diamond.claimRedemption(asset);
        skip(1 seconds);
        diamond.claimRedemption(asset);
    }

    // @dev 1.7 ether < CR <= 2 ether
    function test_proposeRedemption_TimeToDispute_5() public {
        makeShorts({singleShorter: true});
        MTypes.ProposalInput[] memory proposalInputs = makeProposalInputs({singleShorter: true});

        address redeemer = receiver;

        _setETH(1300 ether);
        proposeRedemption(proposalInputs, DEF_REDEMPTION_AMOUNT, redeemer);

        (, uint32 timeToDispute,,, MTypes.ProposalData[] memory decodedProposalData) = getSlate(redeemer);
        uint64 highestCR = decodedProposalData[decodedProposalData.length - 1].CR;
        assertGt(highestCR, 1.7 ether);
        assertLe(highestCR, 2 ether);
        assertEq(timeToDispute, 19801 seconds); // @dev time already skipped 1 second in set up
        assertGt(timeToDispute, 3 hours);
        assertLe(timeToDispute, 6 hours);

        //try to claim
        vm.startPrank(redeemer);
        skip(19799 seconds);
        vm.expectRevert(Errors.TimeToDisputeHasNotElapsed.selector);
        diamond.claimRedemption(asset);
        skip(1 seconds);
        diamond.claimRedemption(asset);
    }

    // @dev 1.7 ether < CR <= 2 ether
    // @dev Idea from Code4rena, prevent low CR at end of proposal exploit
    function test_proposeRedemption_TimeToDispute_1b() public {
        makeShorts({singleShorter: true});
        MTypes.ProposalInput[] memory proposalInputs = makeProposalInputs({singleShorter: true});

        address redeemer = receiver;

        // Make last SR low CR
        uint88 decreaseAmt = uint88(DEFAULT_PRICE.mul(DEFAULT_AMOUNT));
        vm.prank(sender);
        diamond.decreaseCollateral(asset, C.SHORT_STARTING_ID + 2, decreaseAmt);

        _setETH(750 ether);
        assertLt(diamond.getCollateralRatio(asset, getShortRecord(sender, C.SHORT_STARTING_ID + 2)), 1 ether);
        proposeRedemption(proposalInputs, DEF_REDEMPTION_AMOUNT, redeemer);

        (, uint32 timeToDispute,,, MTypes.ProposalData[] memory decodedProposalData) = getSlate(redeemer);
        uint64 highestCR = decodedProposalData[decodedProposalData.length - 1].CR;
        assertGt(highestCR, 1.1 ether);
        assertLe(highestCR, 1.2 ether);
        assertEq(timeToDispute, 301 seconds); // @dev time already skipped 1 second in set up
        assertGt(timeToDispute, 0 hours);
        assertLe(timeToDispute, 0.33 hours);

        //try to claim
        vm.startPrank(redeemer);

        skip(299 seconds);
        vm.expectRevert(Errors.TimeToDisputeHasNotElapsed.selector);
        diamond.claimRedemption(asset);
        skip(1 seconds);
        diamond.claimRedemption(asset);
    }

    // @dev CR under 1.1x can be immediately claimed on
    function test_proposeRedemption_TimeToDispute_LowCR() public {
        makeShorts({singleShorter: true});
        MTypes.ProposalInput[] memory proposalInputs = makeProposalInputs({singleShorter: true});

        address redeemer = receiver;

        _setETH(700 ether);
        proposeRedemption(proposalInputs, DEF_REDEMPTION_AMOUNT, redeemer);

        (, uint32 timeToDispute,,, MTypes.ProposalData[] memory decodedProposalData) = getSlate(redeemer);
        uint64 highestCR = decodedProposalData[decodedProposalData.length - 1].CR;
        assertLe(highestCR, 1.1 ether);
        assertEq(timeToDispute, 0);

        // @dev immediately claim
        vm.startPrank(redeemer);
        diamond.claimRedemption(asset);
    }

    function test_proposeRedemption_TimeToDispute_5_ThenLowCR() public {
        test_proposeRedemption_TimeToDispute_5();

        _setETH(4000 ether);

        makeShorts({singleShorter: true});
        MTypes.ProposalInput[] memory proposalInputs = makeProposalInputs({singleShorter: true});

        address redeemer = receiver;

        _setETH(700 ether);
        proposeRedemption(proposalInputs, DEF_REDEMPTION_AMOUNT, redeemer);

        (, uint32 timeToDispute,,, MTypes.ProposalData[] memory decodedProposalData) = getSlate(redeemer);
        uint64 highestCR = decodedProposalData[decodedProposalData.length - 1].CR;
        assertLe(highestCR, 1.1 ether);
        assertEq(timeToDispute, 0); // @dev timeToDispute is overwritten for each new slate

        // @dev immediately claim
        vm.startPrank(redeemer);
        diamond.claimRedemption(asset);
    }

    function test_proposeRedemption_SkipSRsWithLeftoverDebtUnderMinShortErc() public {
        makeShorts({singleShorter: true});

        // @dev Propose a bunch and leave the last SR in the slate under minShortErc
        MTypes.ProposalInput[] memory proposalInputs = makeProposalInputs({singleShorter: true});
        address redeemer = receiver;
        address shorter = sender;
        checkEscrowed({redeemer: redeemer, ercEscrowed: DEF_REDEMPTION_AMOUNT});
        _setETH(1000 ether);

        //Pre propose check
        STypes.ShortRecord[] memory shortRecords = diamond.getShortRecords(asset, shorter);
        assertEq(shortRecords.length, 3);
        assertEq(shortRecords[0].ercDebt, 5000 ether);
        assertEq(shortRecords[1].ercDebt, 5000 ether);
        assertEq(shortRecords[2].ercDebt, 5000 ether);

        proposeRedemption(proposalInputs, DEF_REDEMPTION_AMOUNT - 1999 ether, redeemer);

        // @dev SR under minShortErc is untouched
        shortRecords = diamond.getShortRecords(asset, shorter);
        assertEq(shortRecords.length, 3);
        assertEq(shortRecords[0].ercDebt, 5000 ether);
        assertEq(shortRecords[1].ercDebt, 0);
        assertEq(shortRecords[2].ercDebt, 0);
        (,,,, MTypes.ProposalData[] memory decodedProposalData) = getSlate(redeemer);
        assertEq(decodedProposalData.length, 2);
    }

    //Move to another file
    //SSTORE2
    function test_WriteRead() public {
        bytes memory testBytes = abi.encode("this is a test");
        address pointer = SSTORE2.write(testBytes);
        assertEq(SSTORE2.read(pointer), testBytes);
    }

    function test_WriteReadStruct() public {
        MTypes.ProposalInput memory proposalInput =
            MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID, shortOrderId: 0});

        bytes memory testBytes = abi.encode(proposalInput);

        address pointer = SSTORE2.write(testBytes);

        assertEq(SSTORE2.read(pointer), testBytes);
    }

    function test_WriteReadStructArrayDecode() public {
        MTypes.ProposalInput[] memory proposalInputs = makeProposalInputs({singleShorter: true});
        bytes memory testBytes = abi.encode(proposalInputs);

        address sstore2Pointer = SSTORE2.write(testBytes);
        MTypes.ProposalInput[] memory decodedProposalInputs = abi.decode(SSTORE2.read(sstore2Pointer), (MTypes.ProposalInput[]));
        assertEq(SSTORE2.read(sstore2Pointer), testBytes);

        for (uint8 i = 0; i < proposalInputs.length; i++) {
            assertEq(decodedProposalInputs[i].shorter, proposalInputs[i].shorter);
            assertEq(decodedProposalInputs[i].shortId, proposalInputs[i].shortId);
        }
    }

    function test_ReadStartEndBytes() public {
        uint256[] memory testArray = new uint256[](3);
        testArray[0] = 732 ether;
        testArray[1] = 4 ether;
        testArray[2] = 5 ether;

        bytes memory testBytes = abi.encode(testArray);
        address pointer = SSTORE2.write(testBytes);
        // uint256 bytez = 256 / 8;
        // uint256 decodedData = abi.decode(SSTORE2.read(pointer, 0, bytez), (uint256));
        // uint256[] memory decodedData =
        //     abi.decode(SSTORE2.read(pointer, 0, bytez * 2), (uint256[]));
        // console.logBytes(SSTORE2.read(pointer, 0, bytez));
        console.logBytes(SSTORE2.read(pointer));
    }

    function test_CannotUpdateSRThatHasNoErcDebt() public {
        //full redeem
        test_proposeRedemption_SingleShorter();
        address shorter = sender;

        STypes.ShortRecord[] memory shortRecords = diamond.getShortRecords(asset, shorter);
        assertEq(shortRecords.length, 3);
        for (uint256 i = 0; i < shortRecords.length; i++) {
            assertEq(shortRecords[i].ercDebt, 0);
        }

        // @dev Preparing things for the tests ahead
        uint16[] memory shortHintArray = setShortHintArray();
        MTypes.BatchLiquidation[] memory batches = new MTypes.BatchLiquidation[](1);
        batches[0] = MTypes.BatchLiquidation({shorter: shorter, shortId: C.SHORT_STARTING_ID, shortOrderId: 0});

        // @dev Revert tests
        vm.expectRevert(Errors.InvalidShortId.selector);
        exitShortWallet(C.SHORT_STARTING_ID, DEFAULT_AMOUNT, shorter);

        vm.expectRevert(Errors.InvalidShortId.selector);
        exitShortErcEscrowed(C.SHORT_STARTING_ID, DEFAULT_AMOUNT, shorter);

        vm.prank(shorter);
        vm.expectRevert(Errors.InvalidShortId.selector);
        diamond.exitShort(asset, C.SHORT_STARTING_ID, DEFAULT_AMOUNT, DEFAULT_PRICE, shortHintArray, 0);

        depositEthAndPrank(sender, DEFAULT_AMOUNT);
        vm.expectRevert(Errors.InvalidShortId.selector);
        increaseCollateral(C.SHORT_STARTING_ID, 1 wei);

        vm.prank(shorter);
        vm.expectRevert(Errors.InvalidShortId.selector);
        decreaseCollateral(C.SHORT_STARTING_ID, 1 wei);

        vm.prank(receiver);
        vm.expectRevert(Errors.InvalidShortId.selector);
        diamond.liquidate(asset, shorter, C.SHORT_STARTING_ID, shortHintArrayStorage, 0);

        vm.prank(shorter);
        vm.expectRevert(Errors.InvalidShortId.selector);
        combineShorts({id1: C.SHORT_STARTING_ID, id2: C.SHORT_STARTING_ID + 1});
    }

    function test_proposeRedemption_Event() public {
        makeShorts({singleShorter: true});
        MTypes.ProposalInput[] memory proposalInputs = makeProposalInputs({singleShorter: true});

        address redeemer = receiver;

        _setETH(1000 ether);
        vm.expectEmit(_diamond);
        emit Events.ProposeRedemption(asset, redeemer);
        proposeRedemption(proposalInputs, DEF_REDEMPTION_AMOUNT, redeemer);
    }
    ///////////////////////////////////////////////////////////////////////////
    //Dispute Redemptions

    function makeProposalInputsForDispute(uint8 shortId1, uint8 shortId2)
        public
        view
        returns (MTypes.ProposalInput[] memory proposalInputs)
    {
        proposalInputs = new MTypes.ProposalInput[](2);

        proposalInputs[0] = MTypes.ProposalInput({shorter: sender, shortId: shortId1, shortOrderId: 0});
        // @dev dispute this redemption
        proposalInputs[1] = MTypes.ProposalInput({shorter: sender, shortId: shortId2, shortOrderId: 0});
    }

    function setETHAndProposeShorts(address redeemer, MTypes.ProposalInput[] memory proposalInputs, uint88 redemptionAmount)
        public
    {
        _setETH(1000 ether);
        proposeRedemption(proposalInputs, redemptionAmount, redeemer);
    }

    // @dev used to test the 1 hr buffer period
    function changeUpdateAtAndSkipTime(uint8 shortId) public {
        vm.prank(sender);
        decreaseCollateral(shortId, 1 wei);
        skip(1 hours);
    }

    function computeRefundAndTappFee(
        uint104 redemptionAmount,
        MTypes.ProposalData memory highestCRInput,
        STypes.ShortRecord memory correctSR
    ) public view returns (uint88 refundAmt, uint88 tappFee) {
        uint256 callerFeePct = diamond.getAssetNormalizedStruct(asset).callerFeePct;
        uint256 correctCR = diamond.getCollateralRatio(asset, correctSR);
        uint256 penaltyPct = min(max(callerFeePct, (highestCRInput.CR - correctCR).div(highestCRInput.CR)), C.ONE_THIRD);
        refundAmt = uint88(redemptionAmount.mulU104(penaltyPct));
        tappFee = uint88(redemptionAmount.mulU104(diamond.getAssetNormalizedStruct(asset).tappFeePct));
    }

    function test_Revert_CannotDisputeYourself() public {
        address redeemer = receiver;
        makeShorts({singleShorter: true});

        address disputer = receiver;

        vm.prank(disputer);
        vm.expectRevert(Errors.CannotDisputeYourself.selector);
        diamond.disputeRedemption({
            asset: asset,
            redeemer: redeemer,
            incorrectIndex: 1,
            disputeShorter: sender,
            disputeShortId: C.SHORT_STARTING_ID
        });
    }

    function test_Revert_InvalidRedemption_NoProposal() public {
        address redeemer = receiver;
        makeShorts({singleShorter: true});

        address disputer = extra;

        vm.prank(disputer);
        vm.expectRevert(Errors.InvalidRedemption.selector);
        diamond.disputeRedemption({
            asset: asset,
            redeemer: redeemer,
            incorrectIndex: 1,
            disputeShorter: sender,
            disputeShortId: C.SHORT_STARTING_ID
        });
    }

    function test_Revert_InvalidRedemption_ClosedSR() public {
        makeShorts({singleShorter: true});
        address redeemer = receiver;
        address disputer = extra;
        uint88 _redemptionAmounts = DEFAULT_AMOUNT * 2;

        MTypes.ProposalInput[] memory proposalInputs =
            makeProposalInputsForDispute({shortId1: C.SHORT_STARTING_ID, shortId2: C.SHORT_STARTING_ID + 1});

        setETHAndProposeShorts({redeemer: redeemer, proposalInputs: proposalInputs, redemptionAmount: _redemptionAmounts});

        // Close C.SHORT_STARTING_ID + 2
        depositUsd(sender, DEFAULT_AMOUNT);
        vm.prank(sender);
        diamond.exitShortErcEscrowed(asset, C.SHORT_STARTING_ID + 2, DEFAULT_AMOUNT, 0);
        assertSR(getShortRecord(sender, C.SHORT_STARTING_ID + 2).status, SR.Closed);

        vm.prank(disputer);
        vm.expectRevert(Errors.InvalidRedemption.selector);
        diamond.disputeRedemption({
            asset: asset,
            redeemer: redeemer,
            incorrectIndex: 1,
            disputeShorter: sender,
            disputeShortId: C.SHORT_STARTING_ID + 2
        });
    }

    function test_Revert_TimeToDisputeHasElapsed() public {
        uint88 _redemptionAmounts = DEFAULT_AMOUNT + DEFAULT_AMOUNT + 2;
        makeShorts({singleShorter: true});

        MTypes.ProposalInput[] memory proposalInputs =
            makeProposalInputsForDispute({shortId1: C.SHORT_STARTING_ID, shortId2: C.SHORT_STARTING_ID + 2});

        address redeemer = receiver;

        setETHAndProposeShorts({redeemer: redeemer, proposalInputs: proposalInputs, redemptionAmount: _redemptionAmounts});

        address disputer = extra;

        diamond.setErcDebt({asset: asset, shorter: sender, id: C.SHORT_STARTING_ID, value: 1 wei});
        (, uint32 timeToDispute,,,) = getSlate(redeemer);
        skip(timeToDispute);

        vm.prank(disputer);
        vm.expectRevert(Errors.TimeToDisputeHasElapsed.selector);
        diamond.disputeRedemption({
            asset: asset,
            redeemer: redeemer,
            incorrectIndex: 1,
            disputeShorter: sender,
            disputeShortId: C.SHORT_STARTING_ID + 2
        });
    }

    function test_Revert_InvalidRedemption_UnderMinShortErc() public {
        makeShorts({singleShorter: true});
        address redeemer = receiver;
        address disputer = extra;
        uint88 _redemptionAmounts = DEFAULT_AMOUNT * 2;

        MTypes.ProposalInput[] memory proposalInputs =
            makeProposalInputsForDispute({shortId1: C.SHORT_STARTING_ID, shortId2: C.SHORT_STARTING_ID + 1});

        // Create SR with coll < minShortErc
        uint88 underMinShortErc = uint88(diamond.getMinShortErc(asset)) - 1;
        fundLimitBidOpt(DEFAULT_PRICE + 3, underMinShortErc, receiver);
        fundLimitShortOpt(DEFAULT_PRICE + 3, DEFAULT_AMOUNT, sender);
        assertEq(getShortRecord(sender, C.SHORT_STARTING_ID + 3).ercDebt, underMinShortErc);

        setETHAndProposeShorts({redeemer: redeemer, proposalInputs: proposalInputs, redemptionAmount: _redemptionAmounts});

        vm.prank(disputer);
        vm.expectRevert(Errors.InvalidRedemption.selector);
        diamond.disputeRedemption({
            asset: asset,
            redeemer: redeemer,
            incorrectIndex: 1,
            disputeShorter: sender,
            disputeShortId: C.SHORT_STARTING_ID + 3
        });
    }

    function test_Revert_InvalidRedemption_ProposerOwnSR() public {
        makeShorts({singleShorter: true});
        address redeemer = receiver;
        address disputer = extra;
        uint88 _redemptionAmounts = DEFAULT_AMOUNT * 2;

        MTypes.ProposalInput[] memory proposalInputs =
            makeProposalInputsForDispute({shortId1: C.SHORT_STARTING_ID, shortId2: C.SHORT_STARTING_ID + 1});

        // Create SR from proposer
        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, receiver);
        assertEq(getShortRecord(receiver, C.SHORT_STARTING_ID).ercDebt, DEFAULT_AMOUNT);

        setETHAndProposeShorts({redeemer: redeemer, proposalInputs: proposalInputs, redemptionAmount: _redemptionAmounts});

        vm.prank(disputer);
        vm.expectRevert(Errors.InvalidRedemption.selector);
        diamond.disputeRedemption({
            asset: asset,
            redeemer: redeemer,
            incorrectIndex: 1,
            disputeShorter: receiver,
            disputeShortId: C.SHORT_STARTING_ID
        });
    }

    function test_Revert_InvalidRedemption_CannotDisputeWithTappSR() public {
        makeShorts({singleShorter: true});
        address redeemer = receiver;
        address disputer = extra;
        uint88 _redemptionAmounts = DEFAULT_AMOUNT * 2;
        uint80 initialCollateral = DEFAULT_PRICE.mulU80(DEFAULT_AMOUNT) * 6;

        // Give tapp SR debt and collateral so CR is not under 1x
        depositEth(tapp, 1000 ether);
        depositUsd(tapp, DEFAULT_AMOUNT);
        diamond.setErcDebt(asset, tapp, C.SHORT_STARTING_ID, DEFAULT_AMOUNT);
        vm.prank(tapp);
        increaseCollateral(C.SHORT_STARTING_ID, initialCollateral);

        MTypes.ProposalInput[] memory proposalInputs =
            makeProposalInputsForDispute({shortId1: C.SHORT_STARTING_ID, shortId2: C.SHORT_STARTING_ID + 1});

        // Create SR from proposer
        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, receiver);
        assertEq(getShortRecord(receiver, C.SHORT_STARTING_ID).ercDebt, DEFAULT_AMOUNT);

        setETHAndProposeShorts({redeemer: redeemer, proposalInputs: proposalInputs, redemptionAmount: _redemptionAmounts});

        vm.prank(disputer);
        vm.expectRevert(Errors.InvalidRedemption.selector);
        diamond.disputeRedemption({
            asset: asset,
            redeemer: redeemer,
            incorrectIndex: 1,
            disputeShorter: tapp,
            disputeShortId: C.SHORT_STARTING_ID
        });
    }

    function test_Revert_InvalidRedemption_CannotDisputeWithCRUnder1x() public {
        //make very low CR short to dispute with
        _setETH(10000 ether);
        fundLimitShortOpt(0.0001 ether, DEFAULT_AMOUNT, extra);
        fundLimitBidOpt(0.0001 ether, DEFAULT_AMOUNT, receiver);
        assertEq(diamond.getShortRecords(asset, extra).length, 1);

        // Set price back to normal
        _setETH(4000 ether);

        makeShorts({singleShorter: true});
        address redeemer = receiver;
        address disputer = extra;
        uint88 _redemptionAmounts = DEFAULT_AMOUNT * 2;

        address sstore2Pointer = diamond.getAssetUserStruct(asset, redeemer).SSTORE2Pointer;
        assertEq(sstore2Pointer, address(0));

        MTypes.ProposalInput[] memory proposalInputs =
            makeProposalInputsForDispute({shortId1: C.SHORT_STARTING_ID, shortId2: C.SHORT_STARTING_ID + 2});
        STypes.ShortRecord memory incorrectSR = getShortRecord(sender, C.SHORT_STARTING_ID + 2);
        sstore2Pointer = diamond.getAssetUserStruct(asset, redeemer).SSTORE2Pointer;

        changeUpdateAtAndSkipTime({shortId: C.SHORT_STARTING_ID + 2});

        setETHAndProposeShorts({redeemer: redeemer, proposalInputs: proposalInputs, redemptionAmount: _redemptionAmounts});

        sstore2Pointer = diamond.getAssetUserStruct(asset, redeemer).SSTORE2Pointer;
        assertFalse(sstore2Pointer == address(0));
        vm.prank(disputer);
        vm.expectRevert(Errors.InvalidRedemptionDispute.selector);
        diamond.disputeRedemption({
            asset: asset,
            redeemer: redeemer,
            incorrectIndex: 1,
            disputeShorter: extra,
            disputeShortId: C.SHORT_STARTING_ID
        });

        STypes.ShortRecord memory disputeSR = getShortRecord(disputer, C.SHORT_STARTING_ID);
        // @dev This passing means the only place where error is triggered is: d.disputeCR >= C.ONE_CR
        assertLt(diamond.getCollateralRatio(asset, disputeSR), diamond.getCollateralRatio(asset, incorrectSR));
    }

    function test_Revert_CannotDisputeWithRedeemerProposal_FirstProposal() public {
        uint88 _redemptionAmounts = DEFAULT_AMOUNT + DEFAULT_AMOUNT + 2;
        makeShorts({singleShorter: true});

        MTypes.ProposalInput[] memory proposalInputs =
            makeProposalInputsForDispute({shortId1: C.SHORT_STARTING_ID, shortId2: C.SHORT_STARTING_ID + 2});

        address redeemer = receiver;

        setETHAndProposeShorts({redeemer: redeemer, proposalInputs: proposalInputs, redemptionAmount: _redemptionAmounts});

        address disputer = extra;

        diamond.setErcDebt({asset: asset, shorter: sender, id: C.SHORT_STARTING_ID, value: 1 wei});

        vm.prank(disputer);
        vm.expectRevert(Errors.CannotDisputeWithRedeemerProposal.selector);
        diamond.disputeRedemption({
            asset: asset,
            redeemer: redeemer,
            incorrectIndex: 1,
            disputeShorter: sender,
            disputeShortId: C.SHORT_STARTING_ID
        });
    }

    function test_Revert_CannotDisputeWithRedeemerProposal_MiddleProposal() public {
        uint88 _redemptionAmounts = DEFAULT_AMOUNT * 3;
        makeShorts({singleShorter: true});

        MTypes.ProposalInput[] memory proposalInputs = makeProposalInputs({singleShorter: true});

        address redeemer = receiver;

        setETHAndProposeShorts({redeemer: redeemer, proposalInputs: proposalInputs, redemptionAmount: _redemptionAmounts});

        address disputer = extra;

        diamond.setErcDebt({asset: asset, shorter: sender, id: C.SHORT_STARTING_ID + 1, value: 1 wei});

        vm.prank(disputer);
        vm.expectRevert(Errors.CannotDisputeWithRedeemerProposal.selector);
        diamond.disputeRedemption({
            asset: asset,
            redeemer: redeemer,
            incorrectIndex: 2,
            disputeShorter: sender,
            disputeShortId: C.SHORT_STARTING_ID + 1
        });
    }

    function test_Revert_CannotDisputeWithRedeemerProposal_LastProposal() public {
        uint88 _redemptionAmounts = DEFAULT_AMOUNT + DEFAULT_AMOUNT + 2;
        makeShorts({singleShorter: true});

        MTypes.ProposalInput[] memory proposalInputs =
            makeProposalInputsForDispute({shortId1: C.SHORT_STARTING_ID, shortId2: C.SHORT_STARTING_ID + 2});

        address redeemer = receiver;

        setETHAndProposeShorts({redeemer: redeemer, proposalInputs: proposalInputs, redemptionAmount: _redemptionAmounts});

        address disputer = extra;

        diamond.setErcDebt({asset: asset, shorter: sender, id: C.SHORT_STARTING_ID + 2, value: 1 wei});

        vm.prank(disputer);
        vm.expectRevert(Errors.CannotDisputeWithRedeemerProposal.selector);
        diamond.disputeRedemption({
            asset: asset,
            redeemer: redeemer,
            incorrectIndex: 1,
            disputeShorter: sender,
            disputeShortId: C.SHORT_STARTING_ID + 2
        });
    }

    function test_Revert_InvalidRedemptionDispute_DisputeCRGtIncorrectCR() public {
        uint88 _redemptionAmounts = DEFAULT_AMOUNT + DEFAULT_AMOUNT + 2;
        makeShorts({singleShorter: true});

        MTypes.ProposalInput[] memory proposalInputs =
            makeProposalInputsForDispute({shortId1: C.SHORT_STARTING_ID, shortId2: C.SHORT_STARTING_ID + 1});

        address redeemer = receiver;

        changeUpdateAtAndSkipTime({shortId: C.SHORT_STARTING_ID + 1});

        setETHAndProposeShorts({redeemer: redeemer, proposalInputs: proposalInputs, redemptionAmount: _redemptionAmounts});

        address disputer = extra;
        vm.prank(disputer);
        // @dev CR for C.SHORT_STARTING_ID + 2 is not lower than CR for C.SHORT_STARTING_ID + 1
        vm.expectRevert(Errors.InvalidRedemptionDispute.selector);
        diamond.disputeRedemption({
            asset: asset,
            redeemer: redeemer,
            incorrectIndex: 1,
            disputeShorter: sender,
            disputeShortId: C.SHORT_STARTING_ID + 2
        });
    }

    function test_Revert_InvalidRedemptionDispute_UpdatedAtGtProposedAt() public {
        uint88 _redemptionAmounts = DEFAULT_AMOUNT + DEFAULT_AMOUNT + 2;
        makeShorts({singleShorter: true});

        MTypes.ProposalInput[] memory proposalInputs =
            makeProposalInputsForDispute({shortId1: C.SHORT_STARTING_ID, shortId2: C.SHORT_STARTING_ID + 2});

        address redeemer = receiver;

        setETHAndProposeShorts({redeemer: redeemer, proposalInputs: proposalInputs, redemptionAmount: _redemptionAmounts});

        address disputer = extra;
        vm.prank(disputer);
        // @dev the 1 hr buffer period has not elapsed yet
        vm.expectRevert(Errors.DisputeSRUpdatedNearProposalTime.selector);
        diamond.disputeRedemption({
            asset: asset,
            redeemer: redeemer,
            incorrectIndex: 1,
            disputeShorter: sender,
            disputeShortId: C.SHORT_STARTING_ID + 1
        });
    }

    function test_Revert_InvalidRedemptionDispute_UpdatedAtGtProposedAt_minShortErc() public {
        uint88 _redemptionAmounts = DEFAULT_AMOUNT * 3;
        makeShorts({singleShorter: true});

        // C.SHORT_STARTING_ID + 3
        uint88 minShortErc = uint88(diamond.getMinShortErc(asset));
        fundLimitBidOpt(DEFAULT_PRICE, minShortErc / 2, receiver);
        fundLimitShortOpt(DEFAULT_PRICE, minShortErc, sender);
        assertEq(getShortRecord(sender, C.SHORT_STARTING_ID + 3).ercDebt, minShortErc / 2);

        // C.SHORT_STARTING_ID + 3 is skipped because not enough ercDebt
        skip(1 hours);
        MTypes.ProposalInput[] memory proposalInputs = new MTypes.ProposalInput[](3);
        proposalInputs[0] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID, shortOrderId: 0});
        proposalInputs[1] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 2, shortOrderId: 0});
        proposalInputs[2] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 3, shortOrderId: 0});
        address redeemer = receiver;
        setETHAndProposeShorts({redeemer: redeemer, proposalInputs: proposalInputs, redemptionAmount: _redemptionAmounts});

        (,,,, MTypes.ProposalData[] memory decodedProposalData) = getSlate(redeemer);
        assertEq(decodedProposalData.length, 2);
        assertEq(decodedProposalData[0].shortId, C.SHORT_STARTING_ID);
        assertEq(decodedProposalData[1].shortId, C.SHORT_STARTING_ID + 2);

        // C.SHORT_STARTING_ID + 3 now valid for proposals
        _setETH(4000 ether);
        fundLimitBidOpt(DEFAULT_PRICE, minShortErc / 2, receiver);
        assertEq(getShortRecord(sender, C.SHORT_STARTING_ID + 3).ercDebt, minShortErc);
        _setETH(1000 ether);

        address disputer = extra;
        // Reverts because the updatedAt time is too recent
        vm.prank(disputer);
        vm.expectRevert(Errors.DisputeSRUpdatedNearProposalTime.selector);
        diamond.disputeRedemption({
            asset: asset,
            redeemer: redeemer,
            incorrectIndex: 1,
            disputeShorter: sender,
            disputeShortId: C.SHORT_STARTING_ID + 3
        });

        // Does not revert
        vm.prank(disputer);
        diamond.disputeRedemption({
            asset: asset,
            redeemer: redeemer,
            incorrectIndex: 1,
            disputeShorter: sender,
            disputeShortId: C.SHORT_STARTING_ID + 1
        });
    }

    function test_Revert_NotLowestIncorrectIndex() public {
        uint88 _redemptionAmounts = DEFAULT_AMOUNT * 3;

        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, receiver);
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);
        fundLimitBidOpt(DEFAULT_PRICE + 1, DEFAULT_AMOUNT, receiver);
        fundLimitShortOpt(DEFAULT_PRICE + 1, DEFAULT_AMOUNT, sender);
        fundLimitBidOpt(DEFAULT_PRICE + 2, DEFAULT_AMOUNT, receiver);
        fundLimitShortOpt(DEFAULT_PRICE + 2, DEFAULT_AMOUNT, sender);
        fundLimitBidOpt(DEFAULT_PRICE + 3, DEFAULT_AMOUNT, receiver);
        fundLimitShortOpt(DEFAULT_PRICE + 3, DEFAULT_AMOUNT, sender);

        MTypes.ProposalInput[] memory proposalInputs = new MTypes.ProposalInput[](3);

        proposalInputs[0] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 1, shortOrderId: 0});
        proposalInputs[1] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 2, shortOrderId: 0});
        proposalInputs[2] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 3, shortOrderId: 0});

        address redeemer = receiver;

        changeUpdateAtAndSkipTime({shortId: C.SHORT_STARTING_ID + 3});

        setETHAndProposeShorts({redeemer: redeemer, proposalInputs: proposalInputs, redemptionAmount: _redemptionAmounts});

        address disputer = extra;
        vm.prank(disputer);

        address sstore2Pointer = diamond.getAssetUserStruct(asset, redeemer).SSTORE2Pointer;
        // @dev most important checks in the test
        assertFalse(sstore2Pointer == address(0));
        assertEq(diamond.getAssetUserStruct(asset, redeemer).slateLength, 3);

        // @dev CR for C.SHORT_STARTING_ID + 2 is not lower than CR for C.SHORT_STARTING_ID + 1
        vm.expectRevert(Errors.NotLowestIncorrectIndex.selector);
        diamond.disputeRedemption({
            asset: asset,
            redeemer: redeemer,
            incorrectIndex: 2,
            disputeShorter: sender,
            disputeShortId: C.SHORT_STARTING_ID
        });

        // @dev Still not the lowest!
        vm.prank(disputer);
        vm.expectRevert(Errors.NotLowestIncorrectIndex.selector);
        diamond.disputeRedemption({
            asset: asset,
            redeemer: redeemer,
            incorrectIndex: 1,
            disputeShorter: sender,
            disputeShortId: C.SHORT_STARTING_ID
        });

        vm.prank(disputer);
        diamond.disputeRedemption({
            asset: asset,
            redeemer: redeemer,
            incorrectIndex: 0,
            disputeShorter: sender,
            disputeShortId: C.SHORT_STARTING_ID
        });

        sstore2Pointer = diamond.getAssetUserStruct(asset, redeemer).SSTORE2Pointer;
        // @dev most important checks in the test
        assertEq(sstore2Pointer, address(0));
    }

    function test_Revert_NotLowestIncorrectIndex_SamePrices() public {
        uint88 _redemptionAmounts = DEFAULT_AMOUNT * 3;

        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, receiver);
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);
        fundLimitBidOpt(DEFAULT_PRICE + 2, DEFAULT_AMOUNT, receiver);
        fundLimitShortOpt(DEFAULT_PRICE + 2, DEFAULT_AMOUNT, sender);
        fundLimitBidOpt(DEFAULT_PRICE + 2, DEFAULT_AMOUNT, receiver);
        fundLimitShortOpt(DEFAULT_PRICE + 2, DEFAULT_AMOUNT, sender);
        fundLimitBidOpt(DEFAULT_PRICE + 3, DEFAULT_AMOUNT, receiver);
        fundLimitShortOpt(DEFAULT_PRICE + 3, DEFAULT_AMOUNT, sender);

        MTypes.ProposalInput[] memory proposalInputs = new MTypes.ProposalInput[](3);

        proposalInputs[0] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 1, shortOrderId: 0});
        proposalInputs[1] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 2, shortOrderId: 0});
        proposalInputs[2] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 3, shortOrderId: 0});

        address redeemer = receiver;

        changeUpdateAtAndSkipTime({shortId: C.SHORT_STARTING_ID + 3});

        setETHAndProposeShorts({redeemer: redeemer, proposalInputs: proposalInputs, redemptionAmount: _redemptionAmounts});

        address disputer = extra;
        vm.prank(disputer);

        address sstore2Pointer = diamond.getAssetUserStruct(asset, redeemer).SSTORE2Pointer;
        // @dev most important checks in the test
        assertFalse(sstore2Pointer == address(0));
        assertEq(diamond.getAssetUserStruct(asset, redeemer).slateLength, 3);

        // @dev CR for C.SHORT_STARTING_ID + 2 is not lower than CR for C.SHORT_STARTING_ID + 1
        vm.expectRevert(Errors.NotLowestIncorrectIndex.selector);
        diamond.disputeRedemption({
            asset: asset,
            redeemer: redeemer,
            incorrectIndex: 2,
            disputeShorter: sender,
            disputeShortId: C.SHORT_STARTING_ID
        });

        // @dev Still not the lowest!
        vm.prank(disputer);
        vm.expectRevert(Errors.NotLowestIncorrectIndex.selector);
        diamond.disputeRedemption({
            asset: asset,
            redeemer: redeemer,
            incorrectIndex: 1,
            disputeShorter: sender,
            disputeShortId: C.SHORT_STARTING_ID
        });

        vm.prank(disputer);
        diamond.disputeRedemption({
            asset: asset,
            redeemer: redeemer,
            incorrectIndex: 0,
            disputeShorter: sender,
            disputeShortId: C.SHORT_STARTING_ID
        });

        sstore2Pointer = diamond.getAssetUserStruct(asset, redeemer).SSTORE2Pointer;
        // @dev most important checks in the test
        assertEq(sstore2Pointer, address(0));
    }

    function test_DisputeRedemption() public {
        uint88 _redemptionAmounts = DEFAULT_AMOUNT * 2;
        uint88 initialErcEscrowed = DEFAULT_AMOUNT;
        makeShorts({singleShorter: true});

        MTypes.ProposalInput[] memory proposalInputs =
            makeProposalInputsForDispute({shortId1: C.SHORT_STARTING_ID, shortId2: C.SHORT_STARTING_ID + 2});

        address redeemer = receiver;

        checkEscrowed({redeemer: redeemer, ercEscrowed: DEF_REDEMPTION_AMOUNT});

        changeUpdateAtAndSkipTime({shortId: C.SHORT_STARTING_ID + 2});

        setETHAndProposeShorts({redeemer: redeemer, proposalInputs: proposalInputs, redemptionAmount: _redemptionAmounts});

        checkRedemptionSSTORE(redeemer, proposalInputs, IS_FULL, IS_FULL);

        //pre-dispute check
        STypes.ShortRecord memory incorrectSR = diamond.getShortRecord(asset, sender, C.SHORT_STARTING_ID + 2);
        address sstore2Pointer = diamond.getAssetUserStruct(asset, redeemer).SSTORE2Pointer;
        // assertTrue(sstore2Pointer != address(0));
        (,,,, MTypes.ProposalData[] memory decodedProposalData) = getSlate(redeemer);

        assertEq(decodedProposalData.length, 2);
        uint104 incorrectRedemptionAmount = DEFAULT_AMOUNT; //RedemptionAmount for C.SHORT_STARTING_ID + 2
        assertEq(decodedProposalData[0].shortId, C.SHORT_STARTING_ID);
        assertEq(decodedProposalData[1].shortId, C.SHORT_STARTING_ID + 2);
        assertEq(diamond.getAssetUserStruct(asset, redeemer).slateLength, 2);

        address disputer = extra;

        // @dev 96616666666666666670 = INITIAL_ETH_AMOUNT - redemption fee
        r.ethEscrowed = 96616666666666666670;
        r.ercEscrowed = initialErcEscrowed;
        assertStruct(redeemer, r);

        vm.prank(disputer);
        diamond.disputeRedemption({
            asset: asset,
            redeemer: redeemer,
            incorrectIndex: 1,
            disputeShorter: sender,
            disputeShortId: C.SHORT_STARTING_ID + 1
        });

        //post dispute check
        incorrectSR = diamond.getShortRecord(asset, sender, C.SHORT_STARTING_ID + 2);
        // penalty is updated
        STypes.ShortRecord memory correctSR = diamond.getShortRecord(asset, sender, C.SHORT_STARTING_ID + 1);
        (uint88 refundAmt, uint88 tappFee) = computeRefundAndTappFee({
            redemptionAmount: incorrectRedemptionAmount,
            highestCRInput: decodedProposalData[decodedProposalData.length - 1],
            correctSR: correctSR
        });

        assertEq(tappFee, 125 ether); //5000 ether * 2.5%

        //@dev Tapp gets ~2.5% of the refundAmt
        t.ercEscrowed = tappFee;
        t.ethEscrowed = INITIAL_ETH_AMOUNT - r.ethEscrowed; // redemption fee
        assertStruct(tapp, t);
        e.ethEscrowed = INITIAL_ETH_AMOUNT;
        e.ercEscrowed = refundAmt;
        assertStruct(disputer, e);

        sstore2Pointer = diamond.getAssetUserStruct(asset, redeemer).SSTORE2Pointer;
        // @dev most important checks in the test
        assertFalse(sstore2Pointer == address(0));
        assertEq(diamond.getAssetUserStruct(asset, redeemer).slateLength, 1);

        // @dev refund redeemer their redemptionAmount after penalty applied
        r.ercEscrowed = initialErcEscrowed + (incorrectRedemptionAmount - refundAmt - tappFee);
        assertStruct(redeemer, r);
    }

    function test_DisputeRedemption_AllRedemptionsWereIncorrect() public {
        uint88 _redemptionAmounts = DEFAULT_AMOUNT * 2;
        uint88 initialErcEscrowed = DEFAULT_AMOUNT;

        makeShorts({singleShorter: true});

        MTypes.ProposalInput[] memory proposalInputs =
            makeProposalInputsForDispute({shortId1: C.SHORT_STARTING_ID + 1, shortId2: C.SHORT_STARTING_ID + 2});

        address redeemer = receiver;

        checkEscrowed({redeemer: redeemer, ercEscrowed: DEF_REDEMPTION_AMOUNT});

        changeUpdateAtAndSkipTime({shortId: C.SHORT_STARTING_ID + 1});

        setETHAndProposeShorts({redeemer: redeemer, proposalInputs: proposalInputs, redemptionAmount: _redemptionAmounts});

        checkRedemptionSSTORE(redeemer, proposalInputs, IS_FULL, IS_FULL);

        //pre-dispute check
        STypes.ShortRecord memory incorrectSR = diamond.getShortRecord(asset, sender, C.SHORT_STARTING_ID + 1);
        address sstore2Pointer = diamond.getAssetUserStruct(asset, redeemer).SSTORE2Pointer;
        assertTrue(sstore2Pointer != address(0));
        (uint32 timeProposed,,,, MTypes.ProposalData[] memory decodedProposalData) = getSlate(redeemer);

        assertEq(decodedProposalData.length, 2);
        assertGt(timeProposed, 0);
        assertEq(diamond.getAssetUserStruct(asset, redeemer).slateLength, 2);
        // @dev 96616666666666666670 = INITIAL_ETH_AMOUNT - redemption fee
        r.ethEscrowed = 96616666666666666670;
        r.ercEscrowed = initialErcEscrowed;
        assertStruct(redeemer, r);

        address disputer = extra;
        vm.expectEmit(_diamond);
        vm.prank(disputer);
        emit Events.DisputeRedemptionAll(asset, redeemer);
        diamond.disputeRedemption({
            asset: asset,
            redeemer: redeemer,
            incorrectIndex: 0,
            disputeShorter: sender,
            disputeShortId: C.SHORT_STARTING_ID
        });

        //post dispute check
        incorrectSR = diamond.getShortRecord(asset, sender, C.SHORT_STARTING_ID + 2);
        //penalty is updated
        STypes.ShortRecord memory correctSR = diamond.getShortRecord(asset, sender, C.SHORT_STARTING_ID);
        (uint88 refundAmt, uint88 tappFee) = computeRefundAndTappFee({
            redemptionAmount: _redemptionAmounts,
            highestCRInput: decodedProposalData[decodedProposalData.length - 1],
            correctSR: correctSR
        });

        assertEq(tappFee, 250 ether); //10000 ether * 2.5%

        //@dev Tapp gets ~2.5% of the refundAmt
        t.ercEscrowed = tappFee;
        t.ethEscrowed = INITIAL_ETH_AMOUNT - r.ethEscrowed; // redemption fee
        assertStruct(tapp, t);
        e.ethEscrowed = INITIAL_ETH_AMOUNT;
        e.ercEscrowed = refundAmt;
        assertStruct(disputer, e);

        //SStorePointer is updated
        // @dev checking SStorePointer is address(0) is MAIN check of this test
        sstore2Pointer = diamond.getAssetUserStruct(asset, redeemer).SSTORE2Pointer;
        assertEq(sstore2Pointer, address(0));
        assertEq(diamond.getAssetUserStruct(asset, redeemer).slateLength, 2);

        // @dev refund redeemer their redemptionAmount after penalty applied
        r.ercEscrowed = initialErcEscrowed + (_redemptionAmounts - refundAmt - tappFee);
        assertStruct(redeemer, r);
    }

    function test_DisputeRedemptions_ClosedSR() public {
        uint88 _redemptionAmounts = DEFAULT_AMOUNT + DEFAULT_AMOUNT / 2;
        address redeemer = receiver;
        address shorter = sender;
        makeShorts({singleShorter: true});
        MTypes.ProposalInput[] memory proposalInputs =
            makeProposalInputsForDispute({shortId1: C.SHORT_STARTING_ID, shortId2: C.SHORT_STARTING_ID + 2});

        changeUpdateAtAndSkipTime({shortId: C.SHORT_STARTING_ID + 2});
        //partial propose the last SR
        setETHAndProposeShorts({redeemer: redeemer, proposalInputs: proposalInputs, redemptionAmount: _redemptionAmounts});

        //exit the remaining
        STypes.ShortRecord[] memory shortRecords = diamond.getShortRecords(asset, shorter);
        assertEq(shortRecords.length, 3);

        //exit the remaining short for id == C.SHORT_STARTING_ID + 2
        depositUsd(shorter, DEFAULT_AMOUNT / 2);
        exitShortErcEscrowed(C.SHORT_STARTING_ID + 2, DEFAULT_AMOUNT / 2, shorter);

        shortRecords = diamond.getShortRecords(asset, shorter);
        assertEq(shortRecords.length, 2);

        //pre-dispute check
        (,,,, MTypes.ProposalData[] memory decodedProposalData) = getSlate(redeemer);

        assertEq(decodedProposalData.length, 2);
        assertEq(decodedProposalData[0].shortId, C.SHORT_STARTING_ID);
        assertEq(decodedProposalData[1].shortId, C.SHORT_STARTING_ID + 2);
        assertEq(diamond.getAssetUserStruct(asset, redeemer).slateLength, 2);
        assertEq(diamond.getShortRecords(asset, shorter).length, 2);

        uint88 disputedColAmount = decodedProposalData[1].colRedeemed;
        uint88 disputedDebtAmount = decodedProposalData[1].ercDebtRedeemed;

        assertEq(disputedColAmount, 2500000000000000000);
        assertEq(disputedDebtAmount, 2500000000000000000000);

        STypes.ShortRecord memory tappSR = getShortRecord(tapp, C.SHORT_STARTING_ID);
        assertEq(tappSR.collateral, 0);
        assertEq(tappSR.ercDebt, 0);

        // dispute
        address disputer = extra;
        vm.prank(disputer);

        diamond.disputeRedemption({
            asset: asset,
            redeemer: redeemer,
            incorrectIndex: 1,
            disputeShorter: sender,
            disputeShortId: C.SHORT_STARTING_ID + 1
        });

        // @dev Confirm that SR is closed
        STypes.ShortRecord memory shortRecordHEAD = diamond.getShortRecord(asset, shorter, C.HEAD);
        STypes.ShortRecord memory closedSR = diamond.getShortRecord(asset, shorter, shortRecordHEAD.prevId);
        assertEq(closedSR.id, C.SHORT_STARTING_ID + 2);
        assertTrue(closedSR.status == SR.Closed);

        assertEq(diamond.getShortRecords(asset, shorter).length, 2);
        //@dev Add proposed amounts to tappSR
        tappSR = getShortRecord(tapp, C.SHORT_STARTING_ID);
        assertEq(tappSR.collateral, disputedColAmount);
        assertEq(tappSR.ercDebt, disputedDebtAmount);
    }

    function test_DisputeRedemptions_MergeIntoReusedSR() public {
        uint88 _redemptionAmounts = DEFAULT_AMOUNT + DEFAULT_AMOUNT / 2;
        address redeemer = receiver;
        address shorter = sender;
        for (uint256 i = C.SHORT_STARTING_ID; i < C.SHORT_MAX_ID - 3; i++) {
            fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, receiver);
            fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, shorter);
        }

        makeShorts({singleShorter: true});

        //ids 251 and 253 are the ones to propose
        MTypes.ProposalInput[] memory proposalInputs =
            makeProposalInputsForDispute({shortId1: C.SHORT_STARTING_ID + 249, shortId2: C.SHORT_STARTING_ID + 251});

        changeUpdateAtAndSkipTime({shortId: C.SHORT_STARTING_ID + 251});
        //partial propose the last SR
        setETHAndProposeShorts({redeemer: redeemer, proposalInputs: proposalInputs, redemptionAmount: _redemptionAmounts});

        //pre-dispute check
        (,,,, MTypes.ProposalData[] memory decodedProposalData) = getSlate(redeemer);

        assertEq(decodedProposalData.length, 2);
        assertEq(decodedProposalData[0].shortId, C.SHORT_STARTING_ID + 249);
        assertEq(decodedProposalData[1].shortId, C.SHORT_STARTING_ID + 251);
        assertEq(diamond.getAssetUserStruct(asset, redeemer).slateLength, 2);

        uint88 disputedColAmount = decodedProposalData[1].colRedeemed;
        uint88 disputedDebtAmount = decodedProposalData[1].ercDebtRedeemed;

        assertEq(disputedColAmount, 2500000000000000000);
        assertEq(disputedDebtAmount, 2500000000000000000000);

        // exit the remaining short for id == C.SHORT_STARTING_ID + 251
        depositUsd(shorter, DEFAULT_AMOUNT / 2);
        exitShortErcEscrowed(C.SHORT_STARTING_ID + 251, DEFAULT_AMOUNT / 2, shorter);

        //make one more short to hit max
        _setETH(4000 ether);
        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, receiver);
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, shorter);

        assertEq(diamond.getShortRecords(asset, shorter).length, 252); //max

        STypes.ShortRecord memory shortRecord = getShortRecord(sender, C.SHORT_STARTING_ID + 251);
        assertEq(shortRecord.collateral, 7.5 ether);
        assertEq(shortRecord.ercDebt, 5000 ether);

        // dispute
        address disputer = extra;
        vm.prank(disputer);

        diamond.disputeRedemption({
            asset: asset,
            redeemer: redeemer,
            incorrectIndex: 1,
            disputeShorter: shorter,
            disputeShortId: C.SHORT_STARTING_ID + 250
        });

        // @dev collateral and debt added to re-used SR
        shortRecord = getShortRecord(shorter, C.SHORT_STARTING_ID + 251);
        assertEq(shortRecord.collateral, 7.5 ether + disputedColAmount);
        assertEq(shortRecord.ercDebt, 5000 ether + disputedDebtAmount);
    }

    //@dev This test checks to see if an invalid dispute SR can be used with the ercDebtRate check
    function test_DisputeRedemption_ErcDebtRate_InvalidDisputeSR() public {
        uint88 _redemptionAmounts = DEFAULT_AMOUNT * 2;
        address redeemer = receiver;
        address disputer = extra;

        makeShorts({singleShorter: true});

        MTypes.ProposalInput[] memory proposalInputs =
            makeProposalInputsForDispute({shortId1: C.SHORT_STARTING_ID, shortId2: C.SHORT_STARTING_ID + 2});

        changeUpdateAtAndSkipTime({shortId: C.SHORT_STARTING_ID + 2});
        setETHAndProposeShorts({redeemer: redeemer, proposalInputs: proposalInputs, redemptionAmount: _redemptionAmounts});

        //pre-dispute check
        STypes.ShortRecord memory disputeSR = diamond.getShortRecord(asset, sender, C.SHORT_STARTING_ID + 1);
        assertEq(disputeSR.ercDebt, DEFAULT_AMOUNT);
        assertEq(disputeSR.ercDebtRate, 0);

        // Mimic black swan setting ercDebtRate
        testFacet.setErcDebtRateAsset(asset, 10 ether);

        //@dev This would PASS if disputeSR.updateErcDebt(d.asset) was called instead of the in-line version in DisputeRedemptionFacet.sol
        vm.prank(disputer);
        vm.expectRevert(Errors.InvalidRedemptionDispute.selector);
        diamond.disputeRedemption({
            asset: asset,
            redeemer: redeemer,
            incorrectIndex: 0,
            disputeShorter: sender,
            disputeShortId: C.SHORT_STARTING_ID + 1
        });
    }

    //@dev This test confirms that only the ercDebtRate at time of proposal is being used
    function test_DisputeRedemption_ErcDebtRateAtTimeOfProposal() public {
        uint88 _redemptionAmounts = DEFAULT_AMOUNT;
        address redeemer = receiver;
        address disputer = extra;

        fundLimitBidOpt(DEFAULT_PRICE + 1, DEFAULT_AMOUNT, receiver);
        fundLimitShortOpt(DEFAULT_PRICE + 1, DEFAULT_AMOUNT, sender); // C.SHORT_STARTING_ID
        // Mimic black swan setting ercDebtRate
        testFacet.setErcDebtRateAsset(asset, 0.1 ether);
        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, receiver);
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender); // C.SHORT_STARTING_ID + 1

        // Set up proposal
        MTypes.ProposalInput[] memory proposalInputs = new MTypes.ProposalInput[](1);
        proposalInputs[0] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 1, shortOrderId: 0});
        skip(1 hours);
        setETHAndProposeShorts({redeemer: redeemer, proposalInputs: proposalInputs, redemptionAmount: _redemptionAmounts});

        // Checking slate to see ercDebtRate is saved at time of proposal
        (,,, uint80 ercDebtRate,) = getSlate(redeemer);

        // pre-dispute check
        STypes.ShortRecord memory disputeSR = diamond.getShortRecord(asset, sender, C.SHORT_STARTING_ID);
        assertEq(disputeSR.ercDebt, DEFAULT_AMOUNT);
        // Main part of test: disputeSR.ercDebtRate != ercDebtRate
        assertEq(disputeSR.ercDebtRate, 0);
        assertEq(ercDebtRate, 0.1 ether);

        // This passes even though SR2 initially has lower CR than SR1 because of ercDebtRate application
        vm.prank(disputer);
        diamond.disputeRedemption({
            asset: asset,
            redeemer: redeemer,
            incorrectIndex: 0,
            disputeShorter: sender,
            disputeShortId: C.SHORT_STARTING_ID
        });

        disputeSR = diamond.getShortRecord(asset, sender, C.SHORT_STARTING_ID);
        assertEq(disputeSR.ercDebtRate, 0.1 ether);
    }

    function test_DisputeRedemption_RatesUnchanged() public {
        // Set rates to non-zero before proposal
        testFacet.setErcDebtRateAsset(asset, 1 ether);
        testFacet.setDethYieldRate(vault, 1 ether);

        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender); // C.SHORT_STARTING_ID
        fundLimitShortOpt(DEFAULT_PRICE + 1, DEFAULT_AMOUNT, sender); // C.SHORT_STARTING_ID + 1
        fundLimitShortOpt(DEFAULT_PRICE + 1, DEFAULT_AMOUNT, sender); // C.SHORT_STARTING_ID + 2
        fundLimitBidOpt(DEFAULT_PRICE + 1, DEFAULT_AMOUNT * 3, receiver);

        // Set up proposal
        uint88 _redemptionAmounts = DEFAULT_AMOUNT * 3 / 2;
        MTypes.ProposalInput[] memory proposalInputs = new MTypes.ProposalInput[](2);
        proposalInputs[0] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 1, shortOrderId: 0});
        proposalInputs[1] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 2, shortOrderId: 0});
        skip(1 hours);
        setETHAndProposeShorts({redeemer: receiver, proposalInputs: proposalInputs, redemptionAmount: _redemptionAmounts});

        // Use first SR to dispute the other two
        vm.prank(extra);
        diamond.disputeRedemption({
            asset: asset,
            redeemer: receiver,
            incorrectIndex: 0,
            disputeShorter: sender,
            disputeShortId: C.SHORT_STARTING_ID
        });

        // Check debt rates
        assertEq(getShortRecord(sender, C.SHORT_STARTING_ID).ercDebtRate, 1 ether);
        assertEq(getShortRecord(sender, C.SHORT_STARTING_ID + 1).ercDebtRate, 1 ether);
        assertEq(getShortRecord(sender, C.SHORT_STARTING_ID + 2).ercDebtRate, 1 ether);
        // Check yield rates
        assertEq(getShortRecord(sender, C.SHORT_STARTING_ID).dethYieldRate, 1 ether);
        assertEq(getShortRecord(sender, C.SHORT_STARTING_ID + 1).dethYieldRate, 1 ether);
        assertEq(getShortRecord(sender, C.SHORT_STARTING_ID + 2).dethYieldRate, 1 ether);
    }

    function test_DisputeRedemption_RatesDifferent() public {
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender); // C.SHORT_STARTING_ID
        fundLimitShortOpt(DEFAULT_PRICE + 1, DEFAULT_AMOUNT, sender); // C.SHORT_STARTING_ID + 1
        fundLimitShortOpt(DEFAULT_PRICE + 1, DEFAULT_AMOUNT, sender); // C.SHORT_STARTING_ID + 2
        fundLimitBidOpt(DEFAULT_PRICE + 1, DEFAULT_AMOUNT * 3, receiver);

        // Set up proposal
        uint88 _redemptionAmounts = DEFAULT_AMOUNT * 3 / 2;
        MTypes.ProposalInput[] memory proposalInputs = new MTypes.ProposalInput[](2);
        proposalInputs[0] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 1, shortOrderId: 0});
        proposalInputs[1] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 2, shortOrderId: 0});
        skip(1 hours);
        setETHAndProposeShorts({redeemer: receiver, proposalInputs: proposalInputs, redemptionAmount: _redemptionAmounts});

        // Update global rates after proposal
        testFacet.setErcDebtRateAsset(asset, 1 ether);
        testFacet.setDethYieldRate(vault, 1 ether);

        uint256 coll = getShortRecord(sender, C.SHORT_STARTING_ID).collateral;
        uint256 coll1 = getShortRecord(sender, C.SHORT_STARTING_ID + 1).collateral;
        uint256 coll2 = getShortRecord(sender, C.SHORT_STARTING_ID + 2).collateral;

        // Use first SR to dispute the other two
        vm.prank(extra);
        diamond.disputeRedemption({
            asset: asset,
            redeemer: receiver,
            incorrectIndex: 0,
            disputeShorter: sender,
            disputeShortId: C.SHORT_STARTING_ID
        });

        // Check debt rates
        assertEq(getShortRecord(sender, C.SHORT_STARTING_ID).ercDebtRate, 0 ether);
        assertEq(getShortRecord(sender, C.SHORT_STARTING_ID + 1).ercDebtRate, 1 ether); // misses the ercDebtRate application
        assertEq(getShortRecord(sender, C.SHORT_STARTING_ID + 2).ercDebtRate, 0.5 ether); // misses half the ercDebtRate application
        // Check yield rates
        assertEq(getShortRecord(sender, C.SHORT_STARTING_ID).dethYieldRate, 0 ether);
        assertApproxEqAbs(getShortRecord(sender, C.SHORT_STARTING_ID + 1).dethYieldRate, (coll - coll1).div(coll), MAX_DELTA_MEDIUM);
        assertApproxEqAbs(getShortRecord(sender, C.SHORT_STARTING_ID + 2).dethYieldRate, (coll - coll2).div(coll), MAX_DELTA_MEDIUM);
    }

    function test_DisputeRedemption_DistributeYieldSkipped() public {
        address other = address(4); // @dev avoiding extra bc it's seeded with 100 dETH
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender); // C.SHORT_STARTING_ID
        fundLimitShortOpt(DEFAULT_PRICE + 1, DEFAULT_AMOUNT, sender); // C.SHORT_STARTING_ID + 1
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, other); // C.SHORT_STARTING_ID
        fundLimitShortOpt(DEFAULT_PRICE + 1, DEFAULT_AMOUNT, other); // C.SHORT_STARTING_ID + 1
        fundLimitBidOpt(DEFAULT_PRICE + 1, DEFAULT_AMOUNT * 4, receiver);

        // Set up proposal
        uint88 _redemptionAmounts = DEFAULT_AMOUNT;
        MTypes.ProposalInput[] memory proposalInputs = new MTypes.ProposalInput[](1);
        proposalInputs[0] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 1, shortOrderId: 0});
        skip(1 hours);
        setETHAndProposeShorts({redeemer: receiver, proposalInputs: proposalInputs, redemptionAmount: _redemptionAmounts});

        // Generate Yield
        deal(_steth, _bridgeSteth, 1000 ether);
        diamond.updateYield(vault);
        distributeYield(sender);
        distributeYield(other);
        // Assert that one SR of sender is skipped bc it's fully redeemed
        assertApproxEqAbs(
            diamond.getVaultUserStruct(vault, sender).ethEscrowed * 2,
            diamond.getVaultUserStruct(vault, other).ethEscrowed,
            MAX_DELTA_MEDIUM
        );
    }

    //ClaimRedemption
    //revert

    function test_Revert_ClaimRedemption_InvalidRedemption() public {
        address redeemer = receiver;

        vm.prank(redeemer);
        vm.expectRevert(Errors.InvalidRedemption.selector);
        diamond.claimRedemption(asset);
    }

    function test_Revert_TimeToDisputeHasNotElapsed() public {
        test_proposeRedemption_SingleShorter();

        address redeemer = receiver;

        vm.prank(redeemer);
        vm.expectRevert(Errors.TimeToDisputeHasNotElapsed.selector);
        diamond.claimRedemption(asset);
    }

    //non-revert
    function getColRedeemedAndShorterRefund(MTypes.ProposalData[] memory proposalData)
        public
        view
        returns (uint88 totalColRedeemed, uint88 shorterRefund)
    {
        MTypes.ProposalData memory proposal;
        STypes.ShortRecord memory shortRecord;

        for (uint256 i = 0; i < proposalData.length; i++) {
            proposal = proposalData[i];
            shortRecord = getShortRecord(proposal.shorter, proposal.shortId);
            if (shortRecord.ercDebt == 0 && shortRecord.status == SR.FullyFilled) {
                totalColRedeemed += proposal.colRedeemed;
                shorterRefund += shortRecord.collateral;
            }
        }
    }

    function test_claimRedemption_AllShortsDeleted() public {
        test_proposeRedemption_SingleShorter();

        address redeemer = receiver;
        address shorter = sender;
        address sstore2Pointer = diamond.getAssetUserStruct(asset, redeemer).SSTORE2Pointer;
        uint8 slateLength = diamond.getAssetUserStruct(asset, redeemer).slateLength;

        (, uint32 timeToDispute, uint80 oraclePrice,, MTypes.ProposalData[] memory decodedProposalData) =
            LibBytes.readProposalData(sstore2Pointer, slateLength);

        (, uint88 shorterRefund) = getColRedeemedAndShorterRefund(decodedProposalData);
        skip(timeToDispute);
        //check redeemer asset user before redemption
        assertGt(timeToDispute, 0);
        assertFalse(diamond.getAssetUserStruct(asset, redeemer).SSTORE2Pointer == address(0));
        assertGt(oraclePrice, 0);
        vm.expectEmit(_diamond);
        vm.prank(redeemer);
        emit Events.ClaimRedemption(asset, redeemer);
        diamond.claimRedemption(asset);

        //check redeemer asset user after redemption;
        assertEq(diamond.getAssetUserStruct(asset, redeemer).SSTORE2Pointer, address(0));

        //check redeemer and shorter ethEscrowed
        // INITIAL_ETH_AMOUNT + totalColRedeemed - redemptionFee = 107425000000000000000
        r.ethEscrowed = 107425000000000000000;
        r.ercEscrowed = 0;
        assertStruct(redeemer, r);

        s.ethEscrowed = shorterRefund;
        s.ercEscrowed = 0;
        assertStruct(shorter, s);

        // check SR's are deleted
        STypes.ShortRecord[] memory shortRecords = diamond.getShortRecords(asset, shorter);
        assertEq(shortRecords.length, 0);
    }

    function test_claimRedemption_SomeShortsDeleted() public {
        address redeemer = receiver;
        address shorter = sender;
        uint88 leftoverErc = 2000 ether;
        makeShorts({singleShorter: true});

        MTypes.ProposalInput[] memory proposalInputs = makeProposalInputs({singleShorter: true});

        _setETH(1000 ether);
        // @dev partially propose the last proposal
        proposeRedemption(proposalInputs, DEF_REDEMPTION_AMOUNT - leftoverErc, redeemer);

        address sstore2Pointer = diamond.getAssetUserStruct(asset, redeemer).SSTORE2Pointer;
        uint8 slateLength = diamond.getAssetUserStruct(asset, redeemer).slateLength;

        (, uint32 timeToDispute, uint80 oraclePrice,, MTypes.ProposalData[] memory decodedProposalData) =
            LibBytes.readProposalData(sstore2Pointer, slateLength);

        (, uint88 shorterRefund) = getColRedeemedAndShorterRefund(decodedProposalData);
        skip(timeToDispute);
        //check redeemer asset user before redemption
        assertGt(timeToDispute, 0);
        assertFalse(diamond.getAssetUserStruct(asset, redeemer).SSTORE2Pointer == address(0));
        assertGt(oraclePrice, 0);

        vm.prank(redeemer);
        diamond.claimRedemption(asset);

        //check redeemer asset user after redemption;
        assertEq(diamond.getAssetUserStruct(asset, redeemer).SSTORE2Pointer, address(0));

        //check redeemer and shorter ethEscrowed
        // INITIAL_ETH_AMOUNT + totalColRedeemed - redemptionFee = 107301666666666666671
        r.ethEscrowed = 107301666666666666671;
        r.ercEscrowed = leftoverErc;
        assertStruct(redeemer, r);

        s.ethEscrowed = shorterRefund;
        s.ercEscrowed = 0;
        assertStruct(shorter, s);

        //All SR's are deleted except for the last one bc of partial

        STypes.ShortRecord[] memory shortRecords = diamond.getShortRecords(asset, shorter);
        assertEq(shortRecords.length, 1);
        assertEq(shortRecords[0].ercDebt, leftoverErc);
        //exit the remaining short
        _setETH(4000 ether);
        fundLimitAskOpt(DEFAULT_PRICE, leftoverErc, extra);
        exitShort(C.SHORT_STARTING_ID + 2, leftoverErc, DEFAULT_PRICE, shorter);
        shortRecords = diamond.getShortRecords(asset, shorter);
        assertEq(shortRecords.length, 0);
    }

    function test_claimRedemption_EnsureValuesReset() public {
        test_claimRedemption_AllShortsDeleted();

        // Save data from last redemption, make sure they get overwritten properly
        address redeemer = receiver;
        address SSTORE2Pointer = diamond.getAssetUserStruct(asset, redeemer).SSTORE2Pointer;
        uint8 slateLength = diamond.getAssetUserStruct(asset, redeemer).slateLength;

        // Make SR
        _setETH(4000 ether);
        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, receiver);
        fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);
        _setETH(999 ether); // using different price this time around

        // Propose redemption
        MTypes.ProposalInput[] memory proposalInputs = new MTypes.ProposalInput[](1);
        proposalInputs[0] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 2, shortOrderId: 0});
        depositUsd(redeemer, DEFAULT_AMOUNT);
        proposeRedemption(proposalInputs, DEFAULT_AMOUNT, redeemer);

        // Ensure AssetUser values were overwritten
        assertNotEq(SSTORE2Pointer, diamond.getAssetUserStruct(asset, redeemer).SSTORE2Pointer);
        assertNotEq(slateLength, diamond.getAssetUserStruct(asset, redeemer).slateLength);
    }

    //claimRemainingCollateral
    function test_revert_claimRemainingCollateral_InvalidRedemption() public {
        vm.expectRevert(Errors.InvalidRedemption.selector);
        diamond.claimRemainingCollateral(asset, receiver, 0, 0);
    }

    function test_revert_claimRemainingCollateral_CanOnlyClaimYourShort() public {
        test_proposeRedemption_SingleShorter();
        skip(1 days);

        // @dev caller is not the shorter
        vm.prank(receiver);
        vm.expectRevert(Errors.CanOnlyClaimYourShort.selector);
        diamond.claimRemainingCollateral(asset, receiver, 0, C.SHORT_STARTING_ID);

        // @dev wrong shortId
        vm.prank(sender);
        vm.expectRevert(Errors.CanOnlyClaimYourShort.selector);
        diamond.claimRemainingCollateral(asset, receiver, 0, C.SHORT_STARTING_ID + 2);
    }

    function test_revert_claimRemainingCollateral_TimeToDisputeHasNotElapsed() public {
        test_proposeRedemption_SingleShorter();
        address redeemer = receiver;
        address shorter = sender;
        vm.prank(shorter);
        vm.expectRevert(Errors.TimeToDisputeHasNotElapsed.selector);
        diamond.claimRemainingCollateral(asset, redeemer, 0, C.SHORT_STARTING_ID);
    }

    function test_claimRemainingCollateral() public {
        test_proposeRedemption_SingleShorter();

        address redeemer = receiver;
        address shorter = sender;
        address sstore2Pointer = diamond.getAssetUserStruct(asset, redeemer).SSTORE2Pointer;
        uint8 slateLength = diamond.getAssetUserStruct(asset, redeemer).slateLength;

        (, uint32 timeToDispute,,, MTypes.ProposalData[] memory decodedProposalData) =
            LibBytes.readProposalData(sstore2Pointer, slateLength);

        (, uint88 shorterRefund) = getColRedeemedAndShorterRefund(decodedProposalData);
        skip(timeToDispute);
        //check redeemer asset user before redemption
        assertFalse(diamond.getAssetUserStruct(asset, redeemer).SSTORE2Pointer == address(0));

        //check redeemer ethEscrowed prior to claim
        r.ethEscrowed = 92425000000000000000; //the actual value of this number is irrelevant for this test
        r.ercEscrowed = 0;
        assertStruct(redeemer, r);

        vm.startPrank(shorter);
        diamond.claimRemainingCollateral(asset, redeemer, 0, C.SHORT_STARTING_ID);
        diamond.claimRemainingCollateral(asset, redeemer, 1, C.SHORT_STARTING_ID + 1);
        diamond.claimRemainingCollateral(asset, redeemer, 2, C.SHORT_STARTING_ID + 2);
        vm.stopPrank();

        //check redeemer asset user after redemption;
        assertFalse(diamond.getAssetUserStruct(asset, redeemer).SSTORE2Pointer == address(0));

        //check redeemer and shorter ethEscrowed
        //The redeemer didn't claim yet, thus no change in ethEscrowed
        assertStruct(redeemer, r);

        s.ethEscrowed = shorterRefund;
        s.ercEscrowed = 0;
        assertStruct(shorter, s);

        // check SR's are deleted
        STypes.ShortRecord[] memory shortRecords = diamond.getShortRecords(asset, shorter);
        assertEq(shortRecords.length, 0);
    }

    //Redemption Fee
    function test_Revert_RedemptionFeeTooHigh() public {
        makeShorts({singleShorter: true});
        MTypes.ProposalInput[] memory proposalInputs = makeProposalInputs({singleShorter: true});
        address redeemer = receiver;
        _setETH(1000 ether);
        vm.prank(redeemer);
        vm.expectRevert(Errors.RedemptionFeeTooHigh.selector);
        diamond.proposeRedemption(asset, proposalInputs, DEF_REDEMPTION_AMOUNT, 1 wei, MAX_REDEMPTION_DEADLINE);
    }

    // @dev this test is directional
    function test_RedemptionFee() public {
        address shorter = sender;
        address redeemer = receiver;
        assertEq(diamond.getAssetStruct(asset).ercDebt, 0);
        for (uint256 i = 0; i < 200; i++) {
            fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, redeemer);
            fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, shorter);
        }
        // @dev 1,000,000 dUSD
        assertEq(diamond.getAssetStruct(asset).ercDebt, DEFAULT_AMOUNT * 200);

        assertEq(diamond.getAssetStruct(asset).baseRate, 0);

        //Proposal 1
        _setETH(4000 ether); //prevent oracle from breaking
        MTypes.ProposalInput[] memory proposalInputs = makeProposalInputs({singleShorter: true});
        skip(21600 seconds); //6 hrs
        _setETH(1000 ether);
        proposeRedemption(proposalInputs, DEF_REDEMPTION_AMOUNT, redeemer);

        (uint32 timeProposed, uint32 timeToDispute,,, MTypes.ProposalData[] memory decodedProposalData) = getSlate(redeemer);
        skip(timeToDispute);

        vm.prank(redeemer);
        diamond.claimRedemption(asset);
        assertEq(diamond.getAssetStruct(asset).baseRate, 0.0075 ether);

        console.log("-----------------");
        console.log("-----------------");
        //Proposal 2 - huge increase
        _setETH(4000 ether); //prevent oracle from breaking
        proposalInputs = new MTypes.ProposalInput[](10);
        proposalInputs[0] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 3, shortOrderId: 0});
        proposalInputs[1] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 4, shortOrderId: 0});
        proposalInputs[2] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 5, shortOrderId: 0});
        proposalInputs[3] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 6, shortOrderId: 0});
        proposalInputs[4] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 7, shortOrderId: 0});
        proposalInputs[5] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 8, shortOrderId: 0});
        proposalInputs[6] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 9, shortOrderId: 0});
        proposalInputs[7] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 10, shortOrderId: 0});
        proposalInputs[8] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 11, shortOrderId: 0});
        proposalInputs[9] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 12, shortOrderId: 0});

        skip(21600 seconds); //6 hrs
        _setETH(1000 ether);
        proposeRedemption(proposalInputs, DEFAULT_AMOUNT * 10, redeemer);
        (timeProposed, timeToDispute,,, decodedProposalData) = getSlate(redeemer);

        skip(timeToDispute);
        vm.prank(redeemer);
        diamond.claimRedemption(asset);
        assertEq(diamond.getAssetStruct(asset).baseRate, 0.028819420647547392 ether);

        console.log("-----------------");
        console.log("-----------------");

        //Proposal 3 - huge decrease
        _setETH(4000 ether); //prevent oracle from breaking
        proposalInputs = new MTypes.ProposalInput[](1);
        proposalInputs[0] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 13, shortOrderId: 0});

        skip(21600 seconds); //6 hrs
        _setETH(1000 ether);
        proposeRedemption(proposalInputs, DEFAULT_AMOUNT, redeemer);

        (timeProposed, timeToDispute,,, decodedProposalData) = getSlate(redeemer);
        skip(timeToDispute);

        vm.prank(redeemer);
        diamond.claimRedemption(asset);
        assertEq(diamond.getAssetStruct(asset).baseRate, 0.008732139254787112 ether);

        console.log("-----------------");
        console.log("-----------------");

        //Proposal 4 - decrease fee close to zero
        _setETH(4000 ether); //prevent oracle from breaking
        proposalInputs = new MTypes.ProposalInput[](1);
        proposalInputs[0] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 14, shortOrderId: 0});
        skip(7 days);
        _setETH(1000 ether);
        proposeRedemption(proposalInputs, DEFAULT_AMOUNT, redeemer);

        (timeProposed, timeToDispute,,, decodedProposalData) = getSlate(redeemer);
        skip(timeToDispute);
        vm.prank(redeemer);
        diamond.claimRedemption(asset);
        // @dev close to zero
        assertEq(diamond.getAssetStruct(asset).baseRate, 0.002688205351340749 ether);
    }

    function test_RedemptionFee_12HrHalfLife() public {
        address shorter = sender;
        address redeemer = receiver;
        assertEq(diamond.getAssetStruct(asset).ercDebt, 0);
        for (uint256 i = 0; i < 200; i++) {
            fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, redeemer);
            fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, shorter);
        }

        //Proposal 1
        _setETH(4000 ether); //prevent oracle from breaking
        MTypes.ProposalInput[] memory proposalInputs = makeProposalInputs({singleShorter: true});
        _setETH(1000 ether);
        proposeRedemption(proposalInputs, DEF_REDEMPTION_AMOUNT, redeemer);
        (, uint32 timeToDispute,,,) = getSlate(redeemer);
        skip(timeToDispute);
        vm.prank(redeemer);
        diamond.claimRedemption(asset);
        uint256 initialBaseRate = 0.0075 ether;
        assertEq(diamond.getAssetStruct(asset).baseRate, initialBaseRate);

        //Make 2nd proposal 12 hours later
        _setETH(4000 ether); //prevent oracle from breaking
        proposalInputs = new MTypes.ProposalInput[](1);
        proposalInputs[0] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 3, shortOrderId: 0});
        skip(12 hours - timeToDispute); //12 total hrs since last proposal
        _setETH(1000 ether);
        //propose a small amount (1 ether is the lowest value for minShortErc)
        vm.prank(owner);
        diamond.setMinShortErcT(asset, 0);
        proposeRedemption(proposalInputs, 1 wei, redeemer);

        // @dev after 12 hrs, baseRate is roughly halved
        assertApproxEqAbs(diamond.getAssetStruct(asset).baseRate, initialBaseRate / 2, MAX_DELTA_MEDIUM);
        assertEq(initialBaseRate / 2, 0.00375 ether);
    }

    function test_RedemptionFee_0SecondsPassedButLargeNextProposal() public {
        address shorter = sender;
        address redeemer = receiver;
        assertEq(diamond.getAssetStruct(asset).ercDebt, 0);
        for (uint256 i = 0; i < 200; i++) {
            fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, redeemer);
            fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, shorter);
        }

        //Proposal 1
        _setETH(4000 ether); //prevent oracle from breaking
        MTypes.ProposalInput[] memory proposalInputs = makeProposalInputs({singleShorter: true});
        skip(21600 seconds); //6 hrs
        _setETH(1000 ether);
        proposeRedemption(proposalInputs, DEF_REDEMPTION_AMOUNT, redeemer);

        uint256 baseRateInitial = diamond.getAssetStruct(asset).baseRate;
        assertEq(baseRateInitial, 0.0075 ether);

        //Make HUGE 2nd proposal immediately
        _setETH(4000 ether); //prevent oracle from breaking
        proposalInputs = new MTypes.ProposalInput[](10);
        proposalInputs[0] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 3, shortOrderId: 0});
        proposalInputs[1] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 4, shortOrderId: 0});
        proposalInputs[2] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 5, shortOrderId: 0});
        proposalInputs[3] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 6, shortOrderId: 0});
        proposalInputs[4] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 7, shortOrderId: 0});
        proposalInputs[5] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 8, shortOrderId: 0});
        proposalInputs[6] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 9, shortOrderId: 0});
        proposalInputs[7] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 10, shortOrderId: 0});
        proposalInputs[8] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 11, shortOrderId: 0});
        proposalInputs[9] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 12, shortOrderId: 0});
        _setETH(1000 ether);
        depositUsdAndPrank(extra, DEFAULT_AMOUNT * 10); // Use different redeemer
        proposeRedemption(proposalInputs, DEFAULT_AMOUNT * 10);

        // @dev ercRedeemed/ercDebtTotal where 3 was removed in the first redemption
        // @dev +10 ether to account for the amount minted via depositUsdAndPrank
        uint256 baseRateAdd = uint256(10 ether).div(200 ether - 3 ether + 10 ether).div(C.BETA);
        uint256 baseRateFinal = baseRateInitial + baseRateAdd;
        assertEq(diamond.getAssetStruct(asset).baseRate, baseRateFinal);
    }

    // @dev this test is from Code4Rena. Slightly modified now that the mitigation is implemented
    // @dev https://github.com/code-423n4/2024-03-dittoeth-findings/issues/32
    function test_decrease_cr_dispute_attack() public {
        // create three SRs with increasing CRs above initialCR

        // set inital CR to 1.7 as in the docs
        vm.startPrank(owner);
        diamond.setInitialCR(asset, 170);

        uint80 price = diamond.getOraclePriceT(asset);

        fundLimitBidOpt(price, DEFAULT_AMOUNT, receiver);

        depositEth(sender, price.mulU88(DEFAULT_AMOUNT).mulU88(100e18));

        uint16[] memory shortHintArray = setShortHintArray();
        MTypes.OrderHint[] memory orderHintArray = diamond.getHintArray(asset, price, O.LimitShort, 1);
        vm.prank(sender);
        diamond.createLimitShort(asset, price, DEFAULT_AMOUNT, orderHintArray, shortHintArray, 70);

        fundLimitBidOpt(price + 1, DEFAULT_AMOUNT, receiver);

        shortHintArray = setShortHintArray();
        orderHintArray = diamond.getHintArray(asset, price, O.LimitShort, 1);
        vm.prank(sender);
        diamond.createLimitShort(asset, price, DEFAULT_AMOUNT, orderHintArray, shortHintArray, 80);

        fundLimitBidOpt(price + 2, DEFAULT_AMOUNT, receiver);

        shortHintArray = setShortHintArray();
        orderHintArray = diamond.getHintArray(asset, price, O.LimitShort, 1);
        vm.prank(sender);
        diamond.createLimitShort(asset, price, DEFAULT_AMOUNT, orderHintArray, shortHintArray, 100);

        skip(1 hours);

        STypes.ShortRecord memory sr1 = diamond.getShortRecord(asset, sender, C.SHORT_STARTING_ID);
        STypes.ShortRecord memory sr2 = diamond.getShortRecord(asset, sender, C.SHORT_STARTING_ID + 1);
        STypes.ShortRecord memory sr3 = diamond.getShortRecord(asset, sender, C.SHORT_STARTING_ID + 2);

        uint256 cr1 = diamond.getCollateralRatio(asset, sr1);
        uint256 cr2 = diamond.getCollateralRatio(asset, sr2);
        uint256 cr3 = diamond.getCollateralRatio(asset, sr3);

        // CRs are increasing
        assertGt(cr2, cr1);
        assertGt(cr3, cr2);

        // user proposes a redemption
        uint88 _redemptionAmounts = DEFAULT_AMOUNT * 2;

        MTypes.ProposalInput[] memory proposalInputs =
            makeProposalInputsForDispute({shortId1: C.SHORT_STARTING_ID, shortId2: C.SHORT_STARTING_ID + 1});

        setETH(3500 ether);
        address redeemer = receiver;
        proposeRedemption(proposalInputs, _redemptionAmounts, redeemer);

        // attacker decreases collateral of a SR with a CR avove the ones in the proposal so that they fall below the CR of the SRs in the proposal
        uint32 updatedAtBefore = getShortRecord(sender, C.SHORT_STARTING_ID + 2).updatedAt;

        vm.prank(sender);
        diamond.decreaseCollateral(asset, C.SHORT_STARTING_ID + 2, 0.3e18);

        uint32 updatedAtAfter = getShortRecord(sender, C.SHORT_STARTING_ID + 2).updatedAt;

        // updatedAt param is not updated when decreasing collateral
        assertFalse(updatedAtBefore == updatedAtAfter);

        // @dev This reflects the bug fix: attacker fails to disputes the redemption proposal
        address disputer = extra;
        vm.prank(disputer);
        vm.expectRevert(Errors.DisputeSRUpdatedNearProposalTime.selector);
        diamond.disputeRedemption({
            asset: asset,
            redeemer: redeemer,
            incorrectIndex: 1,
            disputeShorter: sender,
            disputeShortId: C.SHORT_STARTING_ID + 2
        });
    }

    // @dev this test is from Code4Rena. Slightly modified now that the mitigation is implemented
    // @dev https://github.com/code-423n4/2024-03-dittoeth-findings/issues/33
    function test_proposeRedemption_does_update_updatedAt() public {
        // setup
        uint88 _redemptionAmounts = DEFAULT_AMOUNT * 2;
        makeShorts({singleShorter: true});

        skip(1 hours);
        _setETH(1000 ether);

        // propose a redemption
        MTypes.ProposalInput[] memory proposalInputs =
            makeProposalInputsForDispute({shortId1: C.SHORT_STARTING_ID, shortId2: C.SHORT_STARTING_ID + 1});

        uint32 updatedAtBefore = getShortRecord(sender, C.SHORT_STARTING_ID).updatedAt;

        proposeRedemption(proposalInputs, _redemptionAmounts, receiver);

        uint32 updatedAtAfter = getShortRecord(sender, C.SHORT_STARTING_ID).updatedAt;

        // @dev After the bug fix, the updatedAt param was updated
        assertFalse(updatedAtBefore == updatedAtAfter);
    }

    // @dev this test is from Code4Rena. Slightly modified now that the mitigation is implemented
    // @dev https://github.com/code-423n4/2024-03-dittoeth-findings/issues/34
    function test_combineShorts_does_update_updatedAt_to_now() public {
        uint256 initialTimestamp = diamond.getOffsetTime();
        // create SRs
        makeShorts({singleShorter: true});
        skip(1 hours);
        vm.prank(sender);
        combineShorts({id1: C.SHORT_STARTING_ID, id2: C.SHORT_STARTING_ID + 1});

        // @dev After the bug fix, updatedAt should now be updated
        assertLt(initialTimestamp, getShortRecord(sender, C.SHORT_STARTING_ID).updatedAt);
    }
    // @dev https://github.com/code-423n4/2024-03-dittoeth-findings/issues/104

    function testRuinsDebtAndCollateralTracking() public {
        // Set up all of the users
        address redeemer = receiver;
        address redeemer2 = makeAddr("redeemer2");
        depositEth(redeemer2, INITIAL_ETH_AMOUNT);

        for (uint256 i = 0; i < 6; i++) {
            if (i % 2 == 0) {
                fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, redeemer);
                fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);
            } else {
                fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, redeemer2);
                fundLimitShortOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, sender);
            }
        }

        _setETH(50000 ether);
        fundLimitBidOpt(DEFAULT_PRICE - 0.000000001 ether, DEFAULT_AMOUNT, redeemer2);
        fundLimitShortOpt(DEFAULT_PRICE - 0.000000001 ether, DEFAULT_AMOUNT, sender);

        MTypes.ProposalInput[] memory redeemerProposalInputs = new MTypes.ProposalInput[](1);
        redeemerProposalInputs[0] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID, shortOrderId: 0});

        _setETH(1000 ether);

        proposeRedemption(redeemerProposalInputs, DEF_REDEMPTION_AMOUNT, redeemer); // Redeemer creates a proposal
        (, uint32 timeToDispute,,, MTypes.ProposalData[] memory decodedProposalData) = getSlate(redeemer);
        skip(timeToDispute); // Skip the time to dispute for the first proposal (5401 seconds)

        MTypes.ProposalInput[] memory redeemer2ProposalInputs = new MTypes.ProposalInput[](1);
        redeemer2ProposalInputs[0] = MTypes.ProposalInput({shorter: sender, shortId: C.SHORT_STARTING_ID + 1, shortOrderId: 0});

        proposeRedemption(redeemer2ProposalInputs, DEF_REDEMPTION_AMOUNT, redeemer2); // Redeemer2 creates a proposal

        (, timeToDispute,,, decodedProposalData) = getSlate(redeemer2);
        assert(diamond.getOffsetTime() < timeToDispute); // Not enough time has passed in order to redeem the second proposal (5402 < 10802)

        vm.expectRevert(Errors.TimeToDisputeHasNotElapsed.selector);
        vm.prank(redeemer2);
        diamond.claimRedemption(asset); // This correctly reverts as 5401 seconds have not passed and bug is non-existent in claimRedemption()

        vm.prank(sender);
        vm.expectRevert(Errors.CanOnlyClaimYourShort.selector);
        // @dev bug fixed here
        diamond.claimRemainingCollateral(asset, redeemer, 0, C.SHORT_STARTING_ID + 1);
    }

    function test_decayFactorNotOverFlowing() public {
        makeShorts({singleShorter: true});
        // 100 years between lastRemption
        skip(60 * 60 * 24 * 365 * 100);
        // no assertion needed just checking for no revert
        diamond.getRedemptionFee(asset, 10000 ether, 5 ether);
    }
}
