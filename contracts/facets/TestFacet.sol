// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {U256} from "contracts/libraries/PRBMathHelper.sol";
import {STypes, O, F} from "contracts/libraries/DataTypes.sol";
import {Modifiers} from "contracts/libraries/AppStorage.sol";
import {LibOracle} from "contracts/libraries/LibOracle.sol";
import {LibBridgeRouter} from "contracts/libraries/LibBridgeRouter.sol";
import {LibOrders} from "contracts/libraries/LibOrders.sol";
import {LibAsset} from "contracts/libraries/LibAsset.sol";
import {Errors} from "contracts/libraries/Errors.sol";
import {LibBridge} from "contracts/libraries/LibBridge.sol";
import {C, VAULT} from "contracts/libraries/Constants.sol";

import {TestTypes} from "test/utils/TestTypes.sol";
// import {console} from "contracts/libraries/console.sol";

// @dev dev-only
contract TestFacet is Modifiers {
    using LibOrders for mapping(address => mapping(uint16 => STypes.Order));
    using U256 for uint256;

    address private immutable baseAsset;

    constructor(address asset) {
        baseAsset = asset;
    }

    function setFrozenT(address asset, F value) external {
        s.asset[asset].frozen = value;
    }

    // @dev same as OwnerFacet.setLiquidationCR without requires for testing
    function setLiquidationCRT(address asset, uint16 value) external {
        s.asset[asset].liquidationCR = value;
    }

    function getAskKey(address asset, uint16 id) external view returns (uint16 prevId, uint16 nextId) {
        return (s.asks[asset][id].prevId, s.asks[asset][id].nextId);
    }

    function getBidKey(address asset, uint16 id) external view returns (uint16 prevId, uint16 nextId) {
        return (s.bids[asset][id].prevId, s.bids[asset][id].nextId);
    }

    function getBidOrder(address asset, uint16 id) external view returns (STypes.Order memory bid) {
        return s.bids[asset][id];
    }

    function getAskOrder(address asset, uint16 id) external view returns (STypes.Order memory ask) {
        return s.asks[asset][id];
    }

    function getShortOrder(address asset, uint16 id) external view returns (STypes.Order memory short) {
        return s.shorts[asset][id];
    }

    function currentInactiveBids(address asset) external view returns (STypes.Order[] memory) {
        uint16 currentId = s.bids[asset][C.HEAD].prevId;
        uint256 orderSize;

        while (currentId != C.HEAD) {
            orderSize++;
            currentId = s.bids[asset][currentId].prevId;
        }

        STypes.Order[] memory orderArr = new STypes.Order[](orderSize);
        currentId = s.bids[asset][C.HEAD].prevId; // reset currentId

        for (uint256 i = 0; i < orderSize; i++) {
            orderArr[i] = s.bids[asset][currentId];
            currentId = orderArr[i].prevId;
        }
        return orderArr;
    }

    function currentInactiveAsks(address asset) external view returns (STypes.Order[] memory) {
        uint16 currentId = s.asks[asset][C.HEAD].prevId;
        uint256 orderSize;

        while (currentId != C.HEAD) {
            orderSize++;
            currentId = s.asks[asset][currentId].prevId;
        }

        STypes.Order[] memory orderArr = new STypes.Order[](orderSize);
        currentId = s.asks[asset][C.HEAD].prevId; // reset currentId

        for (uint256 i = 0; i < orderSize; i++) {
            orderArr[i] = s.asks[asset][currentId];
            currentId = orderArr[i].prevId;
        }
        return orderArr;
    }

    // @dev unused
    // function currentInactiveShorts(address asset) external view returns (STypes.Order[] memory) {
    //     uint16 currentId = s.shorts[asset][C.HEAD].prevId;
    //     uint256 orderSize;

    //     while (currentId != C.HEAD) {
    //         orderSize++;
    //         currentId = s.shorts[asset][currentId].prevId;
    //     }

    //     STypes.Order[] memory orderArr = new STypes.Order[](orderSize);
    //     currentId = s.shorts[asset][C.HEAD].prevId; // reset currentId

    //     for (uint256 i = 0; i < orderSize; i++) {
    //         orderArr[i] = s.shorts[asset][currentId];
    //         currentId = orderArr[i].prevId;
    //     }
    //     return orderArr;
    // }

    function setReentrantStatus(uint8 reentrantStatus) external {
        s.reentrantStatus = reentrantStatus;
    }

    function getReentrantStatus() external view returns (uint256) {
        return s.reentrantStatus;
    }

    function getAssetNormalizedStruct(address asset) external view returns (TestTypes.AssetNormalizedStruct memory) {
        STypes.Asset storage Asset = s.asset[asset];
        return TestTypes.AssetNormalizedStruct({
            frozen: s.asset[asset].frozen,
            orderId: s.asset[asset].orderIdCounter,
            initialCR: LibAsset.initialCR(Asset),
            liquidationCR: LibAsset.liquidationCR(asset),
            forcedBidPriceBuffer: LibAsset.forcedBidPriceBuffer(asset),
            penaltyCR: LibAsset.penaltyCR(asset),
            tappFeePct: LibAsset.tappFeePct(asset),
            callerFeePct: LibAsset.callerFeePct(asset),
            startingShortId: s.asset[asset].startingShortId,
            minBidEth: LibAsset.minBidEth(asset),
            minAskEth: LibAsset.minAskEth(Asset),
            minShortErc: LibAsset.minShortErc(Asset),
            assetId: s.asset[asset].assetId,
            recoveryCR: LibAsset.recoveryCR(Asset),
            discountPenaltyFee: LibAsset.discountPenaltyFee(Asset)
        });
    }

    function getBridgeNormalizedStruct(address bridge) external view returns (TestTypes.BridgeNormalizedStruct memory) {
        return TestTypes.BridgeNormalizedStruct({withdrawalFee: LibBridge.withdrawalFee(bridge)});
    }

    function getWithdrawalFeePct(uint256 bridgePointer, address rethBridge, address stethBridge) external view returns (uint256) {
        return LibBridgeRouter.withdrawalFeePct(bridgePointer, rethBridge, stethBridge);
    }

    function setBaseOracle(address _oracle) external {
        s.baseOracle = _oracle;
    }

    // @dev used for gas testing
    function setOracleTimeAndPrice(address asset, uint256 price) external {
        LibOracle.setPriceAndTime(asset, price, LibOrders.getOffsetTime());
    }

    function getOracleTimeT(address asset) external view returns (uint256 oracleTime) {
        return LibOracle.getTime(asset);
    }

    function getOraclePriceT(address asset) external view returns (uint80 oraclePrice) {
        return LibOracle.getPrice(asset);
    }

    // @dev used to test shortHintId
    function setStartingShortId(address asset, uint16 id) external {
        s.asset[asset].startingShortId = id;
    }

    function updateStartingShortId(address asset, uint16[] calldata shortHintArray) external {
        LibOrders.updateOracleAndStartingShortViaTimeBidOnly(asset, shortHintArray);
    }

    // @dev used to test shortHintId
    function setDethYieldRate(uint256 vault, uint256 value) external {
        s.vault[vault].dethYieldRate = uint80(value);
    }

    function nonZeroVaultSlot0(uint256 vault) external {
        s.vault[vault].dethYieldRate += 1;
    }

    function setforcedBidPriceBufferT(address asset, uint8 value) external {
        s.asset[asset].forcedBidPriceBuffer = value;
    }

    function setErcDebtRateAsset(address asset, uint64 value) external {
        uint256 ercDebtRateOld = s.asset[asset].ercDebtRate;
        s.asset[asset].ercDebtRate = value;
        uint256 ercDebt = s.asset[asset].ercDebt;
        if (value >= ercDebtRateOld) {
            s.asset[asset].ercDebtFee += uint88(ercDebt.mul(value - ercDebtRateOld));
        }
    }

    function setOrderIdT(address asset, uint16 value) external {
        s.asset[asset].orderIdCounter = value;
    }

    function setEthEscrowed(address addr, uint88 eth) external {
        s.vaultUser[VAULT.ONE][addr].ethEscrowed = eth;
    }

    function setBridgeCredit(address addr, uint88 bridgeCreditReth, uint88 bridgeCreditSteth) external {
        s.vaultUser[VAULT.ONE][addr].bridgeCreditReth = bridgeCreditReth;
        s.vaultUser[VAULT.ONE][addr].bridgeCreditSteth = bridgeCreditSteth;
    }

    function getUserOrders(address asset, address addr, O orderType) external view returns (STypes.Order[] memory orders) {
        STypes.Order[] memory allOrders;

        if (orderType == O.LimitBid) {
            allOrders = s.bids.currentOrders(asset);
        } else if (orderType == O.LimitAsk) {
            allOrders = s.asks.currentOrders(asset);
        } else if (orderType == O.LimitShort) {
            allOrders = s.shorts.currentOrders(asset);
        }
        uint256 counter = 0;

        for (uint256 i = 0; i < allOrders.length; i++) {
            if (allOrders[i].addr == addr) counter++;
        }

        orders = new STypes.Order[](counter);
        counter = 0;

        for (uint256 i = 0; i < allOrders.length; i++) {
            if (allOrders[i].addr == addr) {
                orders[counter] = allOrders[i];
                counter++;
            }
        }
        return orders;
    }

    function getAssets() external view returns (address[] memory) {
        return s.assets;
    }

    function dittoShorterRate(uint256 vault) external view returns (uint256) {
        return (uint256(s.vault[vault].dittoShorterRate) * 1 ether) / C.TWO_DECIMAL_PLACES;
    }

    function dittoMatchedRate(uint256 vault) external view returns (uint256) {
        return (uint256(s.vault[vault].dittoMatchedRate) * 1 ether) / C.TWO_DECIMAL_PLACES;
    }

    function deleteBridge(address bridge) external onlyDAO {
        uint256 vault = s.bridge[bridge].vault;
        if (vault == 0) revert Errors.InvalidBridge();

        address[] storage VaultBridges = s.vaultBridges[vault];
        uint256 length = VaultBridges.length;
        for (uint256 i; i < length; i++) {
            if (VaultBridges[i] == bridge) {
                if (i != length - 1) {
                    VaultBridges[i] = VaultBridges[length - 1];
                }
                VaultBridges.pop();
                break;
            }
        }
        delete s.bridge[bridge];
    }

    //When deactivating an asset make sure to zero out the oracle.
    function setAssetOracle(address asset, address oracle) external onlyDAO {
        s.asset[asset].oracle = oracle;
    }

    // @dev Beware that the Asset.ercDebt is not updated in this function
    function setErcDebt(address asset, address shorter, uint8 id, uint88 value) external {
        s.shortRecords[asset][shorter][id].ercDebt = value;
    }

    function setErcDebtAsset(address asset, uint88 value) external {
        s.asset[asset].ercDebt = value;
    }

    function setDiscountedErcMatchedAsset(address asset, uint104 value) external {
        s.asset[asset].discountedErcMatched = value;
    }

    function setInitialDiscountTimeAsset(address asset, uint32 value) external {
        s.asset[asset].initialDiscountTime = value;
    }

    function addErcDebtAsset(address asset, uint88 value) external {
        s.asset[asset].ercDebt += value;
    }

    function setLastRedemptionTime(address asset, uint32 lastRedemptionTime) external {
        s.asset[asset].lastRedemptionTime = lastRedemptionTime;
    }

    function setBaseRate(address asset, uint64 baseRate) external {
        s.asset[asset].baseRate = baseRate;
    }

    function setMinShortErcT(address asset, uint16 value) external {
        s.asset[asset].minShortErc = value;
    }

    function addErcDebtFee(address asset, address shorter, uint8 id, uint88 value) external {
        s.shortRecords[asset][shorter][id].ercDebtFee += value;
        s.asset[asset].ercDebtFee += value;
    }
}
