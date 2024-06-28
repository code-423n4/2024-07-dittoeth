// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {InvariantsBase} from "./InvariantsBase.sol";
import {Handler} from "./Handler.sol";

import {console} from "contracts/libraries/console.sol";

/* solhint-disable */
/// @dev This contract deploys the target contract, the Handler, adds the Handler's actions to the invariant fuzzing
/// @dev targets, then defines invariants that should always hold throughout any invariant run.
/// @dev Similar to InvariantsOrderBook but with a greater focus on yield
contract InvariantsPriceDiscount is InvariantsBase {
    function setUp() public override {
        super.setUp();

        // @dev duplicate the selector to increase the distribution of certain handler calls
        selectors = [
            // Bridge
            Handler.deposit.selector,
            // OrderBook
            Handler.createLimitBid.selector,
            Handler.createLimitShort.selector,
            Handler.createLimitBidDiscounted.selector,
            Handler.createLimitAskDiscounted.selector
            // ForcedBid
            // Handler.primaryLiquidation.selector,
            // Handler.exitShort.selector
        ];

        targetSelector(FuzzSelector({addr: address(s_handler), selectors: selectors}));
        targetContract(address(s_handler));
    }

    function statefulFuzz_Discount_ErcEscrowedPlusAssetBalanceEqTotalDebt() public view {
        vault_ErcEscrowedPlusAssetBalanceEqTotalDebt();
    }

    function statefulFuzz_Discount_DethTotal() public {
        vault_DethTotal();

        //Occurences of discounts
        console.log("discounts", s_handler.ghost_matchAtDiscount());
    }
}
