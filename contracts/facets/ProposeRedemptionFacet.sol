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
import {LibOracle} from "contracts/libraries/LibOracle.sol";
import {LibOrders} from "contracts/libraries/LibOrders.sol";
import {LibBytes} from "contracts/libraries/LibBytes.sol";
import {C} from "contracts/libraries/Constants.sol";

import {SSTORE2} from "solmate/utils/SSTORE2.sol";
// import {console} from "contracts/libraries/console.sol";

contract ProposeRedemptionFacet is Modifiers {
    using LibShortRecord for STypes.ShortRecord;
    using LibSRUtil for STypes.ShortRecord;
    using U256 for uint256;
    using U104 for uint104;
    using U88 for uint88;
    using U80 for uint80;
    using U64 for uint64;
    using U32 for uint32;

    function proposeRedemption(
        address asset,
        MTypes.ProposalInput[] calldata proposalInput,
        uint88 redemptionAmount,
        uint88 maxRedemptionFee,
        uint256 deadline
    ) external isNotFrozen(asset) nonReentrant {
        if (block.timestamp > deadline) revert Errors.ProposalExpired(deadline);

        if (proposalInput.length > type(uint8).max) revert Errors.TooManyProposals();
        MTypes.ProposeRedemption memory p;
        p.asset = asset;
        STypes.AssetUser storage redeemerAssetUser = s.assetUser[p.asset][msg.sender];
        STypes.Asset storage Asset = s.asset[p.asset];
        uint256 minShortErc = LibAsset.minShortErc(Asset);

        if (redemptionAmount < minShortErc) revert Errors.RedemptionUnderMinShortErc();
        if (redeemerAssetUser.ercEscrowed < redemptionAmount) revert Errors.InsufficientERCEscrowed();
        // @dev redeemerAssetUser.SSTORE2Pointer gets reset to address(0) after actual redemption
        if (redeemerAssetUser.SSTORE2Pointer != address(0)) revert Errors.ExistingProposedRedemptions();

        p.ercDebtRate = Asset.ercDebtRate;
        p.oraclePrice = uint80(LibOracle.getSavedOrSpotOraclePrice(p.asset));
        p.protocolTime = LibOrders.getOffsetTime();

        bytes memory slate;
        for (uint8 i = 0; i < proposalInput.length; i++) {
            p.shorter = proposalInput[i].shorter;
            p.shortId = proposalInput[i].shortId;
            p.shortOrderId = proposalInput[i].shortOrderId;
            STypes.ShortRecord storage currentSR = s.shortRecords[p.asset][p.shorter][p.shortId];

            /// Evaluate proposed shortRecord

            if (!LibRedemption.validRedemptionSR(currentSR, msg.sender, p.shorter, minShortErc)) continue;

            currentSR.updateErcDebt(p.ercDebtRate);
            p.currentCR = currentSR.getCollateralRatio(p.oraclePrice);

            // @dev Skip if proposal is not sorted correctly or if above/below redemption threshold
            if (p.lastCR > p.currentCR || p.currentCR >= C.MAX_REDEMPTION_CR || p.currentCR < C.ONE_CR) continue;

            // @dev totalAmountProposed tracks the actual amount that can be redeemed. totalAmountProposed <= redemptionAmount
            if (p.totalAmountProposed + currentSR.ercDebt <= redemptionAmount) {
                p.amountProposed = currentSR.ercDebt;
            } else {
                p.amountProposed = redemptionAmount - p.totalAmountProposed;
                // @dev Exit when proposal would leave less than minShortErc, proxy for nearing end of slate
                if (currentSR.ercDebt - p.amountProposed < minShortErc) break;
            }

            // Cancel attached shortOrder if below minShortErc or lowCR
            // @dev Only need to check fully redeemed SR bc partially redeemed SR has >= minShortErc remaining
            // @dev All verified SR have ercDebt >= minShortErc so CR does not change in cancelShort()
            if (currentSR.status == SR.PartialFill && p.amountProposed == currentSR.ercDebt) {
                STypes.Order storage shortOrder = s.shorts[p.asset][p.shortOrderId];
                if (LibSRUtil.invalidShortOrder(shortOrder, p.shortId, p.shorter)) continue;
                // @dev shortOrder needs to be verified BEFORE using
                if (shortOrder.ercAmount < minShortErc || shortOrder.shortOrderCR < Asset.initialCR) {
                    LibOrders.cancelShort(asset, p.shortOrderId);
                }
            }

            /// At this point, the shortRecord passes all checks and will be included in the slate
            p.lastCR = p.currentCR;

            p.colRedeemed = p.oraclePrice.mulU88(p.amountProposed);
            if (p.colRedeemed > currentSR.collateral) {
                p.colRedeemed = currentSR.collateral;
            }

            currentSR.collateral -= p.colRedeemed;
            currentSR.ercDebt -= p.amountProposed;

            // Remove ercDebtFee
            // @dev Not using LibSRUtil.reduceErcDebtFee to save gas bc every call changes Asset.ercDebtFee
            p.ercDebtFee = uint88(LibOrders.min(currentSR.ercDebtFee, p.amountProposed)); // @dev(safe-cast)
            currentSR.ercDebtFee -= p.ercDebtFee;

            p.totalAmountProposed += p.amountProposed;
            p.totalColRedeemed += p.colRedeemed;
            p.totalErcDebtFee += p.ercDebtFee;

            // @dev directly write the properties of MTypes.ProposalData into bytes
            // instead of usual abi.encode to save on extra zeros being written
            slate = bytes.concat(
                slate,
                bytes20(p.shorter),
                bytes1(p.shortId),
                bytes8(uint64(p.currentCR)),
                bytes11(p.amountProposed),
                bytes11(p.colRedeemed),
                bytes11(p.ercDebtFee)
            );

            LibSRUtil.disburseCollateral(p.asset, p.shorter, p.colRedeemed, currentSR.dethYieldRate, currentSR.updatedAt);
            currentSR.updatedAt = p.protocolTime;
            p.redemptionCounter++;
            if (redemptionAmount - p.totalAmountProposed < minShortErc) break;
        }

        if (p.totalAmountProposed < minShortErc) revert Errors.RedemptionUnderMinShortErc();

        // @dev SSTORE2 the entire proposalData after validating proposalInput
        redeemerAssetUser.slateLength = p.redemptionCounter;
        redeemerAssetUser.ercEscrowed -= p.totalAmountProposed;

        // @dev Calculate the dispute period
        // @dev timeToDispute is immediate for shorts with CR <= 1.1x
        uint32 timeToDispute = LibRedemption.calculateTimeToDispute(p.lastCR, p.protocolTime);

        bytes memory initialBytes =
            bytes.concat(bytes4(p.protocolTime), bytes4(timeToDispute), bytes10(p.oraclePrice), bytes10(p.ercDebtRate));
        slate = bytes.concat(initialBytes, slate);
        // @dev SSTORE2 the entire proposalData after validating proposalInput
        redeemerAssetUser.SSTORE2Pointer = SSTORE2.write(slate);

        uint256 newBaseRate = LibRedemption.calculateNewBaseRate(Asset, p.totalAmountProposed);
        assert(newBaseRate > 0); // Base rate is always non-zero after redemption
        // Update the baseRate state variable
        Asset.ercDebt -= p.totalAmountProposed;
        Asset.ercDebtFee -= p.totalErcDebtFee;
        Asset.baseRate = uint64(newBaseRate); // @dev(safe-cast)
        Asset.lastRedemptionTime = p.protocolTime;

        uint88 redemptionFee = LibRedemption.calculateRedemptionFee(uint64(newBaseRate), p.totalColRedeemed);
        if (redemptionFee > maxRedemptionFee) revert Errors.RedemptionFeeTooHigh();

        STypes.VaultUser storage VaultUser = s.vaultUser[Asset.vault][msg.sender];
        if (VaultUser.ethEscrowed < redemptionFee) revert Errors.InsufficientETHEscrowed();
        VaultUser.ethEscrowed -= redemptionFee;
        // Send fee to TAPP
        s.vaultUser[Asset.vault][address(this)].ethEscrowed += redemptionFee;

        emit Events.ProposeRedemption(p.asset, msg.sender);
    }
}
