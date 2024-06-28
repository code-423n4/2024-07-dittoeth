// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;



interface IAskOrdersFacet {

  // functions from contracts/facets/AskOrdersFacet.sol
  function createAsk(
        address asset, uint80 price, uint88 ercAmount, bool isMarketOrder, MTypes.OrderHint[] calldata orderHintArray) external;
  function _cancelAsk(address asset, uint16 id) external;
  function _cancelShort(address asset, uint16 id) external;
}