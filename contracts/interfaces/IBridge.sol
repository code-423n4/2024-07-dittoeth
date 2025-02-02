// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

interface IBridge {
    error NotDiamond();
    error NetBalanceZero();

    function getBaseCollateral() external view returns (address);
    function getDethValue() external view returns (uint256);
    function getUnitDethValue() external view returns (uint256);
    function deposit(address, uint256) external returns (uint256);
    function depositEth() external payable returns (uint256);
    function withdraw(address, uint256) external returns (uint256);
}
