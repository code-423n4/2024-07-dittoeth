// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;



interface IViewRedemptionFacet {

  // functions from contracts/facets/ViewRedemptionFacet.sol
  function getTimeToDispute(uint256 lastCR) external view returns (uint32 timeToDispute);
  function getRedemptionFee(address asset, uint88 ercDebtRedeemed, uint88 colRedeemed) external view returns (uint88 redemptionFee);
  function readProposalData(address asset, address redeemer) external view returns (uint32, uint32, uint80, uint80, MTypes.ProposalData[] memory);
}