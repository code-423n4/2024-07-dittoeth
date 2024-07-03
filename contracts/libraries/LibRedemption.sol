// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {U256, U104, U88, U80, U64, U32} from "contracts/libraries/PRBMathHelper.sol";

import {STypes, SR} from "contracts/libraries/DataTypes.sol";
import {AppStorage, appStorage} from "contracts/libraries/AppStorage.sol";
import {C} from "contracts/libraries/Constants.sol";
import {LibOrders} from "contracts/libraries/LibOrders.sol";
import {LibShortRecord} from "contracts/libraries/LibShortRecord.sol";

library LibRedemption {
    using LibShortRecord for STypes.ShortRecord;
    using U256 for uint256;
    using U104 for uint104;
    using U88 for uint88;
    using U80 for uint80;
    using U64 for uint64;
    using U32 for uint32;

    function validRedemptionSR(STypes.ShortRecord storage shortRecord, address proposer, address shorter, uint256 minShortErc)
        internal
        view
        returns (bool)
    {
        // @dev Matches check in onlyValidShortRecord with a more restrictive ercDebt condition
        // @dev Proposer can't redeem on self or the tappSR
        if (shortRecord.status == SR.Closed || shortRecord.ercDebt < minShortErc || proposer == shorter || shorter == address(this))
        {
            return false;
        } else {
            return true;
        }
    }

    // @dev inspired by https://docs.liquity.org/faq/lusd-redemptions#how-is-the-redemption-fee-calculated
    function calculateNewBaseRate(STypes.Asset storage Asset, uint88 ercDebtRedeemed) internal view returns (uint256 newBaseRate) {
        uint32 protocolTime = LibOrders.getOffsetTime();
        uint256 secondsPassed = uint256((protocolTime - Asset.lastRedemptionTime));
        uint256 decayFactor = C.SECONDS_DECAY_FACTOR.powu(secondsPassed);
        uint256 decayedBaseRate = Asset.baseRate.mulU64(decayFactor);
        // @dev Calculate Asset.ercDebt prior to proposal
        uint104 totalAssetErcDebt = (Asset.ercDebt).mulU104(C.BETA);
        // @dev Derived via this forumula: baseRateNew = baseRateOld + redeemedLUSD / (2 * totalLUSD)
        uint256 redeemedDUSDFraction = ercDebtRedeemed.div(totalAssetErcDebt);
        newBaseRate = LibOrders.min((decayedBaseRate + redeemedDUSDFraction), 1 ether); // cap baseRate at a maximum of 100%
    }

    // @dev inspired by https://docs.liquity.org/faq/lusd-redemptions#how-is-the-redemption-fee-calculated
    function calculateRedemptionFee(uint64 baseRate, uint88 colRedeemed) internal pure returns (uint88 redemptionFee) {
        uint256 redemptionRate = LibOrders.min((baseRate + 0.005 ether), 1 ether);
        return uint88(redemptionRate.mul(colRedeemed)); // @dev(safe-cast)
    }

    function calculateTimeToDispute(uint256 lastCR, uint32 protocolTime) internal pure returns (uint32 timeToDispute) {
        /*
        +-------+------------+
        | CR(X) |  Hours(Y)  |
        +-------+------------+
        | 1.1   |     0      |
        | 1.2   |    .333    |
        | 1.3   |    .75     |
        | 1.5   |    1.5     |
        | 1.7   |     3      |
        | 2.0   |     6      |
        +-------+------------+

        Creating fixed points and interpolating between points on the graph without using exponentials
        Using simple y = mx + b formula
        
        where x = currentCR - lastCR
        m = (y2-y1)/(x2-x1)
        b = last fixed point (Y)
        */

        uint256 m;

        if (lastCR > 1.7 ether) {
            m = uint256(3 ether).div(0.3 ether);
            timeToDispute = protocolTime + uint32((m.mul(lastCR - 1.7 ether) + 3 ether) * 1 hours / 1 ether);
        } else if (lastCR > 1.5 ether) {
            m = uint256(1.5 ether).div(0.2 ether);
            timeToDispute = protocolTime + uint32((m.mul(lastCR - 1.5 ether) + 1.5 ether) * 1 hours / 1 ether);
        } else if (lastCR > 1.3 ether) {
            m = uint256(0.75 ether).div(0.2 ether);
            timeToDispute = protocolTime + uint32((m.mul(lastCR - 1.3 ether) + 0.75 ether) * 1 hours / 1 ether);
        } else if (lastCR > 1.2 ether) {
            m = uint256(0.417 ether).div(0.1 ether);
            timeToDispute = protocolTime + uint32((m.mul(lastCR - 1.2 ether) + C.ONE_THIRD) * 1 hours / 1 ether);
        } else if (lastCR > 1.1 ether) {
            m = uint256(C.ONE_THIRD.div(0.1 ether));
            timeToDispute = protocolTime + uint32(m.mul(lastCR - 1.1 ether) * 1 hours / 1 ether);
        } else {
            timeToDispute = 0;
        }
    }
}
