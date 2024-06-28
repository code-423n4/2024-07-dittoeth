// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {U256, U104, U88, U80, U64, U32} from "contracts/libraries/PRBMathHelper.sol";

import {Errors} from "contracts/libraries/Errors.sol";
import {Events} from "contracts/libraries/Events.sol";
import {Modifiers} from "contracts/libraries/AppStorage.sol";
import {STypes, MTypes, SR} from "contracts/libraries/DataTypes.sol";
import {LibAsset} from "contracts/libraries/LibAsset.sol";
import {LibRedemption} from "contracts/libraries/LibRedemption.sol";
import {LibShortRecord} from "contracts/libraries/LibShortRecord.sol";
import {LibSRUtil} from "contracts/libraries/LibSRUtil.sol";
import {LibOrders} from "contracts/libraries/LibOrders.sol";
import {LibBytes} from "contracts/libraries/LibBytes.sol";
import {C} from "contracts/libraries/Constants.sol";

import {SSTORE2} from "solmate/utils/SSTORE2.sol";
// import {console} from "contracts/libraries/console.sol";

contract DisputeRedemptionFacet is Modifiers {
    using LibShortRecord for STypes.ShortRecord;
    using LibSRUtil for STypes.ShortRecord;
    using U256 for uint256;
    using U104 for uint104;
    using U88 for uint88;
    using U80 for uint80;
    using U64 for uint64;
    using U32 for uint32;

    function disputeRedemption(address asset, address redeemer, uint8 incorrectIndex, address disputeShorter, uint8 disputeShortId)
        external
        isNotFrozen(asset)
        nonReentrant
    {
        if (redeemer == msg.sender) revert Errors.CannotDisputeYourself();
        MTypes.DisputeRedemption memory d;
        d.asset = asset;
        d.redeemer = redeemer;
        d.protocolTime = LibOrders.getOffsetTime();

        STypes.AssetUser storage redeemerAssetUser = s.assetUser[d.asset][d.redeemer];
        if (redeemerAssetUser.SSTORE2Pointer == address(0)) revert Errors.InvalidRedemption();

        (d.timeProposed, d.timeToDispute, d.oraclePrice, d.ercDebtRate, d.decodedProposalData) =
            LibBytes.readProposalData(redeemerAssetUser.SSTORE2Pointer, redeemerAssetUser.slateLength);

        if (d.protocolTime >= d.timeToDispute) revert Errors.TimeToDisputeHasElapsed();

        for (uint256 i = 0; i < d.decodedProposalData.length; i++) {
            if (d.decodedProposalData[i].shorter == disputeShorter && d.decodedProposalData[i].shortId == disputeShortId) {
                revert Errors.CannotDisputeWithRedeemerProposal();
            }
        }

        STypes.ShortRecord storage disputeSR = s.shortRecords[d.asset][disputeShorter][disputeShortId];

        // Match continue (skip) conditions in proposeRedemption()
        STypes.Asset storage Asset = s.asset[d.asset];
        d.minShortErc = LibAsset.minShortErc(Asset);
        if (!LibRedemption.validRedemptionSR(disputeSR, d.redeemer, disputeShorter, d.minShortErc)) {
            revert Errors.InvalidRedemption();
        }

        MTypes.ProposalData memory incorrectProposal = d.decodedProposalData[incorrectIndex];
        MTypes.ProposalData memory currentProposal;

        if (disputeSR.updatedAt + C.DISPUTE_REDEMPTION_BUFFER <= d.timeProposed) {
            // SR valid for evaluation, unchanged in the recent past
            disputeSR.updateErcDebt(d.ercDebtRate);
            d.disputeCR = disputeSR.getCollateralRatio(d.oraclePrice);
            if (d.disputeCR >= C.ONE_CR && d.disputeCR < incorrectProposal.CR) {
                // @dev Ensure disputer passes in the incorrectProposal at the correct index
                if (incorrectIndex > 0) {
                    MTypes.ProposalData memory prevProposal = d.decodedProposalData[incorrectIndex - 1];
                    if (d.disputeCR < prevProposal.CR) revert Errors.NotLowestIncorrectIndex();
                }
                STypes.Vault storage Vault = s.vault[Asset.vault];
                d.dethYieldRate = Vault.dethYieldRate;
                d.ercDebtRate = Asset.ercDebtRate;
                // @dev All proposals from the incorrectIndex onward will be removed
                // @dev Thus the proposer can only redeem a portion of their original slate
                for (uint256 i = incorrectIndex; i < d.decodedProposalData.length; i++) {
                    currentProposal = d.decodedProposalData[i];
                    STypes.ShortRecord storage currentSR = s.shortRecords[d.asset][currentProposal.shorter][currentProposal.shortId];
                    // @dev Handle case where SR is closed (i.e. exited) before it was properly disputed
                    // @dev UIs for this protocol should alert shorter that their SR was proposed and thus see if it can be disputed
                    if (currentSR.status == SR.Closed) {
                        // @dev If the protocol created a new SR with the proposed amount, it would have been at or near 1:1 (1x CR), thus making it instantly liquidatable
                        // @dev Additionally, the shorter would not lose anything in losing the proposed collateral since they also no longer owe the debt
                        // @dev Thus more streamlined to give back the proposed amounts to the TAPP, and safer to consolidate risky debt into one position
                        STypes.ShortRecord storage tappSR = s.shortRecords[d.asset][address(this)][C.SHORT_STARTING_ID];
                        LibShortRecord.merge({
                            short: tappSR,
                            ercDebt: currentProposal.ercDebtRedeemed,
                            ercDebtSocialized: currentProposal.ercDebtRedeemed.mul(d.ercDebtRate),
                            collateral: currentProposal.colRedeemed,
                            yield: currentProposal.colRedeemed.mul(d.dethYieldRate),
                            creationTime: d.protocolTime,
                            ercDebtFee: currentProposal.ercDebtFee
                        });
                    } else {
                        // @dev Returns the proposed collateral and debt to the SR
                        // @dev Also valid in the case where a proposed SR is closed and re-used prior to disputing
                        LibShortRecord.merge({
                            short: currentSR,
                            ercDebt: currentProposal.ercDebtRedeemed,
                            ercDebtSocialized: currentProposal.ercDebtRedeemed.mul(d.ercDebtRate),
                            collateral: currentProposal.colRedeemed,
                            yield: currentProposal.colRedeemed.mul(d.dethYieldRate),
                            creationTime: d.protocolTime,
                            ercDebtFee: currentProposal.ercDebtFee
                        });
                    }
                    d.incorrectCollateral += currentProposal.colRedeemed;
                    d.incorrectErcDebt += currentProposal.ercDebtRedeemed;
                    d.ercDebtFee += currentProposal.ercDebtFee;
                }

                Vault.dethCollateral += d.incorrectCollateral;
                Asset.dethCollateral += d.incorrectCollateral;
                Asset.ercDebt += d.incorrectErcDebt;
                Asset.ercDebtFee += d.ercDebtFee;

                // @dev Update the redeemer's SSTORE2Pointer
                if (incorrectIndex > 0) {
                    redeemerAssetUser.slateLength = incorrectIndex;
                } else {
                    // @dev this implies everything in the redeemer's proposal was incorrect
                    delete redeemerAssetUser.SSTORE2Pointer;
                    emit Events.DisputeRedemptionAll(d.asset, redeemer);
                }

                {
                    // @dev Penalty is based on the proposal with highest CR (decodedProposalData is sorted)
                    // @dev PenaltyPct is bound between CallerFeePct and 33% to prevent exploiting primaryLiquidation fees
                    uint256 penaltyPct = LibOrders.min(
                        LibOrders.max(LibAsset.callerFeePct(d.asset), (currentProposal.CR - d.disputeCR).div(currentProposal.CR)),
                        C.ONE_THIRD
                    );
                    uint88 disputerReward = d.incorrectErcDebt.mulU88(penaltyPct);

                    // @dev TAPP takes portion of the penalty
                    // @dev Disincentivize exploit where user proposes and disputes themselves under different addresses
                    uint88 tappFee = d.incorrectErcDebt.mulU88(LibAsset.tappFeePct(d.asset));

                    // @dev Currently impossible for d.incorrectErcDebt < (disputerReward + tappFee)
                    // @dev Max value of penaltyPct is 33% and tappFeePct is 25%
                    uint88 refundAmt = d.incorrectErcDebt - disputerReward - tappFee;

                    // @dev Give redeemer back ercEscrowed that is no longer used to redeem (penalty applied)
                    redeemerAssetUser.ercEscrowed += refundAmt;
                    s.assetUser[d.asset][address(this)].ercEscrowed += tappFee;
                    s.assetUser[d.asset][msg.sender].ercEscrowed += disputerReward;
                }
            } else {
                revert Errors.InvalidRedemptionDispute();
            }
        } else {
            revert Errors.DisputeSRUpdatedNearProposalTime();
        }
    }
}
