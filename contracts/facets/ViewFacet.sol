// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {U256, U96, U88, U80} from "contracts/libraries/PRBMathHelper.sol";

import {C} from "contracts/libraries/Constants.sol";
import {Modifiers} from "contracts/libraries/AppStorage.sol";
import {STypes, MTypes, O, SR} from "contracts/libraries/DataTypes.sol";
import {LibAsset} from "contracts/libraries/LibAsset.sol";
import {LibOrders} from "contracts/libraries/LibOrders.sol";
import {LibOracle} from "contracts/libraries/LibOracle.sol";
import {LibVault} from "contracts/libraries/LibVault.sol";
import {LibShortRecord} from "contracts/libraries/LibShortRecord.sol";

// import {console} from "contracts/libraries/console.sol";

contract ViewFacet is Modifiers {
    using LibOrders for mapping(address => mapping(uint16 => STypes.Order));
    using LibShortRecord for STypes.ShortRecord;
    using U256 for uint256;
    using U96 for uint96;
    using U88 for uint88;
    using U80 for uint80;
    using LibVault for uint256;

    address private immutable dusd;

    constructor(address _dusd) {
        dusd = _dusd;
    }

    /// Vault View Functions
    function getDethBalance(uint256 vault, address user) external view nonReentrantView returns (uint256) {
        return s.vaultUser[vault][user].ethEscrowed;
    }

    function getAssetBalance(address asset, address user) external view nonReentrantView returns (uint256) {
        return s.assetUser[asset][user].ercEscrowed;
    }

    // @dev does not need read only reentrancy
    function getVault(address asset) external view returns (uint256) {
        return s.asset[asset].vault;
    }

    // @dev does not need read only reentrancy
    // @dev vault of bridge is stored separately from asset vault
    function getBridgeVault(address bridge) external view returns (uint256) {
        return s.bridge[bridge].vault;
    }

    function getDethYieldRate(uint256 vault) external view returns (uint256) {
        return s.vault[vault].dethYieldRate;
    }

    /// Order View Functions
    /**
     * @notice See all sorted bids on market
     *
     * @param asset The market that will be impacted
     *
     * @return orders List of Orders
     */
    function getBids(address asset) external view nonReentrantView returns (STypes.Order[] memory) {
        return s.bids.currentOrders(asset);
    }

    /**
     * @notice See all sorted asks on market
     *
     * @param asset The market that will be impacted
     *
     * @return orders List of Orders
     */
    function getAsks(address asset) external view nonReentrantView returns (STypes.Order[] memory) {
        return s.asks.currentOrders(asset);
    }

    /**
     * @notice See all sorted shorts on market
     *
     * @param asset The market that will be impacted
     *
     * @return orders List of Orders
     */
    function getShorts(address asset) external view nonReentrantView returns (STypes.Order[] memory) {
        return s.shorts.currentOrders(asset);
    }

    /**
     * @notice Returns correct Id of bid based on its price
     * @dev does not need read only reentrancy
     *
     * @param asset The market that will be impacted
     * @param price price of bid
     *
     * @return hintId Exact bid ID in sorted Bid Orders
     */
    function getBidHintId(address asset, uint256 price) external view returns (uint16 hintId) {
        return LibOrders.getOrderId(s.bids, asset, C.NEXT, C.HEAD, price, O.LimitBid);
    }

    /**
     * @notice Returns correct Id of ask based on its price
     * @dev does not need read only reentrancy
     *
     * @param asset The market that will be impacted
     * @param price price of ask
     *
     * @return hintId Exact ask ID in sorted Ask Orders
     */
    function getAskHintId(address asset, uint256 price) external view returns (uint16 hintId) {
        return LibOrders.getOrderId(s.asks, asset, C.NEXT, C.HEAD, price, O.LimitAsk);
    }

    /**
     * @notice Returns correct Id of short based on its price
     * @dev does not need read only reentrancy
     *
     * @param asset The market that will be impacted
     * @param price price of short
     *
     * @return hintId Exact short ID in sorted Short Orders
     */
    function getShortHintId(address asset, uint256 price) external view returns (uint16) {
        return LibOrders.getOrderId(s.shorts, asset, C.NEXT, C.HEAD, price, O.LimitShort);
    }

    /**
     * @notice Returns correct Id of short >= oracle price
     *
     * @param asset The market that will be impacted
     *
     * @return shortHintId Exact short ID in sorted Short Orders
     */
    function getShortIdAtOracle(address asset) external view nonReentrantView returns (uint16 shortHintId) {
        // if 5 is oracle price
        // .. 3 4 [5] 5 5..
        // price is 5-1=4, gets last o with price of 4, get o.next to get [5]
        uint16 idBeforeOracle =
            LibOrders.getOrderId(s.shorts, asset, C.NEXT, C.HEAD, LibOracle.getOraclePrice(asset) - 1 wei, O.LimitShort);

        // @dev If id is the last item, return the last item
        if (s.shorts[asset][idBeforeOracle].nextId == C.TAIL) {
            return idBeforeOracle;
        } else {
            return s.shorts[asset][idBeforeOracle].nextId;
        }
    }

    // @dev does not need read only reentrancy
    function getHintArray(address asset, uint256 price, O orderType, uint256 numHints)
        external
        view
        returns (MTypes.OrderHint[] memory orderHintArray)
    {
        orderHintArray = new MTypes.OrderHint[](numHints);
        uint16 _hintId;
        uint32 _creationTime;

        if (orderType == O.LimitBid) {
            _hintId = LibOrders.getOrderId(s.bids, asset, C.NEXT, C.HEAD, price, orderType);
            _creationTime = s.bids[asset][_hintId].creationTime;
        } else if (orderType == O.LimitAsk) {
            _hintId = LibOrders.getOrderId(s.asks, asset, C.NEXT, C.HEAD, price, orderType);
            _creationTime = s.asks[asset][_hintId].creationTime;
        } else if (orderType == O.LimitShort) {
            _hintId = LibOrders.getOrderId(s.shorts, asset, C.NEXT, C.HEAD, price, orderType);
            _creationTime = s.shorts[asset][_hintId].creationTime;
        }

        orderHintArray[0] = MTypes.OrderHint({hintId: _hintId, creationTime: _creationTime});

        for (uint256 i = 1; i < numHints; i++) {
            if (orderType == O.LimitBid) {
                STypes.Order storage bid = s.bids[asset][_hintId];
                _hintId = bid.nextId;
                _creationTime = bid.creationTime;
            } else if (orderType == O.LimitAsk) {
                STypes.Order storage ask = s.asks[asset][_hintId];
                _hintId = ask.nextId;
                _creationTime = ask.creationTime;
            } else if (orderType == O.LimitShort) {
                STypes.Order storage short = s.shorts[asset][_hintId];
                _hintId = short.nextId;
                _creationTime = short.creationTime;
            }

            // @dev break from loop to prevent considering cancelled/matched/uninitialized orderIds as hint
            if (_hintId == C.HEAD) break;

            orderHintArray[i] = MTypes.OrderHint({hintId: _hintId, creationTime: _creationTime});
        }

        return orderHintArray;
    }

    /// Oracle View Functionss
    /**
     * @notice computes the c-ratio of a specific short at protocol price
     *
     * @param short Short
     *
     * @return cRatio
     */
    function getCollateralRatio(address asset, STypes.ShortRecord memory short)
        external
        view
        nonReentrantView
        returns (uint256 cRatio)
    {
        uint256 oraclePrice = LibOracle.getSavedOrSpotOraclePrice(asset);
        return short.getCollateralRatio(oraclePrice);
    }

    // @dev does not need read only reentrancy
    function getOracleAssetPrice(address asset) external view returns (uint256) {
        return LibOracle.getOraclePrice(asset);
    }

    // @dev does not need read only reentrancy
    function getProtocolAssetPrice(address asset) external view returns (uint256) {
        return LibOracle.getPrice(asset);
    }

    // @dev does not need read only reentrancy
    function getProtocolAssetTime(address asset) external view returns (uint256) {
        return LibOracle.getTime(asset);
    }

    /// Yield View Functions
    // @dev does not need read only reentrancy
    function getTithe(uint256 vault) external view returns (uint256) {
        return (uint256(s.vault[vault].dethTithePercent) * 1 ether) / C.FOUR_DECIMAL_PLACES;
    }

    function getUndistributedYield(uint256 vault) external view nonReentrantView returns (uint256) {
        return vault.getDethTotal() - s.vault[vault].dethTotal;
    }

    function getYield(address asset, address user) external view nonReentrantView returns (uint256 shorterYield) {
        uint256 vault = s.asset[asset].vault;
        uint256 dethYieldRate = s.vault[vault].dethYieldRate;
        uint8 id = s.shortRecords[asset][user][C.HEAD].nextId;

        while (true) {
            // One short of one shorter in this order book
            STypes.ShortRecord storage currentShort = s.shortRecords[asset][user][id];
            // @dev: isNotRecentlyModified is mainly for flash loans or loans where they want to deposit to claim yield immediately
            bool isNotRecentlyModified = LibOrders.getOffsetTime() - currentShort.updatedAt > C.YIELD_DELAY_SECONDS;

            if (currentShort.status != SR.Closed && isNotRecentlyModified) {
                // Yield earned by this short
                shorterYield += currentShort.collateral.mul(dethYieldRate - currentShort.dethYieldRate);
            }
            // Move to next short unless this is the last one
            if (currentShort.nextId > C.HEAD) {
                id = currentShort.nextId;
            } else {
                break;
            }
        }
        return shorterYield;
    }

    function getDittoMatchedReward(uint256 vault, address user) external view nonReentrantView returns (uint256) {
        uint256 shares = s.vaultUser[vault][user].dittoMatchedShares;
        if (shares <= 1) {
            return 0;
        }
        shares -= 1;

        STypes.Vault storage Vault = s.vault[vault];
        // Total token reward amount for limit orders
        uint256 protocolTime = LibOrders.getOffsetTime() / 1 days;
        uint256 elapsedTime = protocolTime - Vault.dittoMatchedTime;
        uint256 totalReward = Vault.dittoMatchedReward + (elapsedTime * 1 days).mul(LibVault.dittoMatchedRate(vault));
        // User's proportion of the total token reward
        uint256 sharesTotal = Vault.dittoMatchedShares;
        return shares.mul(totalReward).div(sharesTotal);
    }

    function getDittoReward(uint256 vault, address user) external view nonReentrantView returns (uint256) {
        STypes.VaultUser storage VaultUser = s.vaultUser[vault][user];
        if (VaultUser.dittoReward <= 1) {
            return 0;
        } else {
            return VaultUser.dittoReward - 1;
        }
    }

    /// Market Shutdown View Functions
    /**
     * @notice Computes the c-ratio of an asset class
     *
     * @param asset The market that will be impacted
     *
     * @return cRatio
     */
    function getAssetCollateralRatio(address asset) external view nonReentrantView returns (uint256 cRatio) {
        STypes.Asset storage Asset = s.asset[asset];
        return LibAsset.getAssetCollateralRatio(Asset, LibOracle.getOraclePrice(asset));
    }

    /// ShortRecord View Functions
    /**
     * @notice Returns shortRecords for an asset of a given address
     *
     * @param asset The market that will be impacted
     * @param shorter Shorter address
     *
     * @return shorts
     */
    function getShortRecords(address asset, address shorter)
        external
        view
        nonReentrantView
        returns (STypes.ShortRecord[] memory shorts)
    {
        uint256 length = LibShortRecord.getShortRecordCount(asset, shorter);

        STypes.ShortRecord[] memory shortRecords = new STypes.ShortRecord[](length);

        uint8 id = s.shortRecords[asset][shorter][C.HEAD].nextId;
        if (id <= C.HEAD) {
            return shorts;
        }

        uint256 i;

        while (true) {
            STypes.ShortRecord storage currentShort = s.shortRecords[asset][shorter][id];
            // @dev skip all of the "empty SRs"
            if (currentShort.status == SR.Closed && currentShort.nextId > C.TAIL) {
                id = currentShort.nextId;
                continue;
            }

            if (currentShort.status != SR.Closed) {
                shortRecords[i] = currentShort;
            }

            if (currentShort.nextId > C.HEAD) {
                id = currentShort.nextId;
                i++;
            } else {
                return shortRecords;
            }
        }
    }

    /**
     * @notice Returns shortRecord
     *
     * @param asset The market that will be impacted
     * @param shorter Shorter address
     * @param id id of short
     *
     * @return shortRecord
     */
    function getShortRecord(address asset, address shorter, uint8 id)
        external
        view
        nonReentrantView
        returns (STypes.ShortRecord memory shortRecord)
    {
        return s.shortRecords[asset][shorter][id];
    }

    /**
     * @notice Returns number of active shorts of a shorter
     *
     * @param asset The market that will be impacted
     * @param shorter Shorter address
     *
     * @return shortRecordCount Number of active shortRecords
     */
    function getShortRecordCount(address asset, address shorter)
        external
        view
        nonReentrantView
        returns (uint256 shortRecordCount)
    {
        return LibShortRecord.getShortRecordCount(asset, shorter);
    }

    /**
     * @notice Returns AssetUser struct
     *
     * @param asset The market asset being queried
     * @param user User address
     *
     * @return assetUser
     */
    function getAssetUserStruct(address asset, address user) external view nonReentrantView returns (STypes.AssetUser memory) {
        return s.assetUser[asset][user];
    }

    /**
     * @notice Returns VaultUser struct
     *
     * @param vault The vault being queried
     * @param user User address
     *
     * @return vaultUser
     */
    function getVaultUserStruct(uint256 vault, address user) external view nonReentrantView returns (STypes.VaultUser memory) {
        return s.vaultUser[vault][user];
    }

    /**
     * @notice Returns Vault struct
     *
     * @param vault The vault being queried
     *
     * @return vault
     */
    function getVaultStruct(uint256 vault) external view nonReentrantView returns (STypes.Vault memory) {
        return s.vault[vault];
    }

    /**
     * @notice Returns Asset struct
     *
     * @param asset The market asset being queried
     *
     * @return asset
     */
    function getAssetStruct(address asset) external view nonReentrantView returns (STypes.Asset memory) {
        return s.asset[asset];
    }

    /**
     * @notice Returns Bridge struct
     *
     * @param bridge The bridge address being queried
     *
     * @return bridge
     */
    function getBridgeStruct(address bridge) external view nonReentrantView returns (STypes.Bridge memory) {
        return s.bridge[bridge];
    }

    /**
     * @notice Returns offset time
     *
     * @return offsetTime
     */
    function getOffsetTime() external view returns (uint256) {
        return LibOrders.getOffsetTime();
    }

    function getShortOrderId(address asset, address shorter, uint8 shortRecordId) external view returns (uint16 shortOrderId) {
        STypes.Order[] memory shorts = s.shorts.currentOrders(asset);
        for (uint256 i = 0; i < shorts.length; i++) {
            if (shorts[i].addr == shorter && shorts[i].shortRecordId == shortRecordId) {
                return shorts[i].id;
            }
        }
    }

    function getShortOrderIdArray(address asset, address shorter, uint8[] memory shortRecordIds)
        external
        view
        returns (uint16[] memory shortOrderIds)
    {
        STypes.Order[] memory shorts = s.shorts.currentOrders(asset);

        shortOrderIds = new uint16[](shortRecordIds.length);

        for (uint256 i = 0; i < shortRecordIds.length; i++) {
            uint16 shortRecordId = shortRecordIds[i];
            for (uint256 j = 0; j < shorts.length; j++) {
                if (shorts[j].addr == shorter && shorts[j].shortRecordId == shortRecordId) {
                    shortOrderIds[i] = shorts[j].id;
                }
            }
        }
        return shortOrderIds;
    }

    function getMinShortErc(address asset) external view returns (uint256) {
        return LibAsset.minShortErc(s.asset[asset]);
    }

    function getTimeSinceDiscounted(address asset) external view returns (uint32 timeSinceLastDiscount) {
        return LibOrders.getOffsetTime() - s.asset[asset].lastDiscountTime;
    }

    function getInitialDiscountTime(address asset) external view returns (uint32 initialDiscountTime) {
        return s.asset[asset].initialDiscountTime;
    }

    // @dev Returns ercDebt after updateErcDebt is called
    function getExpectedSRDebt(address asset, address shorter, uint8 id) external view returns (uint88 updatedErcDebt) {
        STypes.ShortRecord memory shortRecord = s.shortRecords[asset][shorter][id];
        uint80 ercDebtRate = s.asset[asset].ercDebtRate;
        uint88 ercDebt = (shortRecord.ercDebt - shortRecord.ercDebtFee).mulU88(ercDebtRate - shortRecord.ercDebtRate);
        return shortRecord.ercDebt + ercDebt;
    }
}
