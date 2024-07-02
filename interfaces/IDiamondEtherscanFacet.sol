// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;



interface IDiamondEtherscanFacet {

  // functions from contracts/facets/DiamondEtherscanFacet.sol
  function setDummyImplementation(address _implementation) external;
  function implementation() external view returns (address);
}