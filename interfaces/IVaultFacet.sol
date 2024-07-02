// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;



interface IVaultFacet {

  // functions from contracts/facets/VaultFacet.sol
  function depositAsset(address asset, uint104 amount) external;
  function withdrawAsset(address asset, uint104 amount) external;
}