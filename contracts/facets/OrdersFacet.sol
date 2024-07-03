// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {U256, U104, U88} from "contracts/libraries/PRBMathHelper.sol";

import {IAsset as IERC20} from "interfaces/IAsset.sol";
import {IyDUSD} from "interfaces/IyDUSD.sol";
import {Modifiers} from "contracts/libraries/AppStorage.sol";
import {Errors} from "contracts/libraries/Errors.sol";
import {STypes, MTypes, SR, O} from "contracts/libraries/DataTypes.sol";
import {LibAsset} from "contracts/libraries/LibAsset.sol";
import {LibOrders} from "contracts/libraries/LibOrders.sol";
import {LibTStore} from "contracts/libraries/LibTStore.sol";
import {C} from "contracts/libraries/Constants.sol";

// import {console} from "contracts/libraries/console.sol";

contract OrdersFacet is Modifiers {
    using U256 for uint256;
    using U104 for uint104;
    using U88 for uint88;
    using LibOrders for mapping(address => mapping(uint16 => STypes.Order));

    /**
     * @notice Cancels unfilled bid on market
     *
     * @param asset The market that will be impacted
     * @param id Id of bid
     */
    function cancelBid(address asset, uint16 id) external onlyValidAsset(asset) nonReentrant {
        STypes.Order storage bid = s.bids[asset][id];
        if (msg.sender != bid.addr) revert Errors.NotOwner();

        LibOrders.cancelBid(asset, id);
    }

    /**
     * @notice Cancels unfilled ask on market
     *
     * @param asset The market that will be impacted
     * @param id Id of ask
     */
    function cancelAsk(address asset, uint16 id) external onlyValidAsset(asset) nonReentrant {
        STypes.Order storage ask = s.asks[asset][id];
        if (msg.sender != ask.addr) revert Errors.NotOwner();

        LibOrders.cancelAsk(asset, id);
    }

    /**
     * @notice Cancels unfilled short on market
     *
     * @param asset The market that will be impacted
     * @param id Id of short
     */
    function cancelShort(address asset, uint16 id) external onlyValidAsset(asset) nonReentrant {
        STypes.Order storage short = s.shorts[asset][id];
        if (msg.sender != short.addr) revert Errors.NotOwner();
        if (short.orderType != O.LimitShort) revert Errors.NotActiveOrder();
        LibOrders.cancelShort(asset, id);
    }

    /**
     * @notice Used to clear orderbook and/or to prevent DOS
     *
     * @param asset The market that will be impacted
     * @param orderType Order type to be cancelled
     * @param lastOrderId Id of the order in the last position, farthest from HEAD
     * @param numOrdersToCancel Number of orders to cancel, includinf the lastOrderId
     */
    function cancelOrderFarFromOracle(address asset, O orderType, uint16 lastOrderId, uint16 numOrdersToCancel)
        external
        onlyAdminOrDAO
        onlyValidAsset(asset)
        nonReentrant
    {
        if (s.asset[asset].orderIdCounter < 65000) revert Errors.OrderIdCountTooLow();

        if (numOrdersToCancel > 1000) revert Errors.CannotCancelMoreThan1000Orders();

        if (orderType == O.LimitBid && s.bids[asset][lastOrderId].nextId == C.TAIL) {
            cancelManyBids(asset, lastOrderId, numOrdersToCancel);
        } else if (orderType == O.LimitAsk && s.asks[asset][lastOrderId].nextId == C.TAIL) {
            cancelManyAsks(asset, lastOrderId, numOrdersToCancel);
        } else if (orderType == O.LimitShort && s.shorts[asset][lastOrderId].nextId == C.TAIL) {
            cancelManyShorts(asset, lastOrderId, numOrdersToCancel);
        } else {
            revert Errors.NotLastOrder();
        }
    }

    function cancelManyBids(address asset, uint16 lastOrderId, uint16 numOrdersToCancel) internal {
        uint16 prevId;
        uint16 currentId = lastOrderId;
        for (uint8 i; i < numOrdersToCancel;) {
            prevId = s.bids[asset][currentId].prevId;
            LibOrders.cancelBid(asset, currentId);
            currentId = prevId;
            unchecked {
                ++i;
            }
        }
    }

    function cancelManyAsks(address asset, uint16 lastOrderId, uint16 numOrdersToCancel) internal {
        uint16 prevId;
        uint16 currentId = lastOrderId;
        for (uint8 i; i < numOrdersToCancel;) {
            prevId = s.asks[asset][currentId].prevId;
            LibOrders.cancelAsk(asset, currentId);
            currentId = prevId;
            unchecked {
                ++i;
            }
        }
    }

    function cancelManyShorts(address asset, uint16 lastOrderId, uint16 numOrdersToCancel) internal {
        uint16 prevId;
        uint16 currentId = lastOrderId;
        for (uint8 i; i < numOrdersToCancel;) {
            prevId = s.shorts[asset][currentId].prevId;
            LibOrders.cancelShort(asset, currentId);
            currentId = prevId;
            unchecked {
                ++i;
            }
        }
    }

    // @dev Helper for handlePriceDiscount
    function _matchIsDiscounted(MTypes.HandleDiscount memory h) external onlyDiamond {
        STypes.Asset storage Asset = s.asset[h.asset];
        uint32 protocolTime = LibOrders.getOffsetTime();
        Asset.lastDiscountTime = protocolTime;
        // @dev Asset.initialDiscountTime used to calculate multiplier for discounts that occur nonstop for days (daysElapsed)
        if (Asset.initialDiscountTime <= 1 seconds) {
            // @dev Set only during first discount or when discount had been previously reset
            Asset.initialDiscountTime = protocolTime;
        }
        // @dev Cap the discount at 5% to prevent malicious attempt to overly increase ercDebt
        uint256 discountPct = LibOrders.min((h.savedPrice - h.price).div(h.savedPrice), 0.05 ether);
        // @dev Express duration of discount in days
        uint32 timeDiff = (protocolTime - Asset.initialDiscountTime) / 86400 seconds;
        uint32 daysElapsed = 1;
        if (timeDiff > 7) {
            // @dev Protect against situation where discount occurs, followed by long period of inactivity on orderbook
            Asset.initialDiscountTime = protocolTime;
        } else if (timeDiff > 1) {
            daysElapsed = timeDiff;
        }
        // @dev Penalties should occur more frequently if discounts persist many days
        // @dev Multiply discountPct by a multiplier to penalize larger discounts more
        discountPct = (discountPct * daysElapsed).mul(LibAsset.discountMultiplier(Asset));
        uint256 discount = 1 ether + discountPct;
        Asset.discountedErcMatched += uint104(h.ercAmount.mul(discount)); // @dev(safe-cast)
        uint256 pctOfDiscountedDebt = Asset.discountedErcMatched.div(h.ercDebt);
        // @dev Prevent Asset.ercDebt != the total ercDebt of SR's as a result of discounts penalty being triggered by forcedBid
        if (pctOfDiscountedDebt > C.DISCOUNT_THRESHOLD && !LibTStore.isForcedBid()) {
            // @dev Keep slot warm
            Asset.discountedErcMatched = 1 wei;
            uint64 discountPenaltyFee = uint64(LibAsset.discountPenaltyFee(Asset));
            Asset.ercDebtRate += discountPenaltyFee;
            // @dev TappSR should not be impacted by discount penalties
            STypes.ShortRecord storage tappSR = s.shortRecords[h.asset][address(this)][C.SHORT_STARTING_ID];
            tappSR.ercDebtRate = Asset.ercDebtRate;
            uint256 ercDebtMinusTapp = h.ercDebt - Asset.ercDebtFee;
            if (tappSR.status != SR.Closed) {
                ercDebtMinusTapp -= tappSR.ercDebt;
            }
            // @dev Increase global ercDebt to account for the increase debt owed by shorters
            uint104 newDebt = uint104(ercDebtMinusTapp.mul(discountPenaltyFee));
            Asset.ercDebt += newDebt;
            Asset.ercDebtFee += uint88(newDebt); // should be uint104?

            // @dev Mint dUSD to the yDUSD vault for
            // Note: Does not currently handle mutli-asset
            IERC20(h.asset).mint(s.yieldVault[h.asset], newDebt);
        }
    }
}
