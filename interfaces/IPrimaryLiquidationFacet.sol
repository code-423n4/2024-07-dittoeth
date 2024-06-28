// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;



interface IPrimaryLiquidationFacet {

  // functions from contracts/facets/PrimaryLiquidationFacet.sol
  function liquidate(address asset, address shorter, uint8 id, uint16[] memory shortHintArray, uint16 shortOrderId) external returns (uint88, uint88);
}