// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;



interface IClaimRedemptionFacet {

  // functions from contracts/facets/ClaimRedemptionFacet.sol
  function claimRedemption(address asset) external;
  function claimRemainingCollateral(address asset, address redeemer, uint8 claimIndex, uint8 id) external;
}