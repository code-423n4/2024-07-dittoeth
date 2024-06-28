// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;



interface IProposeRedemptionFacet {

  // functions from contracts/facets/ProposeRedemptionFacet.sol
  function proposeRedemption(
        address asset, MTypes.ProposalInput[] calldata proposalInput, uint88 redemptionAmount, uint88 maxRedemptionFee, uint256 deadline) external;
}