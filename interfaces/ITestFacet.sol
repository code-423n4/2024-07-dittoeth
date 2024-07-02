// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;


import {STypes,O,F} from "contracts/libraries/DataTypes.sol";
import {TestTypes} from "test/utils/TestTypes.sol";

interface ITestFacet {

  // functions from contracts/facets/TestFacet.sol
  function setFrozenT(address asset, F value) external;
  function setLiquidationCRT(address asset, uint16 value) external;
  function getAskKey(address asset, uint16 id) external view returns (uint16 prevId, uint16 nextId);
  function getBidKey(address asset, uint16 id) external view returns (uint16 prevId, uint16 nextId);
  function getBidOrder(address asset, uint16 id) external view returns (STypes.Order memory bid);
  function getAskOrder(address asset, uint16 id) external view returns (STypes.Order memory ask);
  function getShortOrder(address asset, uint16 id) external view returns (STypes.Order memory short);
  function currentInactiveBids(address asset) external view returns (STypes.Order[] memory);
  function currentInactiveAsks(address asset) external view returns (STypes.Order[] memory);
  function setReentrantStatus(uint8 reentrantStatus) external;
  function getReentrantStatus() external view returns (uint256);
  function getAssetNormalizedStruct(address asset) external view returns (TestTypes.AssetNormalizedStruct memory);
  function getBridgeNormalizedStruct(address bridge) external view returns (TestTypes.BridgeNormalizedStruct memory);
  function getWithdrawalFeePct(uint256 bridgePointer, address rethBridge, address stethBridge) external view returns (uint256);
  function setBaseOracle(address _oracle) external;
  function setOracleTimeAndPrice(address asset, uint256 price) external;
  function getOracleTimeT(address asset) external view returns (uint256 oracleTime);
  function getOraclePriceT(address asset) external view returns (uint80 oraclePrice);
  function setStartingShortId(address asset, uint16 id) external;
  function updateStartingShortId(address asset, uint16[] calldata shortHintArray) external;
  function setDethYieldRate(uint256 vault, uint256 value) external;
  function nonZeroVaultSlot0(uint256 vault) external;
  function setforcedBidPriceBufferT(address asset, uint8 value) external;
  function setErcDebtRateAsset(address asset, uint64 value) external;
  function setOrderIdT(address asset, uint16 value) external;
  function setEthEscrowed(address addr, uint88 eth) external;
  function setBridgeCredit(address addr, uint88 bridgeCreditReth, uint88 bridgeCreditSteth) external;
  function getUserOrders(address asset, address addr, O orderType) external view returns (STypes.Order[] memory orders);
  function getAssets() external view returns (address[] memory);
  function dittoShorterRate(uint256 vault) external view returns (uint256);
  function dittoMatchedRate(uint256 vault) external view returns (uint256);
  function deleteBridge(address bridge) external;
  function setAssetOracle(address asset, address oracle) external;
  function setErcDebt(address asset, address shorter, uint8 id, uint88 value) external;
  function setErcDebtAsset(address asset, uint88 value) external;
  function setDiscountedErcMatchedAsset(address asset, uint104 value) external;
  function setInitialDiscountTimeAsset(address asset, uint32 value) external;
  function addErcDebtAsset(address asset, uint88 value) external;
  function setLastRedemptionTime(address asset, uint32 lastRedemptionTime) external;
  function setBaseRate(address asset, uint64 baseRate) external;
  function setMinShortErcT(address asset, uint16 value) external;
  function addErcDebtFee(address asset, address shorter, uint8 id, uint88 value) external;
}