// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Vm} from "forge-std/Vm.sol";

import {ISwapRouter} from "contracts/interfaces/ISwapRouter.sol";
import {IWETH} from "contracts/interfaces/IWETH.sol";
import {U256, U88} from "contracts/libraries/PRBMathHelper.sol";
import {C, VAULT} from "contracts/libraries/Constants.sol";
import {ForkHelper} from "test/fork/ForkHelper.sol";

import {console} from "contracts/libraries/console.sol";

contract BridgeRouterForkTest is ForkHelper {
    using U256 for uint256;
    using U88 for uint88;

    uint88 initialDeposit;
    uint88 bridgeCreditReth;
    uint88 bridgeCreditSteth;
    address public constant UNIV3_ROUTER = 0xE592427A0AEce92De3Edee1F18E0157C05861564;

    function setUp() public virtual override {
        forkBlock = bridgeBlock;
        super.setUp();

        initialDeposit = 100 ether;
        deal(sender, initialDeposit);

        // Confirm rETH has market premium relative to stETH
        assertGt(diamond.getWithdrawalFeePct(VAULT.BRIDGE_RETH, _bridgeReth, _bridgeSteth), 0);
        assertEq(diamond.getWithdrawalFeePct(VAULT.BRIDGE_STETH, _bridgeReth, _bridgeSteth), 0);
    }

    function bridgeWithdrawSetup() public {
        vm.startPrank(sender);
        // Just give rETH bc deposit pool is full in this block
        deal(_reth, sender, initialDeposit);
        reth.approve(_bridgeReth, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);

        diamond.deposit(_bridgeReth, initialDeposit);
        // Get stETH the "real" way
        diamond.depositEth{value: initialDeposit}(_bridgeSteth);

        bridgeCreditReth = initialDeposit.mulU88(bridgeReth.getUnitDethValue()) + 1 wei; // rounding
        bridgeCreditSteth = initialDeposit - 1 wei; // rounding
        assertEq(diamond.getVaultUserStruct(vault, sender).ethEscrowed, bridgeCreditReth + bridgeCreditSteth);
        assertEq(diamond.getVaultUserStruct(vault, sender).bridgeCreditReth, bridgeCreditReth);
        assertEq(diamond.getVaultUserStruct(vault, sender).bridgeCreditSteth, bridgeCreditSteth);
        assertEq(diamond.getVaultStruct(vault).dethTotal, bridgeCreditReth + bridgeCreditSteth);
    }

    function zeroBridge(uint256 bridgeToZero) public {
        if (bridgeToZero == VAULT.BRIDGE_RETH) {
            diamond.setEthEscrowed(extra, bridgeCreditReth);
            diamond.setBridgeCredit(extra, bridgeCreditReth, 0);
            vm.startPrank(extra);
            diamond.withdraw(_bridgeReth, bridgeCreditReth);
            vm.startPrank(sender);
        } else {
            diamond.setEthEscrowed(extra, bridgeCreditSteth);
            diamond.setBridgeCredit(extra, 0, bridgeCreditSteth);
            vm.startPrank(extra);
            diamond.withdraw(_bridgeSteth, bridgeCreditSteth);
            vm.startPrank(sender);
        }
    }

    function generateYield(uint256 bridge, uint256 amount) public returns (uint88) {
        if (bridge == VAULT.BRIDGE_RETH) {
            uint88 senderAmt = uint88(initialDeposit + amount);
            uint256 senderAmtInReth = reth.getRethValue(senderAmt);
            deal(_reth, _bridgeReth, senderAmtInReth);
            diamond.updateYield(vault);
            diamond.setEthEscrowed(sender, senderAmt); // send yield to sender
            return senderAmt;
        } else {
            // Fake yield with deposit from extra
            // @dev can't use vm.deal with rebasing token
            deal(extra, amount);
            vm.stopPrank();
            vm.startPrank(extra);
            diamond.depositEth{value: amount}(_bridgeSteth);
            vm.startPrank(sender);
            // Send fake yield to sender
            uint88 senderAmt = uint88(bridgeCreditSteth + amount - 1 wei); // Account for rounding
            diamond.setEthEscrowed(sender, senderAmt);
            return senderAmt;
        }
    }

    function checkAsserts(uint256 bridge, uint256 assessableAmt, uint256 senderAmt) public view {
        assertEq(diamond.getVaultUserStruct(vault, sender).bridgeCreditReth, 0 ether);
        assertEq(diamond.getVaultUserStruct(vault, sender).bridgeCreditSteth, 0 ether);
        assertEq(diamond.getVaultUserStruct(vault, sender).ethEscrowed, 0);
        uint256 feeP = diamond.getWithdrawalFeePct(bridge, _bridgeReth, _bridgeSteth);
        uint256 fee = feeP.mul(assessableAmt);
        uint256 withdrawAmt = senderAmt - fee;
        assertEq(diamond.getVaultStruct(vault).dethTotal, fee);
        assertGt(assessableAmt, fee);
        if (bridge == VAULT.BRIDGE_RETH) {
            assertApproxEqAbs(bridgeReth.getDethValue(), fee, MAX_DELTA_SMALL);
            assertApproxEqAbs(reth.balanceOf(sender), reth.getRethValue(withdrawAmt), MAX_DELTA_SMALL);
        } else {
            assertApproxEqAbs(bridgeSteth.getDethValue(), fee, MAX_DELTA_SMALL);
            assertApproxEqAbs(steth.balanceOf(sender), withdrawAmt, MAX_DELTA_SMALL);
        }
    }

    function fakeStethPremium() public {
        ISwapRouter v3router = ISwapRouter(UNIV3_ROUTER);

        IWETH weth = IWETH(C.WETH);
        IERC20 wstETH = IERC20(VAULT.WSTETH);

        uint24 fee = 100;

        uint256 amount = 9000 ether;
        // Fund WETH
        deal(extra, amount);
        vm.startPrank(extra);
        weth.deposit{value: amount}();
        weth.approve(UNIV3_ROUTER, type(uint256).max);
        // Swap to increase stETH premium
        uint256 _before = wstETH.balanceOf(extra);
        v3router.exactInput(
            ISwapRouter.ExactInputParams({
                path: abi.encodePacked(C.WETH, fee, VAULT.WSTETH),
                recipient: extra,
                deadline: block.timestamp,
                amountIn: amount,
                amountOutMinimum: 0
            })
        );
        uint256 _after = wstETH.balanceOf(extra);
        assertGt(_after, _before);

        skip(30 minutes); // Update TWAP
        // Confirm stETH has market premium relative to rETH
        assertEq(diamond.getWithdrawalFeePct(VAULT.BRIDGE_RETH, _bridgeReth, _bridgeSteth), 0);
        assertGt(diamond.getWithdrawalFeePct(VAULT.BRIDGE_STETH, _bridgeReth, _bridgeSteth), 0);
    }

    /// rETH Premium
    function testFork_BridgeWithdrawRethPastCredit() public {
        bridgeWithdrawSetup();
        // Use STETH credit
        diamond.withdraw(_bridgeSteth, bridgeCreditSteth);
        // Generate yield
        uint88 senderAmt = generateYield(VAULT.BRIDGE_RETH, 200 ether);
        // Withdraw RETH using just RETH credit
        diamond.withdraw(_bridgeReth, senderAmt);
        // Check Asserts
        uint256 assessableAmt = senderAmt - bridgeCreditReth;
        checkAsserts(VAULT.BRIDGE_RETH, assessableAmt, senderAmt);
    }

    function testFork_BridgeWithdrawRethPastCreditWithStethCreditNoLeftover() public {
        bridgeWithdrawSetup();
        // Artificially zero out stEth bridge balance
        zeroBridge(VAULT.BRIDGE_STETH);
        // Generate yield
        uint88 senderAmt = generateYield(VAULT.BRIDGE_RETH, 200 ether);
        // Withdraw RETH using both RETH and STETH credit
        diamond.withdraw(_bridgeReth, senderAmt);
        // Check Asserts
        uint256 assessableAmt = senderAmt - bridgeCreditReth - bridgeCreditSteth;
        checkAsserts(VAULT.BRIDGE_RETH, assessableAmt, senderAmt);
    }

    function testFork_BridgeWithdrawStethPastCredit() public {
        bridgeWithdrawSetup();
        // Use RETH credit
        diamond.withdraw(_bridgeReth, bridgeCreditReth);
        // Generate Yield
        uint88 senderAmt = generateYield(VAULT.BRIDGE_STETH, 200 ether);
        // Withdraw STETH using just STETH credit
        diamond.withdraw(_bridgeSteth, senderAmt);
        // Check Asserts
        uint256 assessableAmt = senderAmt - bridgeCreditSteth;
        checkAsserts(VAULT.BRIDGE_STETH, assessableAmt, senderAmt);
    }

    function testFork_BridgeWithdrawStethPastCreditWithRethCreditNoLeftover() public {
        bridgeWithdrawSetup();
        // Artificially zero out rETH bridge balance
        zeroBridge(VAULT.BRIDGE_RETH);
        // Generate Yield
        uint88 senderAmt = generateYield(VAULT.BRIDGE_STETH, 200 ether);
        // Withdraw STETH using both RETH and STETH credit
        diamond.withdraw(_bridgeSteth, senderAmt);
        // Check Asserts
        uint256 assessableAmt = senderAmt - bridgeCreditSteth - bridgeCreditReth;
        checkAsserts(VAULT.BRIDGE_STETH, assessableAmt, senderAmt);
    }

    function testFork_BridgeWithdrawRethPastCreditNegativeYield() public {
        bridgeWithdrawSetup();
        // Use STETH credit
        diamond.withdraw(_bridgeSteth, bridgeCreditSteth);
        assertEq(diamond.getVaultUserStruct(vault, sender).bridgeCreditSteth, 0 ether);
        // Generate Yield
        uint88 senderAmt = generateYield(VAULT.BRIDGE_RETH, 200 ether); // 300 ether total
        // Negative Yield
        uint256 negYieldAmt = reth.getRethValue(150 ether); // -150 ether of slashing
        deal(_reth, _bridgeReth, negYieldAmt);
        uint256 negYieldFactor = (bridgeReth.getDethValue()).div(senderAmt);
        // Withdraw RETH past credit
        diamond.withdraw(_bridgeReth, senderAmt);
        // Check Asserts
        uint256 assessableAmt = senderAmt - bridgeCreditReth;
        uint256 feeP = diamond.getWithdrawalFeePct(VAULT.BRIDGE_RETH, _bridgeReth, _bridgeSteth);
        uint256 fee = feeP.mul(assessableAmt);
        uint256 withdrawAmtInEth = (senderAmt - fee).mul(negYieldFactor);
        uint256 withdrawAmtInReth = reth.getRethValue(withdrawAmtInEth);
        assertEq(diamond.getVaultUserStruct(vault, sender).ethEscrowed, 0, "1");
        assertEq(diamond.getVaultStruct(vault).dethTotal, fee, "2");
        assertApproxEqAbs(bridgeSteth.getDethValue(), 0, MAX_DELTA_SMALL, "3");
        assertApproxEqAbs(steth.balanceOf(sender), initialDeposit, MAX_DELTA_SMALL, "4");
        assertApproxEqAbs(bridgeReth.getDethValue(), fee.mul(negYieldFactor), MAX_DELTA_SMALL, "5");
        assertApproxEqAbs(reth.balanceOf(sender), withdrawAmtInReth, MAX_DELTA, "6");
    }

    function testFork_BridgeWithdrawStethPastCreditNegativeYield() public {
        bridgeWithdrawSetup();
        // Generate Yield
        uint88 senderAmt = generateYield(VAULT.BRIDGE_STETH, 200 ether); // 300 ether total
        senderAmt += bridgeCreditReth;
        diamond.setEthEscrowed(sender, senderAmt);
        // Negative Yield
        deal(_reth, _bridgeReth, 0); // -100 ether of slashing
        diamond.updateYield(vault); // Realize slashing
        uint256 negYieldFactor = (bridgeSteth.getDethValue()).div(senderAmt);
        // Withdraw STETH past credit
        diamond.withdraw(_bridgeSteth, senderAmt);
        // Check Asserts
        uint256 assessableAmt = senderAmt - bridgeCreditReth - bridgeCreditSteth;
        uint256 feeP = diamond.getWithdrawalFeePct(VAULT.BRIDGE_STETH, _bridgeReth, _bridgeSteth);
        uint256 fee = feeP.mul(assessableAmt);
        uint256 withdrawAmtInEth = (senderAmt - fee).mul(negYieldFactor);
        assertEq(diamond.getVaultUserStruct(vault, sender).ethEscrowed, 0, "1");
        assertEq(diamond.getVaultStruct(vault).dethTotal, fee, "2");
        assertApproxEqAbs(bridgeSteth.getDethValue(), fee.mul(negYieldFactor), MAX_DELTA, "3");
        assertApproxEqAbs(steth.balanceOf(sender), withdrawAmtInEth, MAX_DELTA, "4");
        assertApproxEqAbs(bridgeReth.getDethValue(), 0, MAX_DELTA_SMALL, "5");
        assertApproxEqAbs(reth.balanceOf(sender), 0, MAX_DELTA, "6");
    }

    /// stETH Premium
    function testFork_BridgeWithdrawRethPastCredit_StethPremium() public {
        fakeStethPremium();
        testFork_BridgeWithdrawRethPastCredit();
    }

    function testFork_BridgeWithdrawRethPastCreditWithStethCreditNoLeftover_StethPremium() public {
        fakeStethPremium();
        testFork_BridgeWithdrawRethPastCreditWithStethCreditNoLeftover();
    }

    function testFork_BridgeWithdrawStethPastCredit_StethPremium() public {
        fakeStethPremium();
        testFork_BridgeWithdrawStethPastCredit();
    }

    function testFork_BridgeWithdrawStethPastCreditWithRethCreditNoLeftover_StethPremium() public {
        fakeStethPremium();
        testFork_BridgeWithdrawStethPastCreditWithRethCreditNoLeftover();
    }

    function testFork_BridgeWithdrawRethPastCreditNegativeYield_StethPremium() public {
        fakeStethPremium();
        testFork_BridgeWithdrawRethPastCreditNegativeYield();
    }

    function testFork_BridgeWithdrawStethPastCreditNegativeYield_StethPremium() public {
        fakeStethPremium();
        testFork_BridgeWithdrawStethPastCreditNegativeYield();
    }
}
