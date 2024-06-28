// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;



interface ISecondaryLiquidationFacet {

  // functions from contracts/facets/SecondaryLiquidationFacet.sol
  function liquidateSecondary(address asset, MTypes.BatchLiquidation[] memory batches, uint88 liquidateAmount, bool isWallet) external;
}