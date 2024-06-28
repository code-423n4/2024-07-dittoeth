// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;



interface IyDUSD {

  // functions from node_modules/@openzeppelin/contracts/token/ERC20/ERC20.sol
  function name() external view returns (string memory);
  function symbol() external view returns (string memory);
  function decimals() external view returns (uint8);
  function totalSupply() external view returns (uint256);
  function balanceOf(address account) external view returns (uint256);
  function transfer(address to, uint256 amount) external returns (bool);
  function allowance(address owner, address spender) external view returns (uint256);
  function approve(address spender, uint256 amount) external returns (bool);
  function transferFrom(address from, address to, uint256 amount) external returns (bool);
  function increaseAllowance(address spender, uint256 addedValue) external returns (bool);
  function decreaseAllowance(address spender, uint256 subtractedValue) external returns (bool);

  // functions from node_modules/@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol
  function asset() external view returns (address);
  function totalAssets() external view returns (uint256);
  function convertToShares(uint256 assets) external view returns (uint256);
  function convertToAssets(uint256 shares) external view returns (uint256);
  function maxDeposit(address) external view returns (uint256);
  function maxMint(address) external view returns (uint256);
  function maxWithdraw(address owner) external view returns (uint256);
  function maxRedeem(address owner) external view returns (uint256);
  function previewDeposit(uint256 assets) external view returns (uint256);
  function previewMint(uint256 shares) external view returns (uint256);
  function previewWithdraw(uint256 assets) external view returns (uint256);
  function previewRedeem(uint256 shares) external view returns (uint256);
  function deposit(uint256 assets, address receiver) external returns (uint256);
  function mint(uint256 shares, address receiver) external returns (uint256);
  function withdraw(uint256 assets, address receiver, address owner) external returns (uint256);
  function redeem(uint256 shares, address receiver, address owner) external returns (uint256);

  // functions from contracts/tokens/yDUSD.sol
  function proposeWithdraw(uint104 amountProposed) external;
  function cancelWithdrawProposal() external;
  function getTimeProposed(address account) external view returns (uint40);
  function getAmountProposed(address account) external view returns (uint104);
}