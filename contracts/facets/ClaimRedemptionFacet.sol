// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {U256, U104, U88, U80, U64, U32} from "contracts/libraries/PRBMathHelper.sol";

import {Errors} from "contracts/libraries/Errors.sol";
import {Events} from "contracts/libraries/Events.sol";
import {Modifiers} from "contracts/libraries/AppStorage.sol";
import {STypes, MTypes, SR} from "contracts/libraries/DataTypes.sol";
import {LibShortRecord} from "contracts/libraries/LibShortRecord.sol";
import {LibSRUtil} from "contracts/libraries/LibSRUtil.sol";
import {LibOrders} from "contracts/libraries/LibOrders.sol";
import {LibBytes} from "contracts/libraries/LibBytes.sol";
import {C} from "contracts/libraries/Constants.sol";

import {SSTORE2} from "solmate/utils/SSTORE2.sol";
// import {console} from "contracts/libraries/console.sol";

contract ClaimRedemptionFacet is Modifiers {
    using LibShortRecord for STypes.ShortRecord;
    using U256 for uint256;
    using U104 for uint104;
    using U88 for uint88;
    using U80 for uint80;
    using U64 for uint64;
    using U32 for uint32;

    function claimRedemption(address asset) external isNotFrozen(asset) nonReentrant {
        uint256 vault = s.asset[asset].vault;
        STypes.AssetUser storage redeemerAssetUser = s.assetUser[asset][msg.sender];
        STypes.VaultUser storage redeemerVaultUser = s.vaultUser[vault][msg.sender];
        if (redeemerAssetUser.SSTORE2Pointer == address(0)) revert Errors.InvalidRedemption();

        (, uint32 timeToDispute,,, MTypes.ProposalData[] memory decodedProposalData) =
            LibBytes.readProposalData(redeemerAssetUser.SSTORE2Pointer, redeemerAssetUser.slateLength);

        if (LibOrders.getOffsetTime() < timeToDispute) revert Errors.TimeToDisputeHasNotElapsed();

        uint88 totalColRedeemed;
        for (uint256 i = 0; i < decodedProposalData.length; i++) {
            MTypes.ProposalData memory currentProposal = decodedProposalData[i];
            totalColRedeemed += currentProposal.colRedeemed;
            _claimRemainingCollateral({
                asset: asset,
                vault: vault,
                shorter: currentProposal.shorter,
                shortId: currentProposal.shortId
            });
        }
        redeemerVaultUser.ethEscrowed += totalColRedeemed;
        delete redeemerAssetUser.SSTORE2Pointer;
        emit Events.ClaimRedemption(asset, msg.sender);
    }

    // Redeemed shorters can call this to get their collateral back if redeemer does not claim
    function claimRemainingCollateral(address asset, address redeemer, uint8 claimIndex, uint8 id)
        external
        isNotFrozen(asset)
        nonReentrant
    {
        STypes.AssetUser storage redeemerAssetUser = s.assetUser[asset][redeemer];
        if (redeemerAssetUser.SSTORE2Pointer == address(0)) revert Errors.InvalidRedemption();

        // @dev Only need to read up to the position of the SR to be claimed
        (, uint32 timeToDispute,,, MTypes.ProposalData[] memory decodedProposalData) =
            LibBytes.readProposalData(redeemerAssetUser.SSTORE2Pointer, claimIndex + 1);

        if (timeToDispute > LibOrders.getOffsetTime()) revert Errors.TimeToDisputeHasNotElapsed();
        MTypes.ProposalData memory claimProposal = decodedProposalData[claimIndex];

        if (claimProposal.shorter != msg.sender || claimProposal.shortId != id) revert Errors.CanOnlyClaimYourShort();

        STypes.Asset storage Asset = s.asset[asset];
        _claimRemainingCollateral({asset: asset, vault: Asset.vault, shorter: msg.sender, shortId: id});
    }

    function _claimRemainingCollateral(address asset, uint256 vault, address shorter, uint8 shortId) private {
        STypes.ShortRecord storage shortRecord = s.shortRecords[asset][shorter][shortId];

        if (shortRecord.ercDebt == 0 && shortRecord.status == SR.FullyFilled) {
            // @dev Refund shorter the remaining collateral only if fully redeemed and not claimed already
            uint88 collateral = shortRecord.collateral;
            s.vaultUser[vault][shorter].ethEscrowed += collateral;
            // @dev Shorter shouldn't lose any unclaimed yield because dispute time > YIELD_DELAY_SECONDS
            LibSRUtil.disburseCollateral(asset, shorter, collateral, shortRecord.dethYieldRate, shortRecord.updatedAt);
            LibShortRecord.deleteShortRecord(asset, shorter, shortId);
        }
    }
}
