// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;


import {STypes,MTypes,SR} from "contracts/libraries/DataTypes.sol";

interface IOwnerFacet {

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
}