// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {U256} from "contracts/libraries/PRBMathHelper.sol";

import {Modifiers} from "contracts/libraries/AppStorage.sol";
import {Errors} from "contracts/libraries/Errors.sol";
import {Events} from "contracts/libraries/Events.sol";
import {STypes, MTypes, SR} from "contracts/libraries/DataTypes.sol";
import {LibDiamond} from "contracts/libraries/LibDiamond.sol";
import {LibOrders} from "contracts/libraries/LibOrders.sol";
import {LibOracle} from "contracts/libraries/LibOracle.sol";
import {LibShortRecord} from "contracts/libraries/LibShortRecord.sol";
import {LibAsset} from "contracts/libraries/LibAsset.sol";
import {C} from "contracts/libraries/Constants.sol";

// import {console} from "contracts/libraries/console.sol";

contract OwnerFacet is Modifiers {
    using U256 for uint256;

    /**
     * @notice Initialize data for newly deployed market
     * @dev Single use only
     *
     * @param asset The market that will be impacted
     * @param a The market settings
     */

    /*
     * @param oracle The oracle for the asset
     * @param initialCR initialCR value of the new market
     * @param liquidationCR Liquidation ratio value of the new market
     * @param forcedBidPriceBuffer Liquidation limit value of the new market
     * @param penaltyCR Lowest threshold for shortRecord to not lose collateral during liquidation
     * @param tappFeePct Primary liquidation fee sent to TAPP out of shorter collateral
     * @param callerFeePct Primary liquidation fee sent to liquidator out of shorter collateral
     * @param minBidEth Minimum bid dust amount
     * @param minAskEth Minimum ask dust amount
     * @param minShortErc Minimum short record debt amount
     * @param recoveryCR CRatio threshold for recovery mode of the entire market
    */

    function createMarket(address asset, address yieldVault, STypes.Asset memory a) external onlyDAO {
        STypes.Asset storage Asset = s.asset[asset];
        // can check non-zero ORDER_ID to prevent creating same asset
        if (Asset.orderIdCounter != 0) revert Errors.MarketAlreadyCreated();

        Asset.vault = a.vault;
        _setAssetOracle(asset, a.oracle);

        Asset.assetId = uint8(s.assets.length);
        s.assets.push(asset);

        STypes.Order memory headOrder;
        headOrder.prevId = C.HEAD;
        headOrder.id = C.HEAD;
        headOrder.nextId = C.TAIL;
        // @dev parts of OB depend on having sell's HEAD's price and creationTime = 0
        s.asks[asset][C.HEAD] = s.shorts[asset][C.HEAD] = headOrder;

        // @dev Using Bid's HEAD's order contain oracle data
        headOrder.creationTime = LibOrders.getOffsetTime();
        headOrder.ercAmount = uint80(LibOracle.getOraclePrice(asset));
        s.bids[asset][C.HEAD] = headOrder;

        // @dev hardcoded value
        Asset.orderIdCounter = C.STARTING_ID; // 100
        Asset.startingShortId = C.HEAD;

        // @dev comment with initial values
        _setInitialCR(asset, a.initialCR); // 170 -> 1.7 ether
        _setLiquidationCR(asset, a.liquidationCR); // 150 -> 1.5 ether
        _setForcedBidPriceBuffer(asset, a.forcedBidPriceBuffer); // 110 -> 1.1 ether
        _setPenaltyCR(asset, a.penaltyCR); // 110 -> 1.1 ether
        _setTappFeePct(asset, a.tappFeePct); // 25 -> .025 ether
        _setCallerFeePct(asset, a.callerFeePct); // 5 -> .005 ether
        _setMinBidEth(asset, a.minBidEth); // 10 -> 0.1 ether
        _setMinAskEth(asset, a.minAskEth); // 10 -> 0.1 ether
        _setMinShortErc(asset, a.minShortErc); // 2000 -> 2000 ether
        _setRecoveryCR(asset, a.recoveryCR); // 150 -> 1.5 ether
        _setDiscountPenaltyFee(asset, a.discountPenaltyFee); // 10 -> .001 ether (.1%)
        _setDiscountMultiplier(asset, a.discountMultiplier); // 10000 -> 10 ether (10x)
        _setYieldVault(asset, yieldVault);

        // Create TAPP short
        LibShortRecord.createShortRecord(asset, address(this), SR.FullyFilled, 0, 0, 0, 0, 0);
        emit Events.CreateMarket(asset, Asset);
    }

    // @dev does not need read only reentrancy
    function owner() external view returns (address) {
        return LibDiamond.contractOwner();
    }

    function admin() external view returns (address) {
        return s.admin;
    }

    // @dev does not need read only reentrancy
    function ownerCandidate() external view returns (address) {
        return s.ownerCandidate;
    }

    function transferOwnership(address newOwner) external onlyDAO {
        s.ownerCandidate = newOwner;
        emit Events.NewOwnerCandidate(newOwner);
    }

    // @dev event emitted in setContractOwner
    function claimOwnership() external {
        if (s.ownerCandidate != msg.sender) revert Errors.NotOwnerCandidate();
        LibDiamond.setContractOwner(msg.sender);
        delete s.ownerCandidate;
    }

    //No need for claim step because DAO can also set admin
    function transferAdminship(address newAdmin) external onlyAdminOrDAO {
        s.admin = newAdmin;
        emit Events.NewAdmin(newAdmin);
    }

    function createVault(address deth, uint256 vault, MTypes.CreateVaultParams calldata params) external onlyDAO {
        if (s.dethVault[deth] != 0) revert Errors.VaultAlreadyCreated();
        s.dethVault[deth] = vault;
        _setTithe(vault, params.dethTithePercent);
        _setDittoMatchedRate(vault, params.dittoMatchedRate);
        _setDittoShorterRate(vault, params.dittoShorterRate);
        emit Events.CreateVault(deth, vault);
    }

    // Update eligibility requirements for yield accrual
    function setTithe(uint256 vault, uint16 dethTithePercent) external onlyAdminOrDAO {
        _setTithe(vault, dethTithePercent);
        emit Events.ChangeVaultSetting(vault);
    }

    function setDittoMatchedRate(uint256 vault, uint16 rewardRate) external onlyAdminOrDAO {
        _setDittoMatchedRate(vault, rewardRate);
        emit Events.ChangeVaultSetting(vault);
    }

    function setDittoShorterRate(uint256 vault, uint16 rewardRate) external onlyAdminOrDAO {
        _setDittoShorterRate(vault, rewardRate);
        emit Events.ChangeVaultSetting(vault);
    }

    // For Short Record collateral ratios
    // initialCR > liquidationCR > penaltyCR
    // After initial market creation. Set CRs from smallest to largest to prevent triggering the require checks

    function setInitialCR(address asset, uint16 value) external onlyAdminOrDAO {
        _setInitialCR(asset, value);
        emit Events.ChangeMarketSetting(asset);
    }

    function setLiquidationCR(address asset, uint16 value) external onlyAdminOrDAO {
        require(value > s.asset[asset].penaltyCR, "below penalty CR");
        _setLiquidationCR(asset, value);
        emit Events.ChangeMarketSetting(asset);
    }

    function setForcedBidPriceBuffer(address asset, uint8 value) external onlyAdminOrDAO {
        _setForcedBidPriceBuffer(asset, value);
        emit Events.ChangeMarketSetting(asset);
    }

    function setPenaltyCR(address asset, uint8 value) external onlyAdminOrDAO {
        _setPenaltyCR(asset, value);
        emit Events.ChangeMarketSetting(asset);
    }

    function setTappFeePct(address asset, uint8 value) external onlyAdminOrDAO {
        _setTappFeePct(asset, value);
        emit Events.ChangeMarketSetting(asset);
    }

    function setCallerFeePct(address asset, uint8 value) external onlyAdminOrDAO {
        _setCallerFeePct(asset, value);
        emit Events.ChangeMarketSetting(asset);
    }

    function setMinBidEth(address asset, uint8 value) external onlyAdminOrDAO {
        _setMinBidEth(asset, value);
        emit Events.ChangeMarketSetting(asset);
    }

    function setMinAskEth(address asset, uint8 value) external onlyAdminOrDAO {
        _setMinAskEth(asset, value);
        emit Events.ChangeMarketSetting(asset);
    }

    function setMinShortErc(address asset, uint16 value) external onlyAdminOrDAO {
        _setMinShortErc(asset, value);
        emit Events.ChangeMarketSetting(asset);
    }

    function setRecoveryCR(address asset, uint8 value) external onlyAdminOrDAO {
        _setRecoveryCR(asset, value);
        emit Events.ChangeMarketSetting(asset);
    }

    function setDiscountPenaltyFee(address asset, uint16 value) external onlyAdminOrDAO {
        _setDiscountPenaltyFee(asset, value);
        emit Events.ChangeMarketSetting(asset);
    }

    function setDiscountMultiplier(address asset, uint16 value) external onlyAdminOrDAO {
        _setDiscountMultiplier(asset, value);
        emit Events.ChangeMarketSetting(asset);
    }

    function setYieldVault(address asset, address vault) external onlyAdminOrDAO {
        _setYieldVault(asset, vault);
        emit Events.ChangeMarketSetting(asset);
    }

    function createBridge(address bridge, uint256 vault, uint16 withdrawalFee) external onlyDAO {
        if (vault == 0) revert Errors.InvalidVault();
        STypes.Bridge storage Bridge = s.bridge[bridge];
        if (Bridge.vault != 0) revert Errors.BridgeAlreadyCreated();

        s.vaultBridges[vault].push(bridge);
        Bridge.vault = uint8(vault);
        _setWithdrawalFee(bridge, withdrawalFee);
        emit Events.CreateBridge(bridge, Bridge);
    }

    function setWithdrawalFee(address bridge, uint16 withdrawalFee) external onlyAdminOrDAO {
        _setWithdrawalFee(bridge, withdrawalFee);
        emit Events.ChangeBridgeSetting(bridge);
    }

    function _setAssetOracle(address asset, address oracle) private {
        if (asset == address(0) || oracle == address(0)) revert Errors.ParameterIsZero();
        s.asset[asset].oracle = oracle;
    }

    function _setTithe(uint256 vault, uint16 dethTithePercent) private {
        if (dethTithePercent > 33_33) revert Errors.InvalidTithe();
        // @dev dethTithePercent should never be changed outside of this function
        s.vault[vault].dethTithePercent = dethTithePercent;
    }

    function _setDittoMatchedRate(uint256 vault, uint16 rewardRate) private {
        require(rewardRate <= 100, "above 100");
        s.vault[vault].dittoMatchedRate = rewardRate;
    }

    function _setDittoShorterRate(uint256 vault, uint16 rewardRate) private {
        require(rewardRate <= 100, "above 100");
        s.vault[vault].dittoShorterRate = rewardRate;
    }

    function _setInitialCR(address asset, uint16 value) private {
        STypes.Asset storage Asset = s.asset[asset];
        Asset.initialCR = value;
        require(LibAsset.initialCR(Asset) < C.CRATIO_MAX, "above max CR");
    }

    function _setLiquidationCR(address asset, uint16 value) private {
        require(value > 100, "below 1.0");
        require(value <= 500, "above 5.0");
        s.asset[asset].liquidationCR = value;
    }

    function _setForcedBidPriceBuffer(address asset, uint8 value) private {
        require(value >= 100, "below 1.0");
        require(value <= 200, "above 2.0");
        s.asset[asset].forcedBidPriceBuffer = value;
    }

    function _setPenaltyCR(address asset, uint8 value) private {
        require(value >= 100, "below 1.0");
        require(value <= 120, "above 1.2");
        s.asset[asset].penaltyCR = value;
        require(LibAsset.penaltyCR(asset) < LibAsset.liquidationCR(asset), "above liquidation CR");
    }

    function _setTappFeePct(address asset, uint8 value) private {
        require(value > 0, "Can't be zero");
        require(value <= 250, "above 250");
        s.asset[asset].tappFeePct = value;
    }

    function _setCallerFeePct(address asset, uint8 value) private {
        require(value > 0, "Can't be zero");
        require(value <= 250, "above 250");
        s.asset[asset].callerFeePct = value;
    }

    function _setMinBidEth(address asset, uint8 value) private {
        //no upperboard check because uint8 max - 255
        require(value > 0, "Can't be zero");
        s.asset[asset].minBidEth = value;
    }

    function _setMinAskEth(address asset, uint8 value) private {
        //no upperboard check because uint8 max - 255
        require(value > 0, "Can't be zero");
        s.asset[asset].minAskEth = value;
    }

    function _setMinShortErc(address asset, uint16 value) private {
        //no upperboard check because uint8 max - 65,535
        require(value > 0, "Can't be zero");
        s.asset[asset].minShortErc = value;
    }

    function _setWithdrawalFee(address bridge, uint16 withdrawalFee) private {
        require(withdrawalFee <= 200, "above 2.00%");
        s.bridge[bridge].withdrawalFee = withdrawalFee;
    }

    function _setRecoveryCR(address asset, uint8 value) private {
        require(value >= 100, "below 1.0");
        require(value <= 200, "above 2.0");
        s.asset[asset].recoveryCR = value;
    }

    function _setDiscountPenaltyFee(address asset, uint16 value) private {
        require(value > 0, "Can't be zero");
        require(value <= 1000, "above 10.0%");
        s.asset[asset].discountPenaltyFee = value;
    }

    function _setDiscountMultiplier(address asset, uint16 value) private {
        require(value > 0, "Can't be zero");
        require(value < type(uint16).max, "above 65534");
        s.asset[asset].discountMultiplier = value;
    }

    function _setYieldVault(address asset, address vault) private {
        require(vault != address(0), "Can't be zero");
        s.yieldVault[asset] = vault;
    }
}
