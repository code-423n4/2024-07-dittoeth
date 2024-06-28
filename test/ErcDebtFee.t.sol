// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {U256, U88} from "contracts/libraries/PRBMathHelper.sol";
import {Errors} from "contracts/libraries/Errors.sol";
import {IAsset} from "interfaces/IAsset.sol";
import {LibBytes} from "contracts/libraries/LibBytes.sol";
import {C} from "contracts/libraries/Constants.sol";
import {STypes, MTypes, SR, O} from "contracts/libraries/DataTypes.sol";

import {OBFixture} from "test/utils/OBFixture.sol";

import {console} from "contracts/libraries/console.sol";

contract ErcDebtFeeTest is OBFixture {
    using U256 for uint256;
    using U88 for uint88;

    address public constant USER = address(1);
    address public constant USER_TWO = address(2);
    address public constant USER_THREE = address(3);
    uint88 AMOUNT = 200000 ether;

    function vault_ErcEscrowedPlusAssetBalanceEqTotalDebt() public view {
        address[] memory users = new address[](3);
        users[0] = address(1);
        users[1] = address(2);
        users[2] = address(3);

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

        console.log("--Open SHORTS--");
        uint256 ercEscrowedShorts;
        STypes.Order[] memory shorts = diamond.getShorts(asset);
        for (uint256 i = 0; i < shorts.length; i++) {
            ercEscrowedShorts += shorts[i].ercAmount;
            console.logErcDebt(shorts[i].addr, shorts[i].ercAmount);
        }

        {
            console.log("--Open BIDS--");
            uint256 ercEscrowedBids;
            STypes.Order[] memory bids = diamond.getBids(asset);
            for (uint256 i = 0; i < bids.length; i++) {
                ercEscrowedBids += bids[i].ercAmount;
                console.logErcDebt(bids[i].addr, bids[i].ercAmount);
            }
        }

        console.log("--Users--");
        console.log("User: yDUSD Vault");
        uint256 _balance = assetContract.balanceOf(_yDUSD);
        assetBalance += _balance;
        for (uint256 i = 0; i < users.length; i++) {
            console.log("User:", users[i]);
            uint256 _escrowed = diamond.getAssetUserStruct(asset, users[i]).ercEscrowed;
            ercEscrowed += _escrowed;
            _balance = assetContract.balanceOf(users[i]);
            assetBalance += _balance;
            console.log("--DUSD--");
            console.logErcDebt(users[i], _escrowed + _balance);

            STypes.ShortRecord[] memory shorts = diamond.getShortRecords(asset, users[i]);
            console.log("Short lengths", shorts.length);
            console.log("--SR--");
            for (uint256 j = 0; j < shorts.length; j++) {
                if (shorts[j].ercDebt == 0) continue;
                console.log("Short ID:", shorts[j].id);
                uint88 _debt = shorts[j].ercDebt;
                totalDebt += _debt;
                // Undistributed debt
                uint256 _unDebt =
                    (_debt - shorts[j].ercDebtFee).mulU88(diamond.getAssetStruct(asset).ercDebtRate - shorts[j].ercDebtRate);
                totalDebt += _unDebt;
                console.logErcDebt(users[i], _debt);
                console.logErcDebt(users[i], _unDebt);
                // console.logErcDebt(users[i], shorts[j].ercDebtFee);

                console.log(_debt);
                console.log(diamond.getAssetStruct(asset).ercDebtRate);
                console.log(shorts[j].ercDebtRate);
            }
        }

        console.log("--TAPP DUSD--");
        ercEscrowed += diamond.getAssetUserStruct(asset, address(diamond)).ercEscrowed;
        console.logErcDebt(address(diamond), diamond.getAssetUserStruct(asset, address(diamond)).ercEscrowed);

        if (diamond.getShortRecordCount(asset, address(diamond)) > 0) {
            STypes.ShortRecord memory tappSR = diamond.getShortRecords(asset, address(diamond))[0];
            uint88 unrealizedTappDebt =
                (tappSR.ercDebt - tappSR.ercDebtFee).mulU88(diamond.getAssetStruct(asset).ercDebtRate - tappSR.ercDebtRate);
            // Add ercDebt from TAPP ercEscrowed and TAPP SR

            totalDebt += tappSR.ercDebt;
            totalDebt += unrealizedTappDebt;

            console.logErcDebt(address(diamond), diamond.getShortRecords(asset, address(diamond))[0].ercDebt);
            console.logErcDebt(address(diamond), unrealizedTappDebt);
        }

        console.log("--Total--");
        console.log(string.concat("ercEscrowed: ", console.weiToEther(ercEscrowed)));
        console.log(string.concat("assetBalance: ", console.weiToEther(assetBalance)));
        console.log(string.concat("totalDebt: ", console.weiToEther(totalDebt)));
        console.log(string.concat("ercDebtFee: ", console.weiToEther(diamond.getAssetStruct(asset).ercDebtFee)));

        assertApproxEqAbs(ercEscrowed + assetBalance, totalDebt, MAX_DELTA);
        assertApproxEqAbs(diamond.getAssetStruct(asset).ercDebt, totalDebt, MAX_DELTA);
    }

    function discountedMatch() public {
        uint256 initialErcDebtRate = diamond.getAssetStruct(asset).ercDebtRate;
        limitBidOpt(0.0001 ether, AMOUNT, USER);
        limitAskOpt(0.0001 ether, AMOUNT, USER);
        assertGt(diamond.getAssetStruct(asset).ercDebtRate, initialErcDebtRate);
    }

    function updateErcDebtT(uint8 shortId) public {
        vm.startPrank(USER);
        decreaseCollateral(shortId, 1 wei);
        increaseCollateral(shortId, 1 wei);
        vm.stopPrank();
    }

    function depositEthForUser() public {
        // @dev Need USER and USER_TWO because address cannot exit or liquidate themselves
        give(_steth, USER, 9999990000000000003608);
        give(_steth, USER_TWO, 9999990000000000003608);
        give(_steth, 9999990000000000003608 * 2);
        vm.startPrank(USER);
        steth.approve(_bridgeSteth, type(uint88).max);
        diamond.deposit(_bridgeSteth, 9999990000000000003608);
        vm.stopPrank();
        vm.startPrank(USER_TWO);
        steth.approve(_bridgeSteth, type(uint88).max);
        diamond.deposit(_bridgeSteth, 9999990000000000003608);
        vm.stopPrank();
    }

    function test_Discounts_ercFee_OneDiscount() public {
        depositEthForUser();

        limitBidOpt(0.00025 ether, AMOUNT, USER);
        limitShortOpt(0.00025 ether, AMOUNT, USER);

        limitBidOpt(0.0001 ether, AMOUNT, USER);
        limitAskOpt(0.0001 ether, AMOUNT, USER);

        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();
    }

    function test_Discounts_ercFee_OneDiscount_UpdateErcDebt_A() public {
        depositEthForUser();

        limitBidOpt(0.00025 ether, AMOUNT, USER);
        limitShortOpt(0.00025 ether, AMOUNT, USER);

        updateErcDebtT(C.SHORT_STARTING_ID);
        limitBidOpt(0.0001 ether, AMOUNT, USER);
        limitAskOpt(0.0001 ether, AMOUNT, USER);

        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();
    }

    function test_Discounts_ercFee_OneDiscount_UpdateErcDebt_B() public {
        depositEthForUser();

        limitBidOpt(0.00025 ether, AMOUNT, USER);
        limitShortOpt(0.00025 ether, AMOUNT, USER);

        limitBidOpt(0.0001 ether, AMOUNT, USER);
        updateErcDebtT(C.SHORT_STARTING_ID);
        limitAskOpt(0.0001 ether, AMOUNT, USER);

        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();
    }

    function test_Discounts_ercFee_OneDiscount_UpdateErcDebt_C() public {
        depositEthForUser();

        limitBidOpt(0.00025 ether, AMOUNT, USER);
        limitShortOpt(0.00025 ether, AMOUNT, USER);

        limitBidOpt(0.0001 ether, AMOUNT, USER);
        limitAskOpt(0.0001 ether, AMOUNT, USER);
        updateErcDebtT(C.SHORT_STARTING_ID);

        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();
    }

    function test_Discounts_ercFee_TwoDiscount() public {
        depositEthForUser();

        limitBidOpt(0.00025 ether, AMOUNT, USER);
        limitShortOpt(0.00025 ether, AMOUNT, USER);

        limitBidOpt(0.0001 ether, AMOUNT, USER);
        limitAskOpt(0.0001 ether, AMOUNT, USER);

        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();

        limitBidOpt(0.0001 ether, AMOUNT, USER);
        limitAskOpt(0.0001 ether, AMOUNT, USER);

        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();
    }

    function test_Discounts_ercFee_TwoDiscount_UpdateErcDebt() public {
        depositEthForUser();

        limitBidOpt(0.00025 ether, AMOUNT, USER);
        limitShortOpt(0.00025 ether, AMOUNT, USER);

        updateErcDebtT(C.SHORT_STARTING_ID);
        limitBidOpt(0.0001 ether, AMOUNT, USER);
        updateErcDebtT(C.SHORT_STARTING_ID);
        limitAskOpt(0.0001 ether, AMOUNT, USER);
        updateErcDebtT(C.SHORT_STARTING_ID);

        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();

        limitBidOpt(0.0001 ether, AMOUNT, USER);
        updateErcDebtT(C.SHORT_STARTING_ID);
        limitAskOpt(0.0001 ether, AMOUNT, USER);
        updateErcDebtT(C.SHORT_STARTING_ID);

        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();
    }

    function test_Discounts_ercFee_ThreeDiscount() public {
        depositEthForUser();

        limitBidOpt(0.00025 ether, AMOUNT, USER);
        limitShortOpt(0.00025 ether, AMOUNT, USER);

        limitBidOpt(0.0001 ether, AMOUNT, USER);
        limitAskOpt(0.0001 ether, AMOUNT, USER);

        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();

        limitBidOpt(0.0001 ether, AMOUNT, USER);
        limitAskOpt(0.0001 ether, AMOUNT, USER);

        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();

        limitBidOpt(0.0001 ether, AMOUNT, USER);
        limitAskOpt(0.0001 ether, AMOUNT, USER);

        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();
    }

    function test_Discounts_ercFee_ThreeDiscount_UpdateErcDebt() public {
        depositEthForUser();

        limitBidOpt(0.00025 ether, AMOUNT, USER);
        limitShortOpt(0.00025 ether, AMOUNT, USER);

        updateErcDebtT(C.SHORT_STARTING_ID);
        limitBidOpt(0.0001 ether, AMOUNT, USER);
        updateErcDebtT(C.SHORT_STARTING_ID);
        limitAskOpt(0.0001 ether, AMOUNT, USER);
        updateErcDebtT(C.SHORT_STARTING_ID);

        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();

        limitBidOpt(0.0001 ether, AMOUNT, USER);
        updateErcDebtT(C.SHORT_STARTING_ID);
        limitAskOpt(0.0001 ether, AMOUNT, USER);
        updateErcDebtT(C.SHORT_STARTING_ID);

        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();

        limitBidOpt(0.0001 ether, AMOUNT, USER);
        updateErcDebtT(C.SHORT_STARTING_ID);
        limitAskOpt(0.0001 ether, AMOUNT, USER);
        updateErcDebtT(C.SHORT_STARTING_ID);

        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();
    }

    function test_Discounts_ercFee_ThreeDiscount_PartialMatchThenFullMatch() public {
        depositEthForUser();

        limitBidOpt(0.00025 ether, AMOUNT / 2, USER);
        limitShortOpt(0.00025 ether, AMOUNT, USER);

        updateErcDebtT(C.SHORT_STARTING_ID);
        limitBidOpt(0.0001 ether, AMOUNT / 2, USER);
        updateErcDebtT(C.SHORT_STARTING_ID);
        limitAskOpt(0.0001 ether, AMOUNT / 2, USER);
        updateErcDebtT(C.SHORT_STARTING_ID);

        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();

        //Match the rest
        limitBidOpt(0.00025 ether, AMOUNT / 2, USER);
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();

        limitBidOpt(0.0001 ether, AMOUNT, USER);
        updateErcDebtT(C.SHORT_STARTING_ID);
        limitAskOpt(0.0001 ether, AMOUNT, USER);
        updateErcDebtT(C.SHORT_STARTING_ID);

        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();

        limitBidOpt(0.0001 ether, AMOUNT, USER);
        updateErcDebtT(C.SHORT_STARTING_ID);
        limitAskOpt(0.0001 ether, AMOUNT, USER);
        updateErcDebtT(C.SHORT_STARTING_ID);

        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();
    }

    function test_Discounts_ercFee_ThreeDiscount_CombineShort() public {
        depositEthForUser();

        assertEq(getShortRecordCount(USER), 0);
        limitBidOpt(0.00025 ether, AMOUNT, USER);
        limitShortOpt(0.00025 ether, AMOUNT, USER);
        limitBidOpt(0.00025 ether, AMOUNT, USER);
        limitShortOpt(0.00025 ether, AMOUNT, USER);
        assertEq(getShortRecordCount(USER), 2);

        // First discount
        limitBidOpt(0.0001 ether, AMOUNT, USER);
        updateErcDebtT(C.SHORT_STARTING_ID);
        limitAskOpt(0.0001 ether, AMOUNT, USER);

        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();

        vm.prank(USER);
        combineShorts({id1: C.SHORT_STARTING_ID, id2: C.SHORT_STARTING_ID + 1});

        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();

        assertEq(getShortRecordCount(USER), 1);

        //Second discount
        limitBidOpt(0.0001 ether, AMOUNT, USER);
        updateErcDebtT(C.SHORT_STARTING_ID);
        limitAskOpt(0.0001 ether, AMOUNT, USER);

        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();

        //Third discount
        limitBidOpt(0.0001 ether, AMOUNT, USER);
        limitAskOpt(0.0001 ether, AMOUNT, USER);

        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();
    }

    function test_Discounts_ercFee_ThreeDiscount_ExitShort() public {
        depositEthForUser();

        assertEq(getShortRecordCount(USER), 0);
        limitBidOpt(0.00025 ether, AMOUNT, USER);
        limitShortOpt(0.00025 ether, AMOUNT, USER);
        limitBidOpt(0.00025 ether, AMOUNT * 2, USER_TWO);
        limitShortOpt(0.00025 ether, AMOUNT * 2, USER);
        assertEq(getShortRecordCount(USER), 2);

        // First discount
        discountedMatch();
        updateErcDebtT(C.SHORT_STARTING_ID);
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();

        // Partial exit first SR
        limitAskOpt(DEFAULT_PRICE, AMOUNT / 2, USER_TWO);
        exitShort(C.SHORT_STARTING_ID, AMOUNT / 2, DEFAULT_PRICE, USER);
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();
        assertEq(getShortRecordCount(USER), 2);
        assertEq(diamond.getShortRecord(asset, USER, C.SHORT_STARTING_ID).ercDebtFee, 0);

        // Second discount
        discountedMatch();
        updateErcDebtT(C.SHORT_STARTING_ID);
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();

        // Fully exit first SR
        uint88 debtLeft = diamond.getExpectedSRDebt(asset, USER, C.SHORT_STARTING_ID);
        limitAskOpt(DEFAULT_PRICE, debtLeft, USER_TWO);
        exitShort(C.SHORT_STARTING_ID, debtLeft, DEFAULT_PRICE, USER);
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();
        assertEq(getShortRecordCount(USER), 1);

        // Third discount
        updateErcDebtT(C.SHORT_STARTING_ID + 1);
        discountedMatch();
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();
    }

    function test_Discounts_ercFee_ThreeDiscount_ExitShort_ErcEscrowed() public {
        depositEthForUser();

        // USER needs multiple shorts to have enough ercEscrowed to both exit and limitAskOpt
        assertEq(getShortRecordCount(USER), 0);
        limitBidOpt(0.00025 ether, AMOUNT, USER);
        limitShortOpt(0.00025 ether, AMOUNT, USER);
        limitBidOpt(0.00025 ether, AMOUNT * 2, USER);
        limitShortOpt(0.00025 ether, AMOUNT * 2, USER);
        assertEq(getShortRecordCount(USER), 2);

        // First discount
        discountedMatch();
        updateErcDebtT(C.SHORT_STARTING_ID);
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();

        // Partial exit first SR
        exitShortErcEscrowed(C.SHORT_STARTING_ID, AMOUNT / 2, USER);
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();
        assertEq(getShortRecordCount(USER), 2);
        assertEq(diamond.getShortRecord(asset, USER, C.SHORT_STARTING_ID).ercDebtFee, 0);

        // Second discount
        discountedMatch();
        updateErcDebtT(C.SHORT_STARTING_ID);
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();

        // Fully exit first SR
        uint88 debtLeft = diamond.getExpectedSRDebt(asset, USER, C.SHORT_STARTING_ID);
        exitShortErcEscrowed(C.SHORT_STARTING_ID, debtLeft, USER);
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();
        assertEq(getShortRecordCount(USER), 1);

        // Third discount
        updateErcDebtT(C.SHORT_STARTING_ID + 1);
        discountedMatch();
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();
    }

    function test_Discounts_ercFee_ThreeDiscount_ExitShort_Wallet() public {
        depositEthForUser();

        // USER needs multiple shorts to have enough ercEscrowed to both exit and limitAskOpt
        assertEq(getShortRecordCount(USER), 0);
        limitBidOpt(0.00025 ether, AMOUNT, USER);
        limitShortOpt(0.00025 ether, AMOUNT, USER);
        limitBidOpt(0.00025 ether, AMOUNT * 2, USER);
        limitShortOpt(0.00025 ether, AMOUNT * 2, USER);
        assertEq(getShortRecordCount(USER), 2);

        // First discount
        discountedMatch();
        updateErcDebtT(C.SHORT_STARTING_ID);
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();

        // Partial exit first SR
        vm.prank(USER);
        diamond.withdrawAsset(asset, AMOUNT / 2);
        exitShortWallet(C.SHORT_STARTING_ID, AMOUNT / 2, USER);
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();
        assertEq(getShortRecordCount(USER), 2);
        assertEq(diamond.getShortRecord(asset, USER, C.SHORT_STARTING_ID).ercDebtFee, 0);

        // Second discount
        discountedMatch();
        updateErcDebtT(C.SHORT_STARTING_ID);
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();

        // Fully exit first SR
        uint88 debtLeft = diamond.getExpectedSRDebt(asset, USER, C.SHORT_STARTING_ID);
        vm.prank(USER);
        diamond.withdrawAsset(asset, debtLeft);
        exitShortWallet(C.SHORT_STARTING_ID, debtLeft, USER);
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();
        assertEq(getShortRecordCount(USER), 1);

        // Third discount
        updateErcDebtT(C.SHORT_STARTING_ID + 1);
        discountedMatch();
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();
    }

    function test_Discounts_ercFee_ThreeDiscount_PrimaryLiquidation() public {
        depositEthForUser();

        assertEq(getShortRecordCount(USER), 0);
        limitBidOpt(0.00025 ether, AMOUNT, USER);
        limitShortOpt(0.00025 ether, AMOUNT, USER);
        limitBidOpt(0.00025 ether, AMOUNT * 2, USER_TWO);
        limitShortOpt(0.00025 ether, AMOUNT * 2, USER);
        assertEq(getShortRecordCount(USER), 2);

        // First discount
        discountedMatch();
        updateErcDebtT(C.SHORT_STARTING_ID);
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();

        // Partial liquidate first SR
        setETH(2600 ether);
        limitAskOpt(DEFAULT_PRICE, AMOUNT / 2, USER_TWO);
        vm.prank(USER_TWO);
        diamond.liquidate(asset, USER, C.SHORT_STARTING_ID, shortHintArrayStorage, 0);
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();
        assertEq(getShortRecordCount(USER), 2);
        assertEq(diamond.getShortRecord(asset, USER, C.SHORT_STARTING_ID).ercDebtFee, 0);

        // Second discount
        discountedMatch();
        updateErcDebtT(C.SHORT_STARTING_ID);
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();

        // Fully liquidate first SR via partial liquidate
        setETH(1000 ether);
        uint88 debtLeft = diamond.getExpectedSRDebt(asset, USER, C.SHORT_STARTING_ID);
        limitAskOpt(DEFAULT_PRICE, debtLeft, USER_TWO);
        vm.prank(USER_TWO);
        diamond.liquidate(asset, USER, C.SHORT_STARTING_ID, shortHintArrayStorage, 0);
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();
        assertEq(getShortRecordCount(USER), 1);

        // Third discount
        setETH(4000 ether);
        updateErcDebtT(C.SHORT_STARTING_ID + 1);
        discountedMatch();
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();
    }

    function test_Discounts_ercFee_ThreeDiscount_PrimaryLiquidation_TappAbsorbsSR() public {
        depositEthForUser();

        //Depositing eth to TAPP to prevent socialization
        give(_steth, tapp, 9999990000000000003608);
        vm.startPrank(tapp);
        steth.approve(_bridgeSteth, type(uint88).max);
        diamond.deposit(_bridgeSteth, 9999990000000000003608);
        vm.stopPrank();

        assertEq(getShortRecordCount(USER), 0);
        limitBidOpt(0.00025 ether, AMOUNT, USER);
        limitShortOpt(0.00025 ether, AMOUNT, USER);
        limitBidOpt(0.00025 ether, AMOUNT * 2, USER_TWO);
        limitShortOpt(0.00025 ether, AMOUNT * 2, USER);
        assertEq(getShortRecordCount(USER), 2);

        // First discount
        discountedMatch();
        updateErcDebtT(C.SHORT_STARTING_ID);
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();

        // Partial liquidate first SR
        setETH(730 ether);
        limitAskOpt(DEFAULT_PRICE, AMOUNT / 2, USER_TWO);
        vm.prank(USER_TWO);
        diamond.liquidate(asset, USER, C.SHORT_STARTING_ID, shortHintArrayStorage, 0);
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();
        assertEq(getShortRecordCount(USER), 1);
        assertEq(diamond.getShortRecord(asset, address(diamond), C.SHORT_STARTING_ID).ercDebtFee, 0);

        // Second discount
        setETH(4000 ether);
        discountedMatch();
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();

        // Fully liquidate TAPP SR
        setETH(1000 ether);
        assertEq(getShortRecordCount(tapp), 1);
        uint88 debtLeft = diamond.getExpectedSRDebt(asset, tapp, C.SHORT_STARTING_ID);
        limitAskOpt(DEFAULT_PRICE, debtLeft, USER_TWO);
        vm.prank(USER);
        diamond.liquidate(asset, tapp, C.SHORT_STARTING_ID, shortHintArrayStorage, 0);
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();
        assertEq(getShortRecordCount(tapp), 0);

        // Third discount
        setETH(4000 ether);
        discountedMatch();
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();
    }

    function test_Discounts_ercFee_ThreeDiscount_SecondaryLiquidation_ErcEscrowed() public {
        bool ERC_ESCROWED = false;
        depositEthForUser();

        assertEq(getShortRecordCount(USER), 0);
        limitBidOpt(0.00025 ether, AMOUNT, USER);
        limitShortOpt(0.00025 ether, AMOUNT, USER);
        limitBidOpt(0.00025 ether, AMOUNT * 2, USER_TWO);
        limitShortOpt(0.00025 ether, AMOUNT * 2, USER);
        assertEq(getShortRecordCount(USER), 2);

        // First discount
        limitBidOpt(0.0001 ether, AMOUNT, USER);
        updateErcDebtT(C.SHORT_STARTING_ID);
        limitAskOpt(0.0001 ether, AMOUNT, USER);
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();

        // Fully liquidate first SR via secondary liquidation
        setETH(2600 ether);
        MTypes.BatchLiquidation[] memory batches = new MTypes.BatchLiquidation[](1);
        batches[0] = MTypes.BatchLiquidation({shorter: USER, shortId: C.SHORT_STARTING_ID, shortOrderId: 0});
        uint88 debtLeft = diamond.getExpectedSRDebt(asset, USER, C.SHORT_STARTING_ID);
        vm.prank(USER_TWO);
        diamond.liquidateSecondary(asset, batches, debtLeft, ERC_ESCROWED);
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();
        assertEq(getShortRecordCount(USER), 1);

        // Third discount
        setETH(4000 ether);
        limitBidOpt(0.0001 ether, AMOUNT, USER);
        updateErcDebtT(C.SHORT_STARTING_ID + 1);
        limitAskOpt(0.0001 ether, AMOUNT, USER);
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();
    }

    function test_Discounts_ercFee_ThreeDiscount_SecondaryLiquidation_Wallet() public {
        bool WALLET = true;
        depositEthForUser();

        assertEq(getShortRecordCount(USER), 0);
        limitBidOpt(0.00025 ether, AMOUNT, USER);
        limitShortOpt(0.00025 ether, AMOUNT, USER);
        limitBidOpt(0.00025 ether, AMOUNT * 2, USER_TWO);
        limitShortOpt(0.00025 ether, AMOUNT * 2, USER);
        assertEq(getShortRecordCount(USER), 2);

        // First discount
        limitBidOpt(0.0001 ether, AMOUNT, USER);
        updateErcDebtT(C.SHORT_STARTING_ID);
        limitAskOpt(0.0001 ether, AMOUNT, USER);
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();

        // Fully liquidate first SR via secondary liquidation
        setETH(2600 ether);
        MTypes.BatchLiquidation[] memory batches = new MTypes.BatchLiquidation[](1);
        batches[0] = MTypes.BatchLiquidation({shorter: USER, shortId: C.SHORT_STARTING_ID, shortOrderId: 0});
        uint88 debtLeft = diamond.getExpectedSRDebt(asset, USER, C.SHORT_STARTING_ID);
        vm.startPrank(USER_TWO);
        diamond.withdrawAsset(asset, debtLeft);
        diamond.liquidateSecondary(asset, batches, debtLeft, WALLET);
        vm.stopPrank();
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();
        assertEq(getShortRecordCount(USER), 1);

        // Third discount
        setETH(4000 ether);
        limitBidOpt(0.0001 ether, AMOUNT, USER);
        updateErcDebtT(C.SHORT_STARTING_ID + 1);
        limitAskOpt(0.0001 ether, AMOUNT, USER);
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();
    }

    function test_Discounts_ercFee_ThreeDiscount_ProposeRedemption_ClaimRedemption() public {
        address redeemer = USER_TWO;
        depositEthForUser();
        give(_steth, USER_THREE, 9999990000000000003608);
        give(_steth, 9999990000000000003608);
        vm.startPrank(USER_THREE);
        steth.approve(_bridgeSteth, type(uint88).max);
        diamond.deposit(_bridgeSteth, 9999990000000000003608);
        vm.stopPrank();

        assertEq(getShortRecordCount(USER), 0);
        limitBidOpt(0.00026 ether, AMOUNT, USER);
        limitShortOpt(0.00026 ether, AMOUNT, USER);
        limitBidOpt(0.00025 ether, AMOUNT * 2, USER_TWO);
        limitShortOpt(0.00025 ether, AMOUNT * 2, USER);
        limitBidOpt(0.00025 ether, AMOUNT * 2, USER_THREE);
        limitShortOpt(0.00025 ether, AMOUNT * 2, USER);
        assertEq(getShortRecordCount(USER), 3);

        // First discount
        limitBidOpt(0.0001 ether, AMOUNT, USER);
        updateErcDebtT(C.SHORT_STARTING_ID);
        limitAskOpt(0.0001 ether, AMOUNT, USER);
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();

        // Partial redeem first SR
        MTypes.ProposalInput[] memory proposalInputs = new MTypes.ProposalInput[](1);
        proposalInputs[0] = MTypes.ProposalInput({shorter: USER, shortId: C.SHORT_STARTING_ID, shortOrderId: 0});
        setETH(900 ether);
        uint88 debtLeft = diamond.getExpectedSRDebt(asset, USER, C.SHORT_STARTING_ID);
        address sstore2Pointer = diamond.getAssetUserStruct(asset, redeemer).SSTORE2Pointer;
        assertTrue(sstore2Pointer == address(0));
        assertEq(getShortRecordCount(USER), 3);
        proposeRedemption(proposalInputs, debtLeft / 2, redeemer);
        sstore2Pointer = diamond.getAssetUserStruct(asset, redeemer).SSTORE2Pointer;
        assertTrue(sstore2Pointer != address(0));
        assertEq(getShortRecordCount(USER), 3);

        // Second discount
        setETH(4000 ether);
        limitBidOpt(0.0001 ether, AMOUNT, USER);
        updateErcDebtT(C.SHORT_STARTING_ID);
        limitAskOpt(0.0001 ether, AMOUNT, USER);
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();

        // Fully redeem first SR via partial redeem
        setETH(900 ether);
        redeemer = USER_THREE;
        debtLeft = diamond.getExpectedSRDebt(asset, USER, C.SHORT_STARTING_ID);
        sstore2Pointer = diamond.getAssetUserStruct(asset, redeemer).SSTORE2Pointer;
        assertTrue(sstore2Pointer == address(0));
        assertEq(getShortRecordCount(USER), 3);
        assertGt(getShortRecord(USER, C.SHORT_STARTING_ID).ercDebt, 0);
        proposeRedemption(proposalInputs, debtLeft, redeemer);
        sstore2Pointer = diamond.getAssetUserStruct(asset, redeemer).SSTORE2Pointer;
        assertTrue(sstore2Pointer != address(0));
        assertEq(getShortRecordCount(USER), 3);
        //Fully proposed
        assertEq(getShortRecord(USER, C.SHORT_STARTING_ID).ercDebt, 0);

        // Third discount
        setETH(4000 ether);
        limitBidOpt(0.0001 ether, AMOUNT, USER);
        updateErcDebtT(C.SHORT_STARTING_ID + 1);
        limitAskOpt(0.0001 ether, AMOUNT, USER);
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();

        //Claim
        uint8 slateLength = diamond.getAssetUserStruct(asset, redeemer).slateLength;
        (, uint32 timeToDispute,,,) = LibBytes.readProposalData(sstore2Pointer, slateLength);
        skip(timeToDispute);
        vm.prank(redeemer);
        diamond.claimRedemption(asset);
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();

        // Fourth discount
        setETH(4000 ether);
        limitBidOpt(0.0001 ether, AMOUNT, USER);
        updateErcDebtT(C.SHORT_STARTING_ID + 1);
        limitAskOpt(0.0001 ether, AMOUNT, USER);
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();
    }

    function test_Discounts_ercFee_ThreeDiscount_ProposeRedemption_DisputeRedemption() public {
        address redeemer = USER_TWO;
        depositEthForUser();

        assertEq(getShortRecordCount(USER), 0);
        limitBidOpt(0.00026 ether, AMOUNT, USER);
        limitShortOpt(0.00026 ether, AMOUNT, USER);
        limitBidOpt(0.00026 ether, AMOUNT, USER);
        limitShortOpt(0.00026 ether, AMOUNT, USER);
        limitBidOpt(0.00025 ether, AMOUNT * 3, USER_TWO);
        limitShortOpt(0.00025 ether, AMOUNT * 3, USER);
        assertEq(getShortRecordCount(USER), 3);

        // First discount
        limitBidOpt(0.0001 ether, AMOUNT, USER);
        updateErcDebtT(C.SHORT_STARTING_ID);
        limitAskOpt(0.0001 ether, AMOUNT, USER);
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();

        //Change UpdateAt and skip time to allow dispute
        vm.startPrank(USER);
        decreaseCollateral(C.SHORT_STARTING_ID, 1 wei);
        decreaseCollateral(C.SHORT_STARTING_ID + 1, 1 wei);
        vm.stopPrank();
        skip(1 hours);

        // Fully redeem first SR
        setETH(900 ether);
        MTypes.ProposalInput[] memory proposalInputs = new MTypes.ProposalInput[](2);
        proposalInputs[0] = MTypes.ProposalInput({shorter: USER, shortId: C.SHORT_STARTING_ID, shortOrderId: 0});
        proposalInputs[1] = MTypes.ProposalInput({shorter: USER, shortId: C.SHORT_STARTING_ID + 1, shortOrderId: 0});
        uint88 debtLeft = diamond.getExpectedSRDebt(asset, USER, C.SHORT_STARTING_ID)
            + diamond.getExpectedSRDebt(asset, USER, C.SHORT_STARTING_ID + 1);
        address sstore2Pointer = diamond.getAssetUserStruct(asset, redeemer).SSTORE2Pointer;
        assertTrue(sstore2Pointer == address(0));
        assertEq(getShortRecordCount(USER), 3);
        assertGt(getShortRecord(USER, C.SHORT_STARTING_ID).ercDebt, 0);
        assertGt(getShortRecord(USER, C.SHORT_STARTING_ID + 1).ercDebt, 0);
        proposeRedemption(proposalInputs, debtLeft, redeemer);
        sstore2Pointer = diamond.getAssetUserStruct(asset, redeemer).SSTORE2Pointer;
        assertTrue(sstore2Pointer != address(0));
        assertEq(getShortRecordCount(USER), 3);
        //Fully proposed
        assertEq(getShortRecord(USER, C.SHORT_STARTING_ID).ercDebt, 0);
        assertEq(getShortRecord(USER, C.SHORT_STARTING_ID + 1).ercDebt, 0);

        // Third discount
        setETH(4000 ether);
        limitBidOpt(0.0001 ether, AMOUNT, USER);
        limitAskOpt(0.0001 ether, AMOUNT, USER);
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();

        //Dispute
        setETH(900 ether);
        address disputer = USER;
        vm.prank(disputer);
        diamond.disputeRedemption({
            asset: asset,
            redeemer: redeemer,
            incorrectIndex: 0,
            disputeShorter: USER,
            disputeShortId: C.SHORT_STARTING_ID + 2
        });

        // Yet another discount
        setETH(4000 ether);
        limitBidOpt(0.0001 ether, AMOUNT, USER);
        limitAskOpt(0.0001 ether, AMOUNT, USER);
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();
    }
}
