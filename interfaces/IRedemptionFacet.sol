// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;



interface IRedemptionFacet {

  // functions from contracts/facets/RedemptionFacet.sol
  function proposeRedemption(
        address asset, MTypes.ProposalInput[] calldata proposalInput, uint88 redemptionAmount, uint88 maxRedemptionFee) external;
  function disputeRedemption(address asset, address redeemer, uint8 incorrectIndex, address disputeShorter, uint8 disputeShortId) external;
  function claimRedemption(address asset) external;
  function claimRemainingCollateral(address asset, address redeemer, uint8 claimIndex, uint8 id) external;
}