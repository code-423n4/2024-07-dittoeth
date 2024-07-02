// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import "contracts/EtherscanDiamondImpl.sol";

interface IEtherscanDiamondImpl {

  // functions from contracts/EtherscanDiamondImpl.sol
  function diamondCut(EtherscanDiamondImpl.FacetCut[] memory _diamondCut, address _init, bytes memory _calldata) external;
  function facetAddress(bytes4 _functionSelector) external view returns (address facetAddress_);
  function facetAddresses() external view returns (address[] memory facetAddresses_);
  function facetFunctionSelectors(address _facet) external view returns (bytes4[] memory _facetFunctionSelectors);
  function facets() external view returns (EtherscanDiamondImpl.Facet[] memory facets_);
  function combineShorts(address asset, uint8[] memory ids) external;
  function decreaseCollateral(address asset, uint8 id, uint88 amount) external;
  function increaseCollateral(address asset, uint8 id, uint88 amount) external;
  function depositAsset(address asset, uint104 amount) external;
  function withdrawAsset(address asset, uint104 amount) external;
  function approve(address to, uint256 tokenId) external;
  function balanceOf(address _owner) external view returns (uint256 balance);
  function getApproved(uint256 tokenId) external view returns (address operator);
  function isApprovedForAll(address _owner, address operator) external view returns (bool);
  function mintNFT(address asset, uint8 shortRecordId) external;
  function ownerOf(uint256 tokenId) external view returns (address);
  function safeTransferFrom(address from, address to, uint256 tokenId) external;
  function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory data) external;
  function setApprovalForAll(address operator, bool approved) external;
  function supportsInterface(bytes4 _interfaceId) external view returns (bool);
  function tokenURI(uint256 id) external view returns (string memory);
  function transferFrom(address from, address to, uint256 tokenId) external;
  function deposit(address bridge, uint88 amount) external;
  function depositEth(address bridge) external payable;
  function getBridges(uint256 vault) external view returns (address[] memory);
  function getDethTotal(uint256 vault) external view returns (uint256);
  function withdraw(address bridge, uint88 dethAmount) external;
  function withdrawTapp(address bridge, uint88 dethAmount) external;
  function createBid(
        address asset, uint80 price, uint88 ercAmount, bool isMarketOrder, EtherscanDiamondImpl.OrderHint[] memory orderHintArray, uint16[] memory shortHintArray) external returns (uint88 ethFilled, uint88 ercAmountLeft);
  function createForcedBid(address sender, address asset, uint80 price, uint88 ercAmount, uint16[] memory shortHintArray) external pure returns (uint88 ethFilled, uint88 ercAmountLeft);
  function _cancelAsk(address asset, uint16 id) external;
  function _cancelShort(address asset, uint16 id) external;
  function createAsk(address asset, uint80 price, uint88 ercAmount, bool isMarketOrder, EtherscanDiamondImpl.OrderHint[] memory orderHintArray) external;
  function createLimitShort(
        address asset, uint80 price, uint88 ercAmount, EtherscanDiamondImpl.OrderHint[] memory orderHintArray, uint16[] memory shortHintArray, uint16 initialCR) external;
  function exitShort(address asset, uint8 id, uint88 buyBackAmount, uint80 price, uint16[] memory shortHintArray) external;
  function exitShortErcEscrowed(address asset, uint8 id, uint88 buyBackAmount) external;
  function exitShortWallet(address asset, uint8 id, uint88 buyBackAmount) external;
  function flagShort(address asset, address shorter, uint8 id, uint16 flaggerHint) external;
  function liquidate(address asset, address shorter, uint8 id, uint16[] memory shortHintArray) external returns (uint88 gasFee, uint88 ethFilled);
  function liquidateSecondary(address asset, EtherscanDiamondImpl.BatchLiquidation[] memory batches, uint88 liquidateAmount, bool isWallet) external;
  function admin() external view returns (address);
  function claimOwnership() external;
  function createBridge(address bridge, uint256 vault, uint16 withdrawalFee, uint8 unstakeFee) external;
  function createMarket(address asset, STypes.Asset memory a) external;
  function createVault(address deth, uint256 vault, MTypes.CreateVaultParams memory params) external;
  function owner() external view returns (address);
  function ownerCandidate() external view returns (address);
  function setCallerFeePct(address asset, uint8 value) external;
  function setDittoMatchedRate(uint256 vault, uint16 rewardRate) external;
  function setDittoShorterRate(uint256 vault, uint16 rewardRate) external;
  function setFirstLiquidationTime(address asset, uint8 value) external;
  function setForcedBidPriceBuffer(address asset, uint8 value) external;
  function setInitialCR(address asset, uint16 value) external;
  function setMinAskEth(address asset, uint8 value) external;
  function setMinBidEth(address asset, uint8 value) external;
  function setMinShortErc(address asset, uint16 value) external;
  function setMinimumCR(address asset, uint8 value) external;
  function setPrimaryLiquidationCR(address asset, uint16 value) external;
  function setResetLiquidationTime(address asset, uint8 value) external;
  function setSecondLiquidationTime(address asset, uint8 value) external;
  function setSecondaryLiquidationCR(address asset, uint16 value) external;
  function setTappFeePct(address asset, uint8 value) external;
  function setTithe(uint256 vault, uint16 dethTithePercent) external;
  function setWithdrawalFee(address bridge, uint16 withdrawalFee) external;
  function transferAdminship(address newAdmin) external;
  function transferOwnership(address newOwner) external;
  function claimDittoMatchedReward(uint256 vault) external;
  function distributeYield(address[] memory assets) external;
  function updateYield(uint256 vault) external;
  function withdrawDittoReward(uint256 vault) external;
  function getAskHintId(address asset, uint256 price) external view returns (uint16 hintId);
  function getAsks(address asset) external view returns (EtherscanDiamondImpl.Order[] memory);
  function getAssetBalance(address asset, address user) external view returns (uint256);
  function getAssetCollateralRatio(address asset) external view returns (uint256 cRatio);
  function getAssetStruct(address asset) external view returns (STypes.Asset memory);
  function getAssetUserStruct(address asset, address user) external view returns (EtherscanDiamondImpl.AssetUser memory);
  function getBidHintId(address asset, uint256 price) external view returns (uint16 hintId);
  function getBids(address asset) external view returns (EtherscanDiamondImpl.Order[] memory);
  function getBridgeStruct(address bridge) external view returns (EtherscanDiamondImpl.Bridge memory);
  function getBridgeVault(address bridge) external view returns (uint256);
  function getCollateralRatio(address asset, EtherscanDiamondImpl.ShortRecord memory short) external view returns (uint256 cRatio);
  function getCollateralRatioSpotPrice(address asset, EtherscanDiamondImpl.ShortRecord memory short) external view returns (uint256 cRatio);
  function getDethBalance(uint256 vault, address user) external view returns (uint256);
  function getDethYieldRate(uint256 vault) external view returns (uint256);
  function getDittoMatchedReward(uint256 vault, address user) external view returns (uint256);
  function getDittoReward(uint256 vault, address user) external view returns (uint256);
  function getFlaggerHint() external view returns (uint24 flaggerId);
  function getFlaggerId(address asset, address user) external view returns (uint24 flaggerId);
  function getHintArray(address asset, uint256 price, uint8 orderType, uint256 numHints) external view returns (EtherscanDiamondImpl.OrderHint[] memory orderHintArray);
  function getOffsetTime() external view returns (uint256);
  function getOracleAssetPrice(address asset) external view returns (uint256);
  function getProtocolAssetPrice(address asset) external view returns (uint256);
  function getProtocolAssetTime(address asset) external view returns (uint256);
  function getShortHintId(address asset, uint256 price) external view returns (uint16);
  function getShortIdAtOracle(address asset) external view returns (uint16 shortHintId);
  function getShortRecord(address asset, address shorter, uint8 id) external view returns (EtherscanDiamondImpl.ShortRecord memory shortRecord);
  function getShortRecordCount(address asset, address shorter) external view returns (uint256 shortRecordCount);
  function getShortRecords(address asset, address shorter) external view returns (EtherscanDiamondImpl.ShortRecord[] memory shorts);
  function getShorts(address asset) external view returns (EtherscanDiamondImpl.Order[] memory);
  function getTithe(uint256 vault) external view returns (uint256);
  function getUndistributedYield(uint256 vault) external view returns (uint256);
  function getVault(address asset) external view returns (uint256);
  function getVaultStruct(uint256 vault) external view returns (EtherscanDiamondImpl.Vault memory);
  function getVaultUserStruct(uint256 vault, address user) external view returns (EtherscanDiamondImpl.VaultUser memory);
  function getYield(address asset, address user) external view returns (uint256 shorterYield);
  function cancelAsk(address asset, uint16 id) external;
  function cancelBid(address asset, uint16 id) external;
  function cancelOrderFarFromOracle(address asset, uint8 orderType, uint16 lastOrderId, uint16 numOrdersToCancel) external;
  function cancelShort(address asset, uint16 id) external;
  function redeemErc(address asset, uint88 amtWallet, uint88 amtEscrow) external;
  function shutdownMarket(address asset) external;
  function estimateWETHInUSDC(uint128 amountIn, uint32 secondsAgo) external view returns (uint256 amountOut);
}