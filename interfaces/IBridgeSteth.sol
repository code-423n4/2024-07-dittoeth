// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;



interface IBridgeSteth {

  // functions from contracts/bridges/BridgeSteth.sol
  function getBaseCollateral() external view returns (address);
  function getDethValue() external view returns (uint256);
  function getUnitDethValue() external view returns (uint256);
  function deposit(address from, uint256 amount) external returns (uint256);
  function depositEth() external payable returns (uint256);
  function withdraw(address to, uint256 amount) external returns (uint256);
}