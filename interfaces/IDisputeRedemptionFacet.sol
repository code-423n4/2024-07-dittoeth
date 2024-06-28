// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;



interface IDisputeRedemptionFacet {

  // functions from contracts/facets/DisputeRedemptionFacet.sol
  function disputeRedemption(address asset, address redeemer, uint8 incorrectIndex, address disputeShorter, uint8 disputeShortId) external;
}