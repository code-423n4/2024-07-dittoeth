// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {STypes, MTypes, O, SR} from "contracts/libraries/DataTypes.sol";
import {InvariantsBase} from "./InvariantsBase.sol";
import {Handler} from "./Handler.sol";

import {LibBytes} from "contracts/libraries/LibBytes.sol";

import {console} from "contracts/libraries/console.sol";

/* solhint-disable */
/// @dev This contract deploys the target contract, the Handler, adds the Handler's actions to the invariant fuzzing
/// @dev targets, then defines invariants that should always hold throughout any invariant run.
/// @dev Similar to InvariantsOrderBook but with a greater focus on yield
contract InvariantsRedemptions is InvariantsBase {
    function setUp() public override {
        super.setUp();

        // @dev duplicate the selector to increase the distribution of certain handler calls
        selectors = [
            // Bridge
            Handler.deposit.selector,
            Handler.deposit.selector,
            Handler.deposit.selector,
            Handler.depositEth.selector,
            Handler.depositEth.selector,
            Handler.depositEth.selector,
            Handler.withdraw.selector,
            // OrderBook
            Handler.createLimitBid.selector,
            Handler.createLimitBid.selector,
            Handler.createLimitBid.selector,
            Handler.createLimitAsk.selector,
            Handler.createLimitShort.selector,
            Handler.createLimitShort.selector,
            Handler.createLimitShort.selector,
            Handler.createLimitShort.selector,
            Handler.cancelOrder.selector,
            // Yield
            Handler.fakeYield.selector,
            Handler.distributeYieldAll.selector,
            // Handler.claimDittoMatchedRewardAll.selector, @dev Skip time is too much
            // Vault
            Handler.depositAsset.selector,
            Handler.withdrawAsset.selector,
            // Short
            Handler.proposeRedemption.selector,
            Handler.proposeRedemption.selector,
            Handler.proposeRedemption.selector,
            Handler.proposeRedemption.selector,
            Handler.disputeRedemption.selector,
            Handler.disputeRedemption.selector,
            Handler.claimRedemption.selector,
            Handler.claimRemainingCollateral.selector,
            Handler.secondaryLiquidation.selector,
            Handler.primaryLiquidation.selector,
            Handler.exitShort.selector,
            Handler.increaseCollateral.selector,
            Handler.decreaseCollateral.selector,
            Handler.combineShorts.selector
        ];

        targetSelector(FuzzSelector({addr: address(s_handler), selectors: selectors}));
        targetContract(address(s_handler));
    }

    function statefulFuzz_redemptionProposal() public view {
        redemptionProposal();

        // Propose
        // console.log(s_handler.ghost_proposeRedemption());
        // console.log(s_handler.ghost_proposeRedemptionComplete());

        // Dispute
        // console.log(s_handler.ghost_disputeRedemption());
        // console.log(s_handler.ghost_disputeRedemptionNoProposals());
        // console.log(s_handler.ghost_disputeRedemptionTimeElapsed());
        // console.log(s_handler.ghost_disputeRedemptionNA());
        // console.log(s_handler.ghost_disputeRedemptionComplete());

        // Claim
        // console.log(s_handler.ghost_claimRedemption());
        // console.log(s_handler.ghost_claimRedemptionComplete());
        // console.log(s_handler.ghost_claimRemainingCollateral());
        // console.log(s_handler.ghost_claimRemainingCollateralComplete());
    }

    function redemptionProposal() public view {
        // Possible Violations, should be 0
        uint256 proposalValidity;
        uint256 proposalMinShortErc;
        uint256 proposalAllCROver1;
        uint256 proposalAllCRUnder2;
        uint256 proposalSorted;
        uint256 proposalStatus;

        address[] memory redeemers = s_handler.getRedeemers();
        for (uint256 i = 0; i < redeemers.length; i++) {
            MTypes.ProposalData[] memory decodedProposalData;
            (,,,, decodedProposalData) = LibBytes.readProposalData(
                diamond.getAssetUserStruct(asset, redeemers[i]).SSTORE2Pointer,
                diamond.getAssetUserStruct(asset, redeemers[i]).slateLength
            );

            uint256 prevCR;
            uint256 proposalLength = decodedProposalData.length;
            for (uint256 j = 0; j < proposalLength; j++) {
                // Shorter can't be redeemer, and shorter can't be TAPP
                if (decodedProposalData[j].shorter == redeemers[i] || decodedProposalData[j].shorter == address(diamond)) {
                    proposalValidity++;
                }

                // At least minShortErc has to be redeemed per SR
                if (decodedProposalData[j].ercDebtRedeemed < diamond.getMinShortErc(asset)) proposalMinShortErc++;

                // All SR must be above 1
                if (decodedProposalData[j].CR < 1 ether) proposalAllCROver1++;
                // All SR must be below 2
                if (decodedProposalData[j].CR > 2 ether) proposalAllCRUnder2++;
                // SR sorted by CR from least to greatest
                if (decodedProposalData[j].CR < prevCR) proposalSorted++;
                prevCR = decodedProposalData[j].CR;

                STypes.ShortRecord memory shortRecord =
                    diamond.getShortRecord(asset, decodedProposalData[j].shorter, decodedProposalData[j].shortId);
                // Status can't be closed until claimed or exited
                if (shortRecord.collateral > 0 && shortRecord.status == SR.Closed) proposalStatus++;
            }
        }

        assertEq(proposalValidity, 0, "statefulFuzz_redemptionProposal_1");
        assertEq(proposalMinShortErc, 0, "statefulFuzz_redemptionProposal_2");
        assertEq(proposalAllCROver1, 0, "statefulFuzz_redemptionProposal_3");
        assertEq(proposalAllCRUnder2, 0, "statefulFuzz_redemptionProposal_4");
        assertEq(proposalSorted, 0, "statefulFuzz_redemptionProposal_5");
        assertEq(proposalStatus, 0, "statefulFuzz_redemptionProposal_6");
    }
}
