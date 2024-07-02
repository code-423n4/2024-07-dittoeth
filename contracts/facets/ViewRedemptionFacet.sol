// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {Modifiers} from "contracts/libraries/AppStorage.sol";
import {STypes, MTypes} from "contracts/libraries/DataTypes.sol";
import {LibOrders} from "contracts/libraries/LibOrders.sol";
import {LibRedemption} from "contracts/libraries/LibRedemption.sol";
import {LibBytes} from "contracts/libraries/LibBytes.sol";

contract ViewRedemptionFacet is Modifiers {
    function getTimeToDispute(uint256 lastCR) external view returns (uint32 timeToDispute) {
        return LibRedemption.calculateTimeToDispute(lastCR, LibOrders.getOffsetTime());
    }

    function getRedemptionFee(address asset, uint88 ercDebtRedeemed, uint88 colRedeemed)
        external
        view
        returns (uint88 redemptionFee)
    {
        uint256 newBaseRate = LibRedemption.calculateNewBaseRate(s.asset[asset], ercDebtRedeemed);
        return LibRedemption.calculateRedemptionFee(uint64(newBaseRate), colRedeemed);
    }

    function readProposalData(address asset, address redeemer)
        external
        view
        returns (uint32, uint32, uint80, uint80, MTypes.ProposalData[] memory)
    {
        STypes.AssetUser storage redeemerAssetUser = s.assetUser[asset][redeemer];
        return LibBytes.readProposalData(redeemerAssetUser.SSTORE2Pointer, redeemerAssetUser.slateLength);
    }
}
