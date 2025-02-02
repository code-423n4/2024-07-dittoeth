// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {IAsset} from "interfaces/IAsset.sol";

import {STypes, SR} from "contracts/libraries/DataTypes.sol";
import {Modifiers} from "contracts/libraries/AppStorage.sol";
import {LibOrders} from "contracts/libraries/LibOrders.sol";
import {LibOracle} from "contracts/libraries/LibOracle.sol";
import {LibShortRecord} from "contracts/libraries/LibShortRecord.sol";
import {LibVault} from "contracts/libraries/LibVault.sol";
import {C} from "contracts/libraries/Constants.sol";
import {Errors} from "contracts/libraries/Errors.sol";
import {Events} from "contracts/libraries/Events.sol";

import {U256, U88, U80} from "contracts/libraries/PRBMathHelper.sol";

// import {console} from "contracts/libraries/console.sol";

contract YieldFacet is Modifiers {
    using U256 for uint256;
    using U88 for uint88;
    using U80 for uint80;
    using LibShortRecord for STypes.ShortRecord;
    using LibVault for uint256;

    IAsset private immutable DITTO;
    uint256 private immutable DITTO_TARGET_CR;

    // TODO: Remove _dittoTargetCR as a constructor arg and use constant after yield tests are redone
    constructor(address _ditto, uint256 _dittoTargetCR) {
        DITTO = IAsset(_ditto);
        DITTO_TARGET_CR = _dittoTargetCR;
    }

    /**
     * @notice Updates the vault yield rate from staking rewards earned by bridge contracts holding LSD
     * @dev Does not distribute yield to any individual owner of shortRecords
     *
     * @param vault The vault that will be impacted
     */
    function updateYield(uint256 vault) external nonReentrant {
        vault.updateYield();
        emit Events.UpdateYield(vault);
    }

    // @dev exists because of ShortOrderFacet contract size
    function _updateYieldDiamond(uint256 vault) external onlyDiamond {
        vault.updateYield();
        emit Events.UpdateYield(vault);
    }

    /**
     * @notice Updates the vault yield rate from staking rewards earned by bridge contracts holding LSD
     * @dev Can only distribute yield in markets that are part of the same vault
     *
     * @param assets Array of markets to evaluate when distributing yield from caller's shortRecords
     */
    function distributeYield(address[] calldata assets) external nonReentrant {
        uint256 length = assets.length;
        uint256 vault = s.asset[assets[0]].vault;
        uint256 protocolTime = LibOrders.getOffsetTime();

        // distribute yield for the first order book
        (uint88 yield, uint256 dittoYieldShares) = _distributeYield(assets[0], protocolTime);

        // distribute yield for remaining order books
        for (uint256 i = 1; i < length;) {
            if (s.asset[assets[i]].vault != vault) revert Errors.DifferentVaults();
            (uint88 amtYield, uint256 amtDittoYieldShares) = _distributeYield(assets[i], protocolTime);
            yield += amtYield;
            dittoYieldShares += amtDittoYieldShares;
            unchecked {
                ++i;
            }
        }
        // claim all distributed yield
        _claimYield(vault, yield, dittoYieldShares, protocolTime);
        emit Events.DistributeYield(vault, msg.sender, yield, dittoYieldShares);
    }

    // Distributes yield earned from all of caller's shortRecords of this asset
    function _distributeYield(address asset, uint256 protocolTime)
        private
        onlyValidAsset(asset)
        returns (uint88 yield, uint256 dittoYieldShares)
    {
        uint256 vault = s.asset[asset].vault;
        // Last updated dethYieldRate for this vault
        uint80 dethYieldRate = s.vault[vault].dethYieldRate;
        // Last saved oracle price
        uint256 savedPrice = LibOracle.getPrice(asset);
        // Maximum CR of shortRecord allowed before loss ditto shorter reward efficiency
        uint256 dittoTargetCR = DITTO_TARGET_CR;
        // Retrieve first non-HEAD short
        uint8 id = s.shortRecords[asset][msg.sender][C.HEAD].nextId;
        // Loop through all shorter's shorts of this asset
        while (true) {
            // One short of one shorter in this market
            STypes.ShortRecord memory short = s.shortRecords[asset][msg.sender][id];
            // To prevent flash loans or loans where they want to deposit to claim yield immediately
            bool isNotRecentlyModified = protocolTime - short.updatedAt > C.YIELD_DELAY_SECONDS;
            // Check for ineligible short
            if (short.status != SR.Closed && short.ercDebt > 0 && isNotRecentlyModified) {
                uint88 shortYield = short.collateral.mulU88(dethYieldRate - short.dethYieldRate);
                // Yield earned by this short
                yield += shortYield;
                // Update dethYieldRate for this short
                s.shortRecords[asset][msg.sender][id].dethYieldRate = dethYieldRate;
                // Calculate CR to modify ditto rewards
                uint256 cRatio = short.getCollateralRatio(savedPrice);
                if (cRatio <= dittoTargetCR) {
                    dittoYieldShares += shortYield;
                } else {
                    // Reduce amount of yield credited for ditto rewards proportional to CR
                    dittoYieldShares += shortYield.mul(dittoTargetCR).div(cRatio);
                }
            }
            // Move to next short unless this is the last one
            if (short.nextId > C.HEAD) {
                id = short.nextId;
            } else {
                break;
            }
        }
    }

    // Credit DETH and Ditto rewards earned from shortRecords from all markets
    function _claimYield(uint256 vault, uint88 yield, uint256 dittoYieldShares, uint256 protocolTime) private {
        STypes.Vault storage Vault = s.vault[vault];
        STypes.VaultUser storage VaultUser = s.vaultUser[vault][msg.sender];
        // Implicitly checks for a valid vault
        if (yield <= 1) revert Errors.NoYield();
        // Credit yield to ethEscrowed
        VaultUser.ethEscrowed += yield;
        // Ditto rewards earned for all shorters since inception
        uint256 dittoRewardShortersTotal = protocolTime.mul(LibVault.dittoShorterRate(vault));
        // Ditto reward proportion from this yield distribution
        uint256 dittoYieldSharesTotal = Vault.dethCollateralReward;
        uint256 dittoReward = dittoYieldShares.mul(dittoRewardShortersTotal).div(dittoYieldSharesTotal);
        // Credit ditto reward to user
        VaultUser.dittoReward += uint80(dittoReward); // @dev(safe-cast)
    }

    /**
     * @notice Credits ditto rewards earned from eligible limit orders from all markets
     *
     * @param vault The vault that will be impacted
     */
    function claimDittoMatchedReward(uint256 vault) external nonReentrant {
        STypes.Vault storage Vault = s.vault[vault];
        STypes.VaultUser storage VaultUser = s.vaultUser[vault][msg.sender];
        // User's shares total
        uint88 shares = VaultUser.dittoMatchedShares;
        // Implicitly checks for a valid vault
        if (shares <= 1) revert Errors.NoShares();
        // Decrease by 1 wei to account for 1 wei gas saving technique
        shares -= 1;
        // Total token reward amount for limit orders
        uint256 protocolTime = LibOrders.getOffsetTime() / 1 days;
        uint256 elapsedTime = protocolTime - Vault.dittoMatchedTime;
        uint256 totalReward = Vault.dittoMatchedReward + (elapsedTime * 1 days).mul(LibVault.dittoMatchedRate(vault));
        // User's proportion of the total token reward
        uint256 sharesTotal = Vault.dittoMatchedShares;
        uint256 userReward = shares.mul(totalReward).div(sharesTotal);
        // Only update dittoMatchedTime when totalReward increases
        if (elapsedTime > 0) {
            Vault.dittoMatchedTime = uint16(protocolTime); // @dev(safe-cast)
        }
        // Update remaining records
        Vault.dittoMatchedShares -= shares;
        if ((totalReward - userReward) > type(uint96).max) revert Errors.InvalidAmount();
        Vault.dittoMatchedReward = uint96(totalReward - userReward);
        VaultUser.dittoMatchedShares = 1; // keep as non-zero to save gas
        VaultUser.dittoReward += uint80(userReward); // @dev(safe-cast)
        emit Events.ClaimDittoMatchedReward(vault, msg.sender);
    }

    /**
     * @notice Mints claimed Ditto rewards
     * @dev Includes claimed balances from shortRecords and limit orders
     *
     * @param vault The vault that will be impacted
     */
    function withdrawDittoReward(uint256 vault) external nonReentrant {
        STypes.VaultUser storage VaultUser = s.vaultUser[vault][msg.sender];
        uint256 amt = VaultUser.dittoReward;
        // Implicitly checks for a valid vault
        if (amt <= 1) revert Errors.NoDittoReward();
        // Decrease by 1 wei to account for 1 wei gas saving technique
        amt -= 1;
        VaultUser.dittoReward = 1; // keep as non-zero to save gas
        DITTO.mint(msg.sender, amt);
    }
}
