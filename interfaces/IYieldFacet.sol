// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;



interface IYieldFacet {

  // functions from contracts/facets/YieldFacet.sol
  function updateYield(uint256 vault) external;
  function _updateYieldDiamond(uint256 vault) external;
  function distributeYield(address[] calldata assets) external;
  function claimDittoMatchedReward(uint256 vault) external;
  function withdrawDittoReward(uint256 vault) external;
}