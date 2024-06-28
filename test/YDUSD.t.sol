// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {U104, U80} from "contracts/libraries/PRBMathHelper.sol";
import {Errors} from "contracts/libraries/Errors.sol";
import {OBFixture} from "test/utils/OBFixture.sol";
import {C} from "contracts/libraries/Constants.sol";
import {STypes, MTypes, O} from "contracts/libraries/DataTypes.sol";
import {console} from "contracts/libraries/console.sol";

contract yDUSDTest is OBFixture {
    using U104 for uint104;
    using U80 for uint80;

    function setUp() public override {
        super.setUp();

        //mint dusd to receiver
        vm.prank(_diamond);
        token.mint(receiver, DEFAULT_AMOUNT);

        //give allowance to yDUSD on dUSD for receiver
        vm.prank(receiver);
        token.approve(_yDUSD, type(uint256).max);
        vm.prank(sender);
        token.approve(_yDUSD, type(uint256).max);
        vm.prank(_diamond);
        token.approve(_yDUSD, type(uint256).max);
    }

    function discountSetUp() public returns (uint104 newDebt) {
        uint64 discountPenaltyFee = uint64(diamond.getAssetNormalizedStruct(asset).discountPenaltyFee);
        // @dev Make dethCollateral non zero
        fundLimitBidOpt(DEFAULT_PRICE, ERCDEBTSEED, receiver);
        fundLimitShortOpt(DEFAULT_PRICE, ERCDEBTSEED, extra);

        // @dev Matching above caused Asset.discountedErcMatched = 1 wei
        if (diamond.getAssetStruct(asset).discountedErcMatched == 1 wei) diamond.setDiscountedErcMatchedAsset(asset, 0);

        skip(1 days - 1 seconds);
        setETH(4000 ether);
        assertEq(diamond.getAssetStruct(asset).lastDiscountTime, 0);
        assertEq(diamond.getAssetStruct(asset).initialDiscountTime, 1 seconds);

        uint80 savedPrice = uint80(diamond.getProtocolAssetPrice(asset));
        uint80 askPrice = uint80(savedPrice.mul(0.98 ether));
        uint80 bidPrice = uint80(savedPrice.mul(0.98 ether));

        STypes.ShortRecord memory tappSR = getShortRecord(tapp, C.SHORT_STARTING_ID);
        uint104 ercDebtMinusTapp = diamond.getAssetStruct(asset).ercDebt - tappSR.ercDebt;
        uint104 newDebt = ercDebtMinusTapp.mulU104(discountPenaltyFee);

        // Cause discount
        fundLimitBidOpt(bidPrice, ERCDEBTSEED, receiver);
        MTypes.OrderHint[] memory orderHintArray = diamond.getHintArray(asset, askPrice, O.LimitAsk, 1);
        createAsk(askPrice, ERCDEBTSEED, C.LIMIT_ORDER, orderHintArray, receiver);
        return newDebt;
    }

    function test_Revert_yDUSD_mint() public {
        vm.prank(receiver);
        vm.expectRevert(Errors.ERC4626CannotMint.selector);
        rebasingToken.mint(DEFAULT_AMOUNT, receiver);
    }

    function test_Revert_yDUSD_Redeem() public {
        vm.prank(receiver);
        vm.expectRevert(Errors.ERC4626CannotRedeem.selector);
        rebasingToken.redeem(DEFAULT_AMOUNT, receiver, receiver);
    }

    function test_Revert_yDUSD_ERC4626CannotWithdrawBeforeDiscountWindowExpires_ProposeWithdraw() public {
        // Deposit stuff to withdraw
        vm.prank(receiver);
        rebasingToken.deposit(DEFAULT_AMOUNT, receiver);

        discountSetUp();

        assertEq(diamond.getAssetStruct(asset).lastDiscountTime, 1 days);
        assertEq(diamond.getAssetStruct(asset).initialDiscountTime, 1 days);

        // Last match was discounted
        vm.prank(receiver);
        vm.expectRevert(Errors.ERC4626CannotWithdrawBeforeDiscountWindowExpires.selector);
        rebasingToken.proposeWithdraw(DEFAULT_AMOUNT);

        // Match at oracle
        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, receiver);
        fundLimitAskOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, receiver);
        // skip(C.DISCOUNT_WAIT_TIME);
        assertEq(diamond.getAssetStruct(asset).lastDiscountTime, 1 days);
        assertEq(diamond.getAssetStruct(asset).initialDiscountTime, 1 seconds);

        // Need to wait DISCOUNT_WAIT_TIME since last discount
        vm.prank(receiver);
        vm.expectRevert(Errors.ERC4626CannotWithdrawBeforeDiscountWindowExpires.selector);
        rebasingToken.proposeWithdraw(DEFAULT_AMOUNT);

        assertLe(rebasingToken.getAmountProposed(receiver), 1);
        assertLe(rebasingToken.getTimeProposed(receiver), 1);

        skip(C.DISCOUNT_WAIT_TIME);
        vm.prank(receiver);
        rebasingToken.proposeWithdraw(DEFAULT_AMOUNT);

        assertEq(rebasingToken.getAmountProposed(receiver), DEFAULT_AMOUNT);
        assertGt(rebasingToken.getTimeProposed(receiver), 1);
    }

    function test_Revert_yDUSD_ERC4626CannotWithdrawBeforeDiscountWindowExpires_Withdraw() public {
        uint80 savedPrice = uint80(diamond.getProtocolAssetPrice(asset));
        uint80 askPrice = uint80(savedPrice.mul(0.98 ether));
        uint80 bidPrice = uint80(savedPrice.mul(0.98 ether));

        // Run the same test as above to call proposeWithdraw
        test_Revert_yDUSD_ERC4626CannotWithdrawBeforeDiscountWindowExpires_ProposeWithdraw();

        //Skip 7 days to avoid ERC4626WaitLongerBeforeWithdrawing error
        skip(7 days);
        setETH(4000 ether);

        //Create another discount to block withdrawal
        fundLimitBidOpt(bidPrice, DEFAULT_AMOUNT, receiver);
        fundLimitAskOpt(askPrice, DEFAULT_AMOUNT, receiver);

        assertEq(diamond.getAssetStruct(asset).lastDiscountTime, 8 days + C.DISCOUNT_WAIT_TIME);
        assertEq(diamond.getAssetStruct(asset).initialDiscountTime, 8 days + C.DISCOUNT_WAIT_TIME);

        // Last match was discounted
        vm.prank(receiver);
        vm.expectRevert(Errors.ERC4626CannotWithdrawBeforeDiscountWindowExpires.selector);
        rebasingToken.withdraw(DEFAULT_AMOUNT, receiver, receiver);

        // Match at oracle again
        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, receiver);
        fundLimitAskOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, receiver);
        assertEq(diamond.getAssetStruct(asset).lastDiscountTime, 8 days + C.DISCOUNT_WAIT_TIME);
        assertEq(diamond.getAssetStruct(asset).initialDiscountTime, 1 seconds);

        // Need to wait C.DISCOUNT_WAIT_TIME days since last discount
        vm.prank(receiver);
        vm.expectRevert(Errors.ERC4626CannotWithdrawBeforeDiscountWindowExpires.selector);
        rebasingToken.withdraw(DEFAULT_AMOUNT, receiver, receiver);

        // Pre Withdraw Check
        assertEq(rebasingToken.balanceOf(receiver), DEFAULT_AMOUNT);

        skip(C.DISCOUNT_WAIT_TIME);
        vm.prank(receiver);
        rebasingToken.withdraw(DEFAULT_AMOUNT, receiver, receiver);
        assertLt(rebasingToken.balanceOf(receiver), DEFAULT_AMOUNT);
    }

    function test_yDUSD_AssetIsDUSD() public {
        assertEq(rebasingToken.asset(), _dusd);
    }

    function test_yDUSD_Deposit() public {
        //check balance before deposit
        assertEq(rebasingToken.balanceOf(receiver), 0);
        assertEq(rebasingToken.totalAssets(), 0);
        assertEq(rebasingToken.totalAssets(), 0);
        assertEq(token.balanceOf(receiver), DEFAULT_AMOUNT);
        assertEq(token.balanceOf(_diamond), 0);
        assertEq(token.balanceOf(_yDUSD), 0);
        assertEq(token.totalSupply(), DEFAULT_AMOUNT);

        // deposit dusd into yDUSD
        vm.prank(_diamond);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        rebasingToken.deposit(DEFAULT_AMOUNT + 1, receiver);

        vm.prank(receiver);
        rebasingToken.deposit(DEFAULT_AMOUNT, receiver);

        //check balance after deposit
        assertEq(rebasingToken.balanceOf(receiver), DEFAULT_AMOUNT);
        assertEq(rebasingToken.totalAssets(), DEFAULT_AMOUNT);
        assertEq(rebasingToken.totalSupply(), DEFAULT_AMOUNT); // Checks the amount of yDUSD minted
        assertEq(token.balanceOf(_diamond), 0);
        assertEq(token.balanceOf(receiver), 0); //receiver no longer owns the dusd...
        assertEq(token.balanceOf(_yDUSD), DEFAULT_AMOUNT); //...but yDUSD owns the dusd now
        assertEq(token.totalSupply(), DEFAULT_AMOUNT);
    }

    // Check what the asset and supply will be after newDebt occurs via discount
    function test_yDUSD_NewDebt() public {
        assertEq(rebasingToken.totalAssets(), 0);
        assertEq(rebasingToken.totalSupply(), 0);
        assertEq(rebasingToken.balanceOf(receiver), 0);
        assertEq(rebasingToken.balanceOf(_diamond), 0);

        vm.prank(receiver);
        rebasingToken.deposit(DEFAULT_AMOUNT, receiver);
        assertEq(rebasingToken.totalSupply(), DEFAULT_AMOUNT);
        assertEq(rebasingToken.balanceOf(receiver), DEFAULT_AMOUNT);
        assertEq(rebasingToken.balanceOf(_diamond), 0);

        // mock generate newDebt
        vm.prank(_diamond);
        token.mint(sender, DEFAULT_AMOUNT);
        vm.prank(sender);
        token.transfer(_yDUSD, DEFAULT_AMOUNT);

        assertEq(rebasingToken.totalAssets(), DEFAULT_AMOUNT * 2);
        assertEq(rebasingToken.totalSupply(), DEFAULT_AMOUNT);
        assertEq(rebasingToken.balanceOf(receiver), DEFAULT_AMOUNT);

        assertEq(rebasingToken.convertToShares(DEFAULT_AMOUNT), DEFAULT_AMOUNT / 2);
        assertApproxEqAbs(rebasingToken.convertToAssets(DEFAULT_AMOUNT), DEFAULT_AMOUNT * 2, MAX_DELTA_SMALL);
    }

    function test_yDUSD_Withdraw() public {
        // Skip to prevent within7DaysFromLastDiscount from reverting
        skip(7 days);
        assertEq(rebasingToken.totalAssets(), 0);
        assertEq(rebasingToken.totalSupply(), 0);
        assertEq(rebasingToken.balanceOf(receiver), 0);
        assertEq(rebasingToken.balanceOf(_diamond), 0);

        vm.prank(receiver);
        rebasingToken.deposit(DEFAULT_AMOUNT, receiver);
        assertEq(rebasingToken.totalAssets(), DEFAULT_AMOUNT);
        assertEq(rebasingToken.totalSupply(), DEFAULT_AMOUNT);
        assertEq(rebasingToken.balanceOf(receiver), DEFAULT_AMOUNT);
        assertEq(rebasingToken.balanceOf(_diamond), 0);

        vm.prank(receiver);
        vm.expectRevert(Errors.ERC4626ProposeWithdrawFirst.selector);
        rebasingToken.withdraw(DEFAULT_AMOUNT, receiver, receiver);

        vm.prank(receiver);
        vm.expectRevert(Errors.ERC4626AmountProposedTooLow.selector);
        rebasingToken.proposeWithdraw(0);

        vm.prank(receiver);
        vm.expectRevert(Errors.ERC4626AmountProposedTooLow.selector);
        rebasingToken.proposeWithdraw(1);

        vm.prank(receiver);
        vm.expectRevert(Errors.ERC4626WithdrawMoreThanMax.selector);
        rebasingToken.proposeWithdraw(DEFAULT_AMOUNT + 1 wei);

        assertLe(rebasingToken.getAmountProposed(receiver), 1);
        assertLe(rebasingToken.getTimeProposed(receiver), 1);

        vm.prank(receiver);
        rebasingToken.proposeWithdraw(DEFAULT_AMOUNT);

        assertEq(rebasingToken.getAmountProposed(receiver), DEFAULT_AMOUNT);
        assertGt(rebasingToken.getTimeProposed(receiver), 1);

        vm.prank(receiver);
        vm.expectRevert(Errors.ERC4626ExistingWithdrawalProposal.selector);
        rebasingToken.proposeWithdraw(DEFAULT_AMOUNT);

        vm.prank(receiver);
        vm.expectRevert(Errors.ERC4626WaitLongerBeforeWithdrawing.selector);
        rebasingToken.withdraw(DEFAULT_AMOUNT, receiver, receiver);

        skip(7 days);

        vm.prank(receiver);
        rebasingToken.withdraw(DEFAULT_AMOUNT, receiver, receiver);
        assertEq(rebasingToken.totalSupply(), 0);
        assertEq(rebasingToken.totalSupply(), 0);
        assertEq(rebasingToken.balanceOf(receiver), 0);

        //Can propose again after successful withdraw
        vm.prank(receiver);
        rebasingToken.deposit(DEFAULT_AMOUNT, receiver);
        vm.prank(receiver);
        rebasingToken.proposeWithdraw(DEFAULT_AMOUNT);
    }

    function test_yDUSD_CancelWithdrawProposal() public {
        // Skip to prevent within7DaysFromLastDiscount from reverting
        skip(7 days);
        vm.prank(receiver);
        rebasingToken.deposit(DEFAULT_AMOUNT, receiver);

        assertLe(rebasingToken.getAmountProposed(receiver), 1);
        assertLe(rebasingToken.getTimeProposed(receiver), 1);

        vm.prank(receiver);
        rebasingToken.proposeWithdraw(DEFAULT_AMOUNT);

        assertEq(rebasingToken.getAmountProposed(receiver), DEFAULT_AMOUNT);
        assertGt(rebasingToken.getTimeProposed(receiver), 1);

        vm.prank(receiver);
        vm.expectRevert(Errors.ERC4626ExistingWithdrawalProposal.selector);
        rebasingToken.proposeWithdraw(DEFAULT_AMOUNT);

        skip(C.WITHDRAW_WAIT_TIME + C.MAX_WITHDRAW_TIME);
        vm.prank(receiver);
        vm.expectRevert(Errors.ERC4626MaxWithdrawTimeHasElapsed.selector);
        rebasingToken.withdraw(DEFAULT_AMOUNT, receiver, receiver);

        vm.prank(receiver);
        rebasingToken.cancelWithdrawProposal();

        //values reset
        assertLe(rebasingToken.getAmountProposed(receiver), 1);
        assertLe(rebasingToken.getTimeProposed(receiver), 1);

        vm.prank(receiver);
        vm.expectRevert(Errors.ERC4626ProposeWithdrawFirst.selector);
        rebasingToken.cancelWithdrawProposal();

        // Can propose again after cancelling
        vm.prank(receiver);
        rebasingToken.proposeWithdraw(DEFAULT_AMOUNT);

        //Can withdraw now
        skip(C.WITHDRAW_WAIT_TIME);
        vm.prank(receiver);
        rebasingToken.withdraw(DEFAULT_AMOUNT, receiver, receiver);
    }

    // Discount

    function test_yDUSD_Discount_Withdraw_OneUser() public {
        uint64 discountPenaltyFee = uint64(diamond.getAssetNormalizedStruct(asset).discountPenaltyFee);
        //User 1 despoit DUSD into vault to get yDUSD
        assertEq(token.balanceOf(_yDUSD), 0);
        vm.prank(receiver);
        rebasingToken.deposit(DEFAULT_AMOUNT, receiver);
        assertEq(rebasingToken.totalAssets(), DEFAULT_AMOUNT);
        assertEq(rebasingToken.totalSupply(), DEFAULT_AMOUNT);
        assertEq(rebasingToken.balanceOf(receiver), DEFAULT_AMOUNT);
        assertEq(rebasingToken.balanceOf(_diamond), 0);
        assertEq(rebasingToken.balanceOf(_yDUSD), 0);
        assertEq(token.balanceOf(_yDUSD), DEFAULT_AMOUNT);

        //Create discount to generate newDebt
        uint88 newDebt = uint88(discountSetUp());
        assertEq(rebasingToken.totalAssets(), DEFAULT_AMOUNT + newDebt);
        assertEq(rebasingToken.totalSupply(), DEFAULT_AMOUNT);
        assertEq(rebasingToken.balanceOf(receiver), DEFAULT_AMOUNT);
        assertEq(rebasingToken.balanceOf(_diamond), 0);
        assertEq(rebasingToken.balanceOf(_yDUSD), 0);
        assertEq(token.balanceOf(_yDUSD), DEFAULT_AMOUNT + newDebt);

        // Match at oracle
        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, extra);
        fundLimitAskOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, extra);

        skip(C.DISCOUNT_WAIT_TIME);

        //User 1 withdraws yDUSD and gets back more DUSD than original amount
        // @dev Roughly DEFAULT_AMOUNT + newDebt, but rounded down
        uint88 withdrawAmount = 54999999999999999999990;
        vm.prank(receiver);
        rebasingToken.proposeWithdraw(withdrawAmount);

        //Skip 7 days to avoid ERC4626WaitLongerBeforeWithdrawing error
        skip(7 days);
        assertEq(token.balanceOf(receiver), 0);
        vm.prank(receiver);
        rebasingToken.withdraw(withdrawAmount, receiver, receiver);
        assertEq(token.balanceOf(receiver), withdrawAmount);
        // receiver receives more than they originally deposited
        assertGt(withdrawAmount, DEFAULT_AMOUNT);
    }

    function test_yDUSD_Discount_Withdraw_TwoUsers() public {
        uint64 discountPenaltyFee = uint64(diamond.getAssetNormalizedStruct(asset).discountPenaltyFee);

        //Also mint dusd to sender
        vm.prank(_diamond);
        token.mint(sender, DEFAULT_AMOUNT);

        //User 1 despoit DUSD into vault to get yDUSD
        assertEq(token.balanceOf(_yDUSD), 0);
        vm.prank(receiver);
        rebasingToken.deposit(DEFAULT_AMOUNT, receiver);
        vm.prank(sender);
        rebasingToken.deposit(DEFAULT_AMOUNT, sender);

        assertEq(rebasingToken.totalAssets(), DEFAULT_AMOUNT * 2);
        assertEq(rebasingToken.totalSupply(), DEFAULT_AMOUNT * 2);
        assertEq(rebasingToken.balanceOf(receiver), DEFAULT_AMOUNT);
        assertEq(rebasingToken.balanceOf(sender), DEFAULT_AMOUNT);
        assertEq(rebasingToken.balanceOf(_diamond), 0);
        assertEq(rebasingToken.balanceOf(_yDUSD), 0);
        assertEq(token.balanceOf(_yDUSD), DEFAULT_AMOUNT * 2);

        //Create discount to generate newDebt
        uint88 newDebt = uint88(discountSetUp());
        assertEq(rebasingToken.totalAssets(), DEFAULT_AMOUNT * 2 + newDebt);
        assertEq(rebasingToken.totalSupply(), DEFAULT_AMOUNT * 2);
        assertEq(rebasingToken.balanceOf(receiver), DEFAULT_AMOUNT);
        assertEq(rebasingToken.balanceOf(sender), DEFAULT_AMOUNT);
        assertEq(rebasingToken.balanceOf(_diamond), 0);
        assertEq(rebasingToken.balanceOf(_yDUSD), 0);
        assertEq(token.balanceOf(_yDUSD), DEFAULT_AMOUNT * 2 + newDebt);

        // Match at oracle
        fundLimitBidOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, extra);
        fundLimitAskOpt(DEFAULT_PRICE, DEFAULT_AMOUNT, extra);

        skip(C.DISCOUNT_WAIT_TIME);

        //User 1 withdraws yDUSD and gets back more DUSD than original amount
        // @dev Roughly (DEFAULT_AMOUNT + newDebt) / 2 based on number of users in vault. (rounded down)
        // For reference: If only 1 user in vault, receiver could withdraw up to 54999999999999999999990
        uint88 withdrawAmount = 27500000000000000000000;
        vm.prank(receiver);
        rebasingToken.proposeWithdraw(withdrawAmount);
        vm.prank(sender);
        rebasingToken.proposeWithdraw(withdrawAmount);

        //Skip 7 days to avoid ERC4626WaitLongerBeforeWithdrawing error
        skip(7 days);
        assertEq(token.balanceOf(receiver), 0);
        assertEq(token.balanceOf(sender), 0);
        vm.prank(receiver);
        rebasingToken.withdraw(withdrawAmount, receiver, receiver);
        vm.prank(sender);
        rebasingToken.withdraw(withdrawAmount, sender, sender);
        assertEq(token.balanceOf(receiver), withdrawAmount);
        assertEq(token.balanceOf(sender), withdrawAmount);
        //Both receiver and sender receives more than they originally deposited
        assertGt(withdrawAmount, DEFAULT_AMOUNT);
    }
}
