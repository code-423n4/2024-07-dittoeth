// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;



interface IBridgeRouterFacet {

  // functions from contracts/facets/BridgeRouterFacet.sol
  function getDethTotal(uint256 vault) external view returns (uint256);
  function getBridges(uint256 vault) external view returns (address[] memory);
  function deposit(address bridge, uint88 amount) external;
  function depositEth(address bridge) external payable;
  function withdraw(address bridge, uint88 dethAmount) external;
  function withdrawTapp(address bridge, uint88 dethAmount) external;
}