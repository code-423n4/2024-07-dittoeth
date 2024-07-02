// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;



interface IExitShortFacet {

  // functions from contracts/facets/ExitShortFacet.sol
  function exitShortWallet(address asset, uint8 id, uint88 buybackAmount, uint16 shortOrderId) external;
  function exitShortErcEscrowed(address asset, uint8 id, uint88 buybackAmount, uint16 shortOrderId) external;
  function exitShort(
        address asset, uint8 id, uint88 buybackAmount, uint80 price, uint16[] memory shortHintArray, uint16 shortOrderId) external;
}