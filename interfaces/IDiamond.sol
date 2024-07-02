// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {IDiamondLoupe} from "contracts/interfaces/IDiamondLoupe.sol";
import {IDiamondCut} from "contracts/interfaces/IDiamondCut.sol";
import "contracts/libraries/DataTypes.sol";
import "test/utils/TestTypes.sol";

interface IDiamond {

  // functions from contracts/Diamond.sol
  fallback() external payable;
  receive() external payable;
  // functions from contracts/facets/DiamondCutFacet.sol
  function diamondCut(IDiamondCut.FacetCut[] calldata _diamondCut, address _init, bytes calldata _calldata) external;
  // functions from contracts/facets/ViewRedemptionFacet.sol
  function getTimeToDispute(uint256 lastCR) external view returns (uint32 timeToDispute);
  function getRedemptionFee(address asset, uint88 ercDebtRedeemed, uint88 colRedeemed) external view returns (uint88 redemptionFee);
  function readProposalData(address asset, address redeemer) external view returns (uint32, uint32, uint80, uint80, MTypes.ProposalData[] memory);
  // functions from contracts/facets/OwnerFacet.sol
  function createMarket(address asset, address yieldVault, STypes.Asset memory a) external;
  function owner() external view returns (address);
  function admin() external view returns (address);
  function ownerCandidate() external view returns (address);
  function transferOwnership(address newOwner) external;
  function claimOwnership() external;
  function transferAdminship(address newAdmin) external;
  function createVault(address deth, uint256 vault, MTypes.CreateVaultParams calldata params) external;
  function setTithe(uint256 vault, uint16 dethTithePercent) external;
  function setDittoMatchedRate(uint256 vault, uint16 rewardRate) external;
  function setDittoShorterRate(uint256 vault, uint16 rewardRate) external;
  function setInitialCR(address asset, uint16 value) external;
  function setLiquidationCR(address asset, uint16 value) external;
  function setForcedBidPriceBuffer(address asset, uint8 value) external;
  function setPenaltyCR(address asset, uint8 value) external;
  function setTappFeePct(address asset, uint8 value) external;
  function setCallerFeePct(address asset, uint8 value) external;
  function setMinBidEth(address asset, uint8 value) external;
  function setMinAskEth(address asset, uint8 value) external;
  function setMinShortErc(address asset, uint16 value) external;
  function setRecoveryCR(address asset, uint8 value) external;
  function setDiscountPenaltyFee(address asset, uint16 value) external;
  function setDiscountMultiplier(address asset, uint16 value) external;
  function setYieldVault(address asset, address vault) external;
  function createBridge(address bridge, uint256 vault, uint16 withdrawalFee) external;
  function setWithdrawalFee(address bridge, uint16 withdrawalFee) external;
  // functions from contracts/facets/PrimaryLiquidationFacet.sol
  function liquidate(address asset, address shorter, uint8 id, uint16[] memory shortHintArray, uint16 shortOrderId) external returns (uint88, uint88);
  // functions from contracts/facets/AskOrdersFacet.sol
  function createAsk(
        address asset, uint80 price, uint88 ercAmount, bool isMarketOrder, MTypes.OrderHint[] calldata orderHintArray) external;
  function _cancelAsk(address asset, uint16 id) external;
  function _cancelShort(address asset, uint16 id) external;
  // functions from contracts/facets/ProposeRedemptionFacet.sol
  function proposeRedemption(
        address asset, MTypes.ProposalInput[] calldata proposalInput, uint88 redemptionAmount, uint88 maxRedemptionFee, uint256 deadline) external;
  // functions from contracts/facets/DisputeRedemptionFacet.sol
  function disputeRedemption(address asset, address redeemer, uint8 incorrectIndex, address disputeShorter, uint8 disputeShortId) external;
  // functions from contracts/facets/DiamondEtherscanFacet.sol
  function setDummyImplementation(address _implementation) external;
  function implementation() external view returns (address);
  // functions from contracts/facets/TWAPFacet.sol
  function estimateWETHInUSDC(uint128 amountIn, uint32 secondsAgo) external view returns (uint256 amountOut);
  // functions from contracts/facets/ViewFacet.sol
  function getDethBalance(uint256 vault, address user) external view returns (uint256);
  function getAssetBalance(address asset, address user) external view returns (uint256);
  function getVault(address asset) external view returns (uint256);
  function getBridgeVault(address bridge) external view returns (uint256);
  function getDethYieldRate(uint256 vault) external view returns (uint256);
  function getBids(address asset) external view returns (STypes.Order[] memory);
  function getAsks(address asset) external view returns (STypes.Order[] memory);
  function getShorts(address asset) external view returns (STypes.Order[] memory);
  function getBidHintId(address asset, uint256 price) external view returns (uint16 hintId);
  function getAskHintId(address asset, uint256 price) external view returns (uint16 hintId);
  function getShortHintId(address asset, uint256 price) external view returns (uint16);
  function getShortIdAtOracle(address asset) external view returns (uint16 shortHintId);
  function getHintArray(address asset, uint256 price, O orderType, uint256 numHints) external view returns (MTypes.OrderHint[] memory orderHintArray);
  function getCollateralRatio(address asset, STypes.ShortRecord memory short) external view returns (uint256 cRatio);
  function getOracleAssetPrice(address asset) external view returns (uint256);
  function getProtocolAssetPrice(address asset) external view returns (uint256);
  function getProtocolAssetTime(address asset) external view returns (uint256);
  function getTithe(uint256 vault) external view returns (uint256);
  function getUndistributedYield(uint256 vault) external view returns (uint256);
  function getYield(address asset, address user) external view returns (uint256 shorterYield);
  function getDittoMatchedReward(uint256 vault, address user) external view returns (uint256);
  function getDittoReward(uint256 vault, address user) external view returns (uint256);
  function getAssetCollateralRatio(address asset) external view returns (uint256 cRatio);
  function getShortRecords(address asset, address shorter) external view returns (STypes.ShortRecord[] memory shorts);
  function getShortRecord(address asset, address shorter, uint8 id) external view returns (STypes.ShortRecord memory shortRecord);
  function getShortRecordCount(address asset, address shorter) external view returns (uint256 shortRecordCount);
  function getAssetUserStruct(address asset, address user) external view returns (STypes.AssetUser memory);
  function getVaultUserStruct(uint256 vault, address user) external view returns (STypes.VaultUser memory);
  function getVaultStruct(uint256 vault) external view returns (STypes.Vault memory);
  function getAssetStruct(address asset) external view returns (STypes.Asset memory);
  function getBridgeStruct(address bridge) external view returns (STypes.Bridge memory);
  function getOffsetTime() external view returns (uint256);
  function getShortOrderId(address asset, address shorter, uint8 shortRecordId) external view returns (uint16 shortOrderId);
  function getShortOrderIdArray(address asset, address shorter, uint8[] memory shortRecordIds) external view returns (uint16[] memory shortOrderIds);
  function getMinShortErc(address asset) external view returns (uint256);
  function getTimeSinceDiscounted(address asset) external view returns (uint32 timeSinceLastDiscount);
  function getInitialDiscountTime(address asset) external view returns (uint32 initialDiscountTime);
  function getExpectedSRDebt(address asset, address shorter, uint8 id) external view returns (uint88 updatedErcDebt);
  // functions from contracts/facets/DiamondLoupeFacet.sol
  function facets() external view returns (IDiamondLoupe.Facet[] memory facets_);
  function facetFunctionSelectors(address _facet) external view returns (bytes4[] memory _facetFunctionSelectors);
  function facetAddresses() external view returns (address[] memory facetAddresses_);
  function facetAddress(bytes4 _functionSelector) external view returns (address facetAddress_);
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
  // functions from contracts/facets/BridgeRouterFacet.sol
  function getDethTotal(uint256 vault) external view returns (uint256);
  function getBridges(uint256 vault) external view returns (address[] memory);
  function deposit(address bridge, uint88 amount) external;
  function depositEth(address bridge) external payable;
  function withdraw(address bridge, uint88 dethAmount) external;
  function withdrawTapp(address bridge, uint88 dethAmount) external;
  // functions from contracts/facets/ExitShortFacet.sol
  function exitShortWallet(address asset, uint8 id, uint88 buybackAmount, uint16 shortOrderId) external;
  function exitShortErcEscrowed(address asset, uint8 id, uint88 buybackAmount, uint16 shortOrderId) external;
  function exitShort(
        address asset, uint8 id, uint88 buybackAmount, uint80 price, uint16[] memory shortHintArray, uint16 shortOrderId) external;
  // functions from contracts/facets/ShortRecordFacet.sol
  function increaseCollateral(address asset, uint8 id, uint88 amount) external;
  function decreaseCollateral(address asset, uint8 id, uint88 amount) external;
  function combineShorts(address asset, uint8[] memory ids, uint16[] memory shortOrderIds) external;
  // functions from contracts/facets/OrdersFacet.sol
  function cancelBid(address asset, uint16 id) external;
  function cancelAsk(address asset, uint16 id) external;
  function cancelShort(address asset, uint16 id) external;
  function cancelOrderFarFromOracle(address asset, O orderType, uint16 lastOrderId, uint16 numOrdersToCancel) external;
  function _matchIsDiscounted(MTypes.HandleDiscount memory h) external;
  // functions from contracts/facets/ShortOrdersFacet.sol
  function createLimitShort(
        address asset, uint80 price, uint88 ercAmount, MTypes.OrderHint[] memory orderHintArray, uint16[] memory shortHintArray, uint16 shortOrderCR) external;
  // functions from contracts/facets/ClaimRedemptionFacet.sol
  function claimRedemption(address asset) external;
  function claimRemainingCollateral(address asset, address redeemer, uint8 claimIndex, uint8 id) external;
  // functions from contracts/facets/ThrowAwayFacet.sol
  function zeroOutLastRedemption() external;
  // functions from contracts/facets/YieldFacet.sol
  function updateYield(uint256 vault) external;
  function _updateYieldDiamond(uint256 vault) external;
  function distributeYield(address[] calldata assets) external;
  function claimDittoMatchedReward(uint256 vault) external;
  function withdrawDittoReward(uint256 vault) external;
  // functions from contracts/facets/VaultFacet.sol
  function depositAsset(address asset, uint104 amount) external;
  function withdrawAsset(address asset, uint104 amount) external;
  // functions from contracts/facets/BidOrdersFacet.sol
  function createBid(
        address asset, uint80 price, uint88 ercAmount, bool isMarketOrder, MTypes.OrderHint[] calldata orderHintArray, uint16[] calldata shortHintArray) external returns (uint88 ethFilled, uint88 ercAmountLeft);
  function createForcedBid(address sender, address asset, uint80 price, uint88 ercAmount, uint16[] calldata shortHintArray) external returns (uint88 ethFilled, uint88 ercAmountLeft);
  // functions from contracts/facets/SecondaryLiquidationFacet.sol
  function liquidateSecondary(address asset, MTypes.BatchLiquidation[] memory batches, uint88 liquidateAmount, bool isWallet) external;
  // functions from contracts/facets/MarketShutdownFacet.sol
  function shutdownMarket(address asset) external;
  function redeemErc(address asset, uint88 amtWallet, uint88 amtEscrow) external;
}