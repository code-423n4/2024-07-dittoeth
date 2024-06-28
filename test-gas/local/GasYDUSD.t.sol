// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {U256, U88} from "contracts/libraries/PRBMathHelper.sol";

import {GasHelper} from "test-gas/GasHelper.sol";
import {C, VAULT} from "contracts/libraries/Constants.sol";
import {STypes, MTypes, SR} from "contracts/libraries/DataTypes.sol";

import {console} from "contracts/libraries/console.sol";

contract GasYDUSDProposeWithdrawFixture is GasHelper {
    using U88 for uint88;

    function setUp() public virtual override {
        super.setUp();
        skip(7 days);

        uint88 amount = DEFAULT_AMOUNT.mulU88(100 ether);
        //give receiver some dUSD
        vm.prank(_diamond);
        dusd.mint(receiver, amount);
        assertEq(dusd.balanceOf(receiver), amount);

        //give allowance to yDUSD on dUSD for receiver
        vm.prank(receiver);
        rebasingToken.approve(receiver, type(uint256).max);
        vm.prank(receiver);
        rebasingToken.approve(address(rebasingToken), type(uint256).max);
        vm.prank(receiver);
        dusd.approve(address(rebasingToken), type(uint256).max);

        //deposit into yDUSD vault
        vm.prank(receiver);
        rebasingToken.deposit(DEFAULT_AMOUNT, receiver);
    }

    function testGas_YDUSD_ProposeWithdraw() public {
        assertEq(rebasingToken.getAmountProposed(receiver), 0);
        vm.prank(receiver);
        startMeasuringGas("YDUSD-ProposeWithdraw");
        rebasingToken.proposeWithdraw(DEFAULT_AMOUNT);
        stopMeasuringGas();
        assertEq(rebasingToken.getAmountProposed(receiver), DEFAULT_AMOUNT);
    }
}

contract GasYDUSDWithdrawFixture is GasHelper {
    using U88 for uint88;

    function setUp() public virtual override {
        super.setUp();
        skip(7 days);

        uint88 amount = DEFAULT_AMOUNT.mulU88(100 ether);
        //give receiver some dUSD
        vm.prank(_diamond);
        dusd.mint(receiver, amount);
        assertEq(dusd.balanceOf(receiver), amount);

        //give allowance to yDUSD on dUSD for receiver
        vm.prank(receiver);
        rebasingToken.approve(receiver, type(uint256).max);
        vm.prank(receiver);
        rebasingToken.approve(address(rebasingToken), type(uint256).max);
        vm.prank(receiver);
        dusd.approve(address(rebasingToken), type(uint256).max);

        //deposit into yDUSD vault
        vm.prank(receiver);
        rebasingToken.deposit(DEFAULT_AMOUNT, receiver);

        assertEq(rebasingToken.getAmountProposed(receiver), 0);
        vm.prank(receiver);
        rebasingToken.proposeWithdraw(DEFAULT_AMOUNT);
        assertEq(rebasingToken.getAmountProposed(receiver), DEFAULT_AMOUNT);
    }

    function testGas_YDUSD_Withdraw() public {
        skip(C.WITHDRAW_WAIT_TIME);
        vm.prank(receiver);
        startMeasuringGas("YDUSD-Withdraw");
        rebasingToken.withdraw(DEFAULT_AMOUNT, receiver, receiver);
        stopMeasuringGas();
        assertEq(rebasingToken.getAmountProposed(receiver), 1);
    }

    function testGas_YDUSD_CancelWithdrawProposal() public {
        vm.prank(receiver);
        startMeasuringGas("YDUSD-CancelWithdrawProposal");
        rebasingToken.cancelWithdrawProposal();
        stopMeasuringGas();
        assertEq(rebasingToken.getAmountProposed(receiver), 1);
    }
}
