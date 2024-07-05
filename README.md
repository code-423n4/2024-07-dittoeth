# DittoEth audit details
- Total Prize Pool: $13,600 in USDC
  - HM awards: $11000 in USDC*
  - Judge awards: $2100 in USDC
  - Scout awards: $500 USDC
- Join [C4 Discord](https://discord.gg/code4rena) to register
- Submit findings [using the C4 form](https://code4rena.com/contests/2024-07-dittoeth/submit)
- [Read our guidelines for more details](https://docs.code4rena.com/roles/wardens)
- Starts July 2, 2024 20:00 UTC
- Ends July 8, 2024 20:00 UTC

*❗️Note: This audit has $0 in QA awards. However, if no valid HM findings are found, the HM awards will be $0, and the top 3 QA reports will split a QA award of $440 in USDC.

## This is a Private audit

This audit repo and its Discord channel are accessible to **certified wardens only.** Participation in private audits is bound by:

1. Code4rena's [Certified Contributor Terms and Conditions](https://github.com/code-423n4/code423n4.com/blob/main/_data/pages/certified-contributor-terms-and-conditions.md)
2. Code4rena's [Certified Contributor Code of Professional Conduct](https://code4rena.notion.site/Code-of-Professional-Conduct-657c7d80d34045f19eee510ae06fef55)

*All discussions regarding private audits should be considered private and confidential, unless otherwise indicated.*


## Automated Findings / Publicly Known Issues

The 4naly3er report can be found [here](https://github.com/code-423n4/2024-07-dittoeth/blob/main/4naly3er-report.md).



_Note for C4 wardens: Anything included in this `Automated Findings / Publicly Known Issues` section is considered a publicly known issue and is ineligible for awards._
# Previous audit known issues

- Issues related to the start/bootstrap of the protocol
  - When there are few ShortRecords or TAPP is low, it's easy to fall into a black swan scenario
  - Ditto rewards: first claimer gets 100% of ditto reward, also `dittoShorterRate` can give more/less ditto than expected (see [L-21](https://www.codehawks.com/report/clm871gl00001mp081mzjdlwc#L-21)).
  - Empty order book can lead to different kinds of issues. Just as one example, matching self can get ditto rewards/yield. Creating a low bid (see [L-16](https://www.codehawks.com/report/clm871gl00001mp081mzjdlwc#L-16)) isn't likely since anyone would want to simply match against it. Creating a high short that eventually matches seems impossible with real orders. Can also prevent creating an order too far away from the oracle.
- Don't worry about front-running
- Not finished with governance/token setup
- Issues related to oracles
  - Oracle is very dependent on Chainlink, stale/invalid prices fallback to a Uniswap TWAP. 2 hours staleness means it can be somewhat out of date.
- Bridge credit system (for LST arb, since rETH/stETH is mixed)
  - If user has LST credit but that bridge is empty, LST credit can be redeemed for the other base collateral at 1-1 ratio
  - In NFT transfer, LST credit is transferred up to the amount of the collateral in the ShortRecord, which includes collateral that comes from bidder, might introduce a fee on minting a NFT
  - Thus, credits don't prevent arbitrage from either yield profits or trading: credit is only tracked on deposits/withdraw and not at the more granular level of matching trades or how much credit is given for yield from LSTs.
- There is an edge case where a Short meets `minShortErc` requirements because of `ercDebtRate` application
- `disburseCollateral` in `proposeRedemption()` can cause user to lose yield if their SR was recently modified and it’s still below 2.0 CR (modified through order fill, or increase collateral) - this is only `YIELD_DELAY_SECONDS` which is currently 60s
- Recovery Mode: currently not checking `recoveryCR` in secondary liquidation unlike primary, may introduce later.
- Incentives should mitigate actions from bad/lazy actors and promote correct behavior, but they do not guarantee perfect behavior:
  - That Primary Liquidations happen
  - Redemptions in the exact sorted order
- Redemptions
  - Proposals are intentionally overly conservative in considering an SR to ineligible (with regards to `minShortErc`) to prevent scenarios of ercDebt under `minShortErc`
  - ~~There is an issue when `claimRemainingCollateral()` is called on a SR that is included in a proposal and is later correctly disputed.~~ **Fixed**
  - ~~Undecided on how to distribute the redemption fee, maybe to dusd holders rather than just the system.~~ Redemption fee goes to the TAPP
  - ~~Currently allowed to redeem at any CR under 2, even under 1 CR.~~ Cannot redeem under 1 CR

## Added known issues
- In the case of collateral efficient SR, protocol can be overly conservative with checkShortMinErc for partial liquidations in reverting (Not worried bc the liquidator can just supply the asks needed to reach full liquidation)
- Is possible to have SR with CR higher than max at small amounts, ie. collateral efficient SR with ethInitial and small partial match
- If you don’t dispute before proposing, can get disputed yourself since dispute doesn’t change updatedAt
- new: ERC4626 Vault (yDUSD.sol)
  - ~~the vault contract is currently immutable, but before deployment will either be a proxy or diamond, or incorporate a way to modify the values~~ (Fixed: added an address mapping to be able to swap vaults and let people migrate over if there is a need to update the contract in the future)
- Introduced `ercDebtFee` to allow the fee itself not to be compounded. Didn't cover every case but looking for feedback (handled in cases where ercDebt changes: redemptions, liquidations, black swan socialization, exit short, combine). ~~Found an issue with modifying the ercDebt/updateErcDebt, regarding discountFees/socializing debt from blackswan.~~ Fixed: tried to account for socialized debt as well.

# Overview
### About Ditto

The Ditto protocol is a new decentralized stable asset protocol for Ethereum mainnet. It takes in overcollateralized liquid staked ETH (rETH, stETH) to create stablecoins using a gas optimized orderbook (starting with a USD stablecoin, dUSD).

On the orderbook, bidders and shorters bring ETH, askers can sell their dUSD. Bidders get the dUSD, shorters get the bidders collateral and a ShortRecord to manage their debt position (similar to a CDP). Shorters get the collateral of the position (and thus the LST yield), with the bidder getting the stable asset, rather than a CDP where the user also gets the asset.

## Links

- **Previous audits:**  https://code4rena.com/reports/2024-03-dittoeth
- **Documentation:** https://dittoeth.com/
- **Website:** https://dittoeth.com
- **X/Twitter:** https://twitter.com/dittoproj

---

# Scope
Please check the `diff` to see the changes from the previous audit [here](https://github.com/code-423n4/2024-07-dittoeth/commit/4ab7d3aaf57de83806e6b818210d7675c2367ecd#diff-163ce8529ee32196d5cfc3342d88a72cb481071443732525277b65ddf6132727)
### Files in scope

| Contract                                                                                                                                        | SLOC | Purpose                                        |
|:----------------------------------------------------------------------------------------------------------------------------------------------- |:---- |:---------------------------------------------- |
| [tokens/yDUSD.sol](https://github.com/code-423n4/2024-07-dittoeth/blob/main/contracts/tokens/yDUSD.sol)                                         | 90   | the ERC4626 Vault that the DUSD gets minted to |
| [libraries/LibRedemption.sol](https://github.com/code-423n4/2024-07-dittoeth/blob/main/contracts/libraries/LibRedemption.sol)                   | 58   | helper library for Redemptions                 |
| [libraries/LibPriceDiscount.sol](https://github.com/code-423n4/2024-07-dittoeth/blob/main/contracts/libraries/LibPriceDiscount.sol)             | 38   | helper library for price discount              |
| [libraries/LibOrders.sol](https://github.com/code-423n4/2024-07-dittoeth/blob/main/contracts/libraries/LibOrders.sol)                           | 578  | helper library for price discount              |
| [libraries/LibVault.sol](https://github.com/code-423n4/2024-07-dittoeth/blob/main/contracts/libraries/LibVault.sol)                             | 60   |                                                |
| [libraries/LibShortRecord.sol](https://github.com/code-423n4/2024-07-dittoeth/blob/main/contracts/libraries/LibShortRecord.sol)                 | 134  |                                                |
| [libraries/LibSRUtil.sol](https://github.com/code-423n4/2024-07-dittoeth/blob/main/contracts/libraries/LibSRUtil.sol)                           | 100  |                                                |
| [libraries/LibOracle.sol](https://github.com/code-423n4/2024-07-dittoeth/blob/main/contracts/libraries/LibOracle.sol)                           | 122  |                                                |
| [libraries/LibBytes.sol](https://github.com/code-423n4/2024-07-dittoeth/blob/main/contracts/libraries/LibBytes.sol)                             | 51   |                                                |
| [libraries/LibAsset.sol](https://github.com/code-423n4/2024-07-dittoeth/blob/main/contracts/libraries/LibAsset.sol)                             | 63   |                                                |
| [libraries/DataTypes.sol](https://github.com/code-423n4/2024-07-dittoeth/blob/main/contracts/libraries/DataTypes.sol)                           | 273  |                                                |
| [facets/OwnerFacet.sol](https://github.com/code-423n4/2024-07-dittoeth/blob/main/contracts/facets/OwnerFacet.sol)                               | 238  |                                                |
| [facets/BridgeRouterFacet.sol](https://github.com/code-423n4/2024-07-dittoeth/blob/main/contracts/facets/BridgeRouterFacet.sol)                 | 101  |                                                |
| [facets/YieldFacet.sol](https://github.com/code-423n4/2024-07-dittoeth/blob/main/contracts/facets/YieldFacet.sol)                               | 116  |                                                |
| [facets/ShortRecordFacet.sol](https://github.com/code-423n4/2024-07-dittoeth/blob/main/contracts/facets/ShortRecordFacet.sol)                   | 94   |                                                |
| [facets/ShortOrdersFacet.sol](https://github.com/code-423n4/2024-07-dittoeth/blob/main/contracts/facets/ShortOrdersFacet.sol)                   | 56   |                                                |
| [facets/SecondaryLiquidationFacet.sol](https://github.com/code-423n4/2024-07-dittoeth/blob/main/contracts/facets/SecondaryLiquidationFacet.sol) | 117  |                                                |
| [facets/PrimaryLiquidationFacet.sol](https://github.com/code-423n4/2024-07-dittoeth/blob/main/contracts/facets/PrimaryLiquidationFacet.sol)     | 184  |                                                |
| [facets/ProposeRedemptionFacet.sol](https://github.com/code-423n4/2024-07-dittoeth/blob/main/contracts/facets/ProposeRedemptionFacet.sol)       | 110  |                                                |
| [facets/DisputeRedemptionFacet.sol](https://github.com/code-423n4/2024-07-dittoeth/blob/main/contracts/facets/DisputeRedemptionFacet.sol)       | 117  |                                                |
| [facets/ClaimRedemptionFacet.sol](https://github.com/code-423n4/2024-07-dittoeth/blob/main/contracts/facets/ClaimRedemptionFacet.sol)           | 64   |                                                |
| [facets/OrdersFacet.sol](https://github.com/code-423n4/2024-07-dittoeth/blob/main/contracts/facets/OrdersFacet.sol)                             | 117  |                                                |
| [facets/MarketShutdownFacet.sol](https://github.com/code-423n4/2024-07-dittoeth/blob/main/contracts/facets/MarketShutdownFacet.sol)             | 49   |                                                |
| [facets/ExitShortFacet.sol](https://github.com/code-423n4/2024-07-dittoeth/blob/main/contracts/facets/ExitShortFacet.sol)                       | 136  |                                                |
| [facets/BidOrdersFacet.sol](https://github.com/code-423n4/2024-07-dittoeth/blob/main/contracts/facets/BidOrdersFacet.sol)                       | 227  |                                                |
| TOTAL                                                                                                                                           | 3293 |                                                |

### Files out of scope
All files not listed above are Out Of Scope

## Scoping Q &amp; A

### General questions

| Question                                | Answer                       |
| --------------------------------------- | ---------------------------- |
| ERC20 used by the protocol              |       Protocol tokens: Asset.sol (DUSD, DETH, Ditto), LSTs: stETH/rETH             |
| Test coverage                           | Lines: 74.33%, Functions: 57.35%                          |
| ERC721 used  by the protocol            |           Protocol token: NFT as part of the Diamond, represents a ShortRecord position              |
| ERC777 used by the protocol             |          None                |
| ERC1155 used by the protocol            |              None            |
| Chains the protocol will be deployed on | Ethereum |

### ERC20 token behaviors in scope

| Question                                                                                                                                                   | Answer |
| ---------------------------------------------------------------------------------------------------------------------------------------------------------- | ------ |
| [Missing return values](https://github.com/d-xo/weird-erc20?tab=readme-ov-file#missing-return-values)                                                      |   No  |
| [Fee on transfer](https://github.com/d-xo/weird-erc20?tab=readme-ov-file#fee-on-transfer)                                                                  |  No  |
| [Balance changes outside of transfers](https://github.com/d-xo/weird-erc20?tab=readme-ov-file#balance-modifications-outside-of-transfers-rebasingairdrops) | No    |
| [Upgradeability](https://github.com/d-xo/weird-erc20?tab=readme-ov-file#upgradable-tokens)                                                                 |   No  |
| [Flash minting](https://github.com/d-xo/weird-erc20?tab=readme-ov-file#flash-mintable-tokens)                                                              | No    |
| [Pausability](https://github.com/d-xo/weird-erc20?tab=readme-ov-file#pausable-tokens)                                                                      | No    |
| [Approval race protections](https://github.com/d-xo/weird-erc20?tab=readme-ov-file#approval-race-protections)                                              | No    |
| [Revert on approval to zero address](https://github.com/d-xo/weird-erc20?tab=readme-ov-file#revert-on-approval-to-zero-address)                            | No    |
| [Revert on zero value approvals](https://github.com/d-xo/weird-erc20?tab=readme-ov-file#revert-on-zero-value-approvals)                                    | No    |
| [Revert on zero value transfers](https://github.com/d-xo/weird-erc20?tab=readme-ov-file#revert-on-zero-value-transfers)                                    | No    |
| [Revert on transfer to the zero address](https://github.com/d-xo/weird-erc20?tab=readme-ov-file#revert-on-transfer-to-the-zero-address)                    | No    |
| [Revert on large approvals and/or transfers](https://github.com/d-xo/weird-erc20?tab=readme-ov-file#revert-on-large-approvals--transfers)                  | No    |
| [Doesn't revert on failure](https://github.com/d-xo/weird-erc20?tab=readme-ov-file#no-revert-on-failure)                                                   |  No   |
| [Multiple token addresses](https://github.com/d-xo/weird-erc20?tab=readme-ov-file#revert-on-zero-value-transfers)                                          | No    |
| [Low decimals ( < 6)](https://github.com/d-xo/weird-erc20?tab=readme-ov-file#low-decimals)                                                                 |   No  |
| [High decimals ( > 18)](https://github.com/d-xo/weird-erc20?tab=readme-ov-file#high-decimals)                                                              | No    |
| [Blocklists](https://github.com/d-xo/weird-erc20?tab=readme-ov-file#tokens-with-blocklists)                                                                | No    |

### External integrations (e.g., Uniswap) behavior in scope:


| Question                                                  | Answer |
| --------------------------------------------------------- | ------ |
| Enabling/disabling fees (e.g. Blur disables/enables fees) | No   |
| Pausability (e.g. Uniswap pool gets paused)               |  No   |
| Upgradeability (e.g. Uniswap gets upgraded)               |   No  |


### EIP compliance checklist
None


# Additional context

## Main invariants

## Orderbook

- Ditto's orderbook acts similar to central limit orderbook with some changes. In order to make the gas costs low, there is a hint system added to enable a user to place an order in the orderbook mapping. Asks/Shorts are both on the "sell" side of the orderbook. Order structs are reused by implementing the orders as a doubly linked-list in a mapping. HEAD order is used as a starting point to match against.

- Ask orders get matched before short orders at the same price.
Bids sorted high to low
Asks/Shorts sorted low to high
Only cancelled/matched orders can be reused (Technically: Left of HEAD (HEAD.prevId) these are the only possible OrderTypes: O.Matched, O.Cancelled, O.Uninitialized).
Since bids/asks/shorts share the same orderId counter, every single orderId should be unique

## Short Orders

- shortOrders can only be limit orders. startingShort represents the first short order that can be matched. Normally HEAD.nextId would the next short order in the mapping, but it's not guaranteed that it is matchable since users can still create limit shorts under the oracle price (or they move below oracle once the price updates). Oracle updates from chainlink or elsewhere will cause the startingShort to move, which means the system doesn't know when to start matching from without looping through each short, so the system allows a temporary matching backwards.

- shortOrder can't match under oraclePrice
startingShort price must be greater than or equal to oraclePrice
shortOrder with a non-zero (ie. positive) shortRecordId means that the referenced SR is status partialFill

## ShortRecords

- ShortRecords are the Vaults/CDPs/Troves of Ditto. SRs represent a collateral/debt position by a shorter. Each user can have multiple SRs, which are stored under their address as a list.

- The only time shortRecord debt can be below minShortErc is when it's partially filled and the connected shortOrder has enough ercDebt to make up the difference to minShortErc (Technically: SR.status == PartialFill && shortOrder.ercAmount + ercDebt >= minShortErc)
Similarly, SR can never be SR.FullyFilled and be under minShortErc
FullyFilled SR can never have 0 collateral
Only SR with status Closed can ever be re-used (Technically, only SR.Closed on the left (prevId) side of HEAD, with the exception of HEAD itself)

## Redemptions

- Allows dUSD holders to get equivalent amount of ETH back, akin to Liquity. However the system doesn't automatically sort the SR's lowest to highest. Instead, users propose a list of SRs (an immutable slate) to redeem against. There is a dispute period to revert any proposal changes and a corresponding penalty against a proposer if incorrect. Proposers can claim the ETH after the time period, and shorters can also claim any remaining collateral afterwards.

- Proposal "slates" are sorted least to highest CR
All CR in proposedData dataTypes should be under 2 CR, above 1 CR
If proposal happens, check to see that there is no issues with SSTORE2 (the way it is saved and read)
Relationship between proposal and SR's current collateral and ercDebt amounts. The sum total should always add up to the original amounts (save those amounts)
SR can be SR.Closed before claim if closed another way (like liquidation)
SR can be partially redeemed in non-last position only if it gets refilled after a full proposal

## BridgeRouter/Bridge

- Because the Vault mixes rETH/stETH, a credit system is introduced to allow users to withdraw only what they deposit, anything in excess (due to yield) also checks either LSTs price difference using a TWAP via Uniswap.

- deposit/withdraw gives/removes an appropriate amount of virtual dETH (ETH equivalent), no matter if someone deposits an LST (rETH, stETH), or ETH and accounts for yield that is gained over time.

## Misc

- NFT can only be SR.FullyFilled
TAPP SR is never moved to the left of HEAD, even when closed bc of full liquidation
All deleted SR have collateral = 0, unless pointing to shortOrder
User should never be able to force SR under initialCR (excluding oracle price change)
Collateral Efficient SR being redeemed always has enough ETH

## Change Log 
- This changelog section is of what has occured since [code-423n4/2024-03-dittoeth](https://github.com/code-423n4/2024-03-dittoeth). Other than the [report](https://code4rena.com/reports/2024-03-dittoeth) this should helpful to get a sense of the changes. It's 2 "features" and otherwise fixes and refactoring.

- This encompasses last commit before audit 3/14/24-to now (6/28/24). Diff with previous code and the existing one can be found [here](https://github.com/code-423n4/2024-07-dittoeth/commit/4ab7d3aaf57de83806e6b818210d7675c2367ecd#diff-163ce8529ee32196d5cfc3342d88a72cb481071443732525277b65ddf6132727). It still might be a bit messy due to version changes and renames.

##### Features
- Apply a fee (increase ercDebt) to ShortRecords when trades are happening at a discount. Basic scenario is that ETH goes up, dUSD holders start to sell at a discount, increased fee or potential fee causes some shorts to exit to buy the discounted usd. Doesn't happen if assetCR < recoveryCR, or if forcedBid. Mints the extra fee/debt to the another vault contract (described below).
- Create a vault (erc4626) that allows depositing `dUSD` for `yDUSD` which can be withdrawn in the future for more `dUSD` based on the minted `dUSD` created from the fees from a discounted price. Different from standard as it doesn't allow withdrawal at any time. Must `proposeWithdraw` then `withdraw`, and it must be during a certain time period (after 7 days, before 45 days). Can also `cancelWithdrawProposal`. Also prevents withdrawal if system is currently in a discount.

##### Bug Fixes
- Allow `depositAsset` during market shutdown (frozen asset)
- Assembly: `add` should be `and`
- Disputing a `Closed` SR (exited) gives everything to the TAPP (the proposer already got their collateral, and the shorter already exited, so they would get 1:1 and it's safer to give to the TAPP). If disputing a non `Closed` SR, it causes the `merge` helper correctly. Also splits the RedemptionFacet into 3 to get around contract size limits.
- Call `getSavedOrSpotOraclePrice` instead of `getPrice` in `ProposeRedemption.sol` to avoid outdated price
- When short order is cancelled because of dust, the SR status wasn't set to `FullyFilled`, made it seem like there was an attached short order when there wasn't (causes an issue when the order is re-used)
- Users can dispute multiple times in the same proposal to maximize rewards (as opposed to just finding an incorrect proposal): prevent this by only allowing the lowest CR to be able to be disputable
- Various issues with not updating an SR's `updatedAt` timestamp (example: decrease collateral in a SR to dispute)
- `shortOrderId` wasn't validated correctly for proposeRedemption/liquidateSecondary: create a helper for this check in various places
- Incorrect validation: used `&&` instead of `||`
- Prevent combining SR if resulting SR is undercollateralized (low risk since an issue more around front-running redemption/liquidation)
- Lockdown TAPP by preventing sending it an NFT, and also special logic when deleting the TAPP SR after liquidation to prevent re-using ids
- Extra validation for `transferShortRecord` for `short.tokenId` and input `tokenId`
- Fix issue with partial NFT transfers cancelling orders, by not allowing partial NFT transfers at all
- Fix: update the SR's `ercDebt` before disputing
- Issues around user disputing own proposal (could evade a liquidation), introduce a fee that is given to the TAPP to disincentivize this
- Fix issues around redemptions that are under 1 CR. A redeemer wouldn't get 1:1 collateral back so prevent both proposing and disputing a SR under 1 CR and ask users to primary liquidate (also they get a fee).
- Fix issue with dispute time where it wasn't actually the last valid CR
- Make sure tithe doesn't go over 100%
- Fix potential out of gas issue with short order hints (find hint from `startingShortId` vs `HEAD`)
- Fix issue with capital efficient short record creation by forcing user to add extra collateral to the SR to cover `minShortErc`
- Fix issues with NFT ids (multiple NFTs pointing to same SR id), don't re-use ids.
- Fix issues with a capital efficient CDP by adding more checks by initial eth when lower collateralization
- Add staleness check to non base oracle
- Prevent liquidation from matching with own short order
- Fix to allow distributing yield when one of a shorter's SR has been fully redeemed already
- Fix to send redemptionFee to TAPP

##### Refactor
- Storing the reset of the Redemption parameters (`timeProposed`, `timeToDispute`, `oraclePrice`) in SSTORE2
- Solidity `0.8.25` (will update to 0.8.26 on deploy)
- Remove NFT of SR feature, make room for something else
- Make ercDebtRate u80 from u64
- Start using tstore/tload

## Attack ideas (where to focus for bugs)
- 2 new "features": ercDebt increase on price discount (when there's a match under oracle) + the ERC4626 vault that the ercDebt goes to.
- fixes from the last audit
- In general: redemptions feature, orderbook matching, dust amounts (minShortErc), liquidations at the right time.

## All trusted roles in the protocol


| Role                                | Description                       |
| --------------------------------------- | ---------------------------- |
| onlyDiamond                          | Asset can mint/burn with onlyDiamond               |
| onlyAdminOrDAO, onlyDAO                             | for OwnerFacet                       |

## Any novel or unique curve logic or mathematical models implemented in the contracts:

None

## Running tests
```bash
git clone --recurse https://github.com/code-423n4/2024-07-dittoeth.git
cd 2024-07-dittoeth
```
Use Bun to run TypeScript
```bash
curl -fsSL https://bun.sh/install | bash
bun install
```

Install Foundry for Solidity
```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

Set `.env` for tests
```bash
echo 'ANVIL_9_PRIVATE_KEY=0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6' >> .env
echo 'MAINNET_RPC_URL=https://eth.drpc.org' >> .env
```

Create interfaces (should already be committed into `interfaces/`, but usually in .gitignore)
```bash
bun run interfaces-force
```
Build
```bash
bun run build
```
Unit/fork/invariant tests
```bash
bun run test
```
Gas tests, check `/.gas.json`
```bash
bun run test-gas
```
To run code coverage
```bash
forge coverage
```

<pre>| File                                                                | % Lines            | % Statements       | % Branches        | % Funcs          |
|---------------------------------------------------------------------|--------------------|--------------------|-------------------|------------------|
| contracts/Diamond.sol                                               |<font color="#33DA7A"> 100.00% (24/24)    </font>|<font color="#33DA7A"> 100.00% (30/30)    </font>|<font color="#E9AD0C"> 66.67% (4/6)      </font>|<font color="#33DA7A"> 100.00% (2/2)    </font>|
| contracts/EtherscanDiamondImpl.sol                                  |<font color="#F66151"> 0.00% (0/31)       </font>|<font color="#F66151"> 0.00% (0/31)       </font>|<font color="#8B8A88"> 100.00% (0/0)     </font>|<font color="#F66151"> 0.00% (0/100)    </font>|
| contracts/bridges/BridgeReth.sol                                    |<font color="#33DA7A"> 100.00% (25/25)    </font>|<font color="#33DA7A"> 95.35% (41/43)     </font>|<font color="#E9AD0C"> 50.00% (2/4)      </font>|<font color="#33DA7A"> 100.00% (9/9)    </font>|
| contracts/bridges/BridgeSteth.sol                                   |<font color="#33DA7A"> 100.00% (17/17)    </font>|<font color="#33DA7A"> 92.00% (23/25)     </font>|<font color="#E9AD0C"> 50.00% (2/4)      </font>|<font color="#33DA7A"> 100.00% (8/8)    </font>|
| contracts/facets/AskOrdersFacet.sol                                 |<font color="#33DA7A"> 100.00% (12/12)    </font>|<font color="#33DA7A"> 100.00% (16/16)    </font>|<font color="#33DA7A"> 100.00% (4/4)     </font>|<font color="#33DA7A"> 100.00% (3/3)    </font>|
| contracts/facets/BidOrdersFacet.sol                                 |<font color="#33DA7A"> 100.00% (143/143)  </font>|<font color="#33DA7A"> 100.00% (182/182)  </font>|<font color="#33DA7A"> 91.94% (57/62)    </font>|<font color="#33DA7A"> 100.00% (8/8)    </font>|
| contracts/facets/BridgeRouterFacet.sol                              |<font color="#33DA7A"> 100.00% (53/53)    </font>|<font color="#33DA7A"> 100.00% (74/74)    </font>|<font color="#33DA7A"> 95.83% (23/24)    </font>|<font color="#33DA7A"> 100.00% (10/10)  </font>|
| contracts/facets/ClaimRedemptionFacet.sol                           |<font color="#33DA7A"> 100.00% (30/30)    </font>|<font color="#33DA7A"> 100.00% (45/45)    </font>|<font color="#33DA7A"> 100.00% (12/12)   </font>|<font color="#33DA7A"> 100.00% (3/3)    </font>|
| contracts/facets/DiamondCutFacet.sol                                |<font color="#33DA7A"> 100.00% (2/2)      </font>|<font color="#33DA7A"> 100.00% (2/2)      </font>|<font color="#8B8A88"> 100.00% (0/0)     </font>|<font color="#33DA7A"> 100.00% (1/1)    </font>|
| contracts/facets/DiamondEtherscanFacet.sol                          |<font color="#F66151"> 0.00% (0/3)        </font>|<font color="#F66151"> 0.00% (0/4)        </font>|<font color="#8B8A88"> 100.00% (0/0)     </font>|<font color="#F66151"> 0.00% (0/2)      </font>|
| contracts/facets/DiamondLoupeFacet.sol                              |<font color="#F66151"> 47.89% (34/71)     </font>|<font color="#F66151"> 46.94% (46/98)     </font>|<font color="#F66151"> 33.33% (6/18)     </font>|<font color="#E9AD0C"> 50.00% (2/4)     </font>|
| contracts/facets/DisputeRedemptionFacet.sol                         |<font color="#33DA7A"> 100.00% (56/56)    </font>|<font color="#33DA7A"> 100.00% (75/75)    </font>|<font color="#33DA7A"> 100.00% (22/22)   </font>|<font color="#33DA7A"> 100.00% (1/1)    </font>|
| contracts/facets/ExitShortFacet.sol                                 |<font color="#33DA7A"> 100.00% (77/77)    </font>|<font color="#33DA7A"> 100.00% (95/95)    </font>|<font color="#33DA7A"> 100.00% (22/22)   </font>|<font color="#33DA7A"> 100.00% (5/5)    </font>|
| contracts/facets/MarketShutdownFacet.sol                            |<font color="#33DA7A"> 100.00% (24/24)    </font>|<font color="#33DA7A"> 100.00% (31/31)    </font>|<font color="#33DA7A"> 100.00% (8/8)     </font>|<font color="#33DA7A"> 100.00% (2/2)    </font>|
| contracts/facets/OrdersFacet.sol                                    |<font color="#33DA7A"> 100.00% (69/69)    </font>|<font color="#33DA7A"> 100.00% (94/94)    </font>|<font color="#33DA7A"> 96.43% (27/28)    </font>|<font color="#33DA7A"> 100.00% (8/8)    </font>|
| contracts/facets/OwnerFacet.sol                                     |<font color="#33DA7A"> 98.52% (133/135)   </font>|<font color="#33DA7A"> 97.96% (144/147)   </font>|<font color="#33DA7A"> 93.94% (62/66)    </font>|<font color="#33DA7A"> 97.73% (43/44)   </font>|
| contracts/facets/PrimaryLiquidationFacet.sol                        |<font color="#33DA7A"> 100.00% (101/101)  </font>|<font color="#33DA7A"> 99.19% (122/123)   </font>|<font color="#33DA7A"> 96.15% (25/26)    </font>|<font color="#33DA7A"> 100.00% (8/8)    </font>|
| contracts/facets/ProposeRedemptionFacet.sol                         |<font color="#33DA7A"> 98.55% (68/69)     </font>|<font color="#33DA7A"> 99.00% (99/100)    </font>|<font color="#33DA7A"> 94.44% (34/36)    </font>|<font color="#33DA7A"> 100.00% (1/1)    </font>|
| contracts/facets/SecondaryLiquidationFacet.sol                      |<font color="#33DA7A"> 87.50% (63/72)     </font>|<font color="#33DA7A"> 87.36% (76/87)     </font>|<font color="#33DA7A"> 78.12% (25/32)    </font>|<font color="#E9AD0C"> 60.00% (3/5)     </font>|
| contracts/facets/ShortOrdersFacet.sol                               |<font color="#33DA7A"> 100.00% (34/34)    </font>|<font color="#33DA7A"> 100.00% (50/50)    </font>|<font color="#33DA7A"> 100.00% (16/16)   </font>|<font color="#33DA7A"> 100.00% (1/1)    </font>|
| contracts/facets/ShortRecordFacet.sol                               |<font color="#33DA7A"> 100.00% (55/55)    </font>|<font color="#33DA7A"> 100.00% (76/76)    </font>|<font color="#33DA7A"> 100.00% (20/20)   </font>|<font color="#33DA7A"> 100.00% (4/4)    </font>|
| contracts/facets/TWAPFacet.sol                                      |<font color="#33DA7A"> 100.00% (1/1)      </font>|<font color="#33DA7A"> 100.00% (2/2)      </font>|<font color="#8B8A88"> 100.00% (0/0)     </font>|<font color="#33DA7A"> 100.00% (1/1)    </font>|
| contracts/facets/TestFacet.sol                                      |<font color="#33DA7A"> 97.92% (94/96)     </font>|<font color="#33DA7A"> 97.46% (115/118)   </font>|<font color="#33DA7A"> 77.78% (14/18)    </font>|<font color="#33DA7A"> 95.35% (41/43)   </font>|
| contracts/facets/ThrowAwayFacet.sol                                 |<font color="#F66151"> 0.00% (0/1)        </font>|<font color="#F66151"> 0.00% (0/1)        </font>|<font color="#8B8A88"> 100.00% (0/0)     </font>|<font color="#F66151"> 0.00% (0/1)      </font>|
| contracts/facets/VaultFacet.sol                                     |<font color="#33DA7A"> 100.00% (9/9)      </font>|<font color="#33DA7A"> 100.00% (12/12)    </font>|<font color="#33DA7A"> 100.00% (6/6)     </font>|<font color="#33DA7A"> 100.00% (3/3)    </font>|
| contracts/facets/ViewFacet.sol                                      |<font color="#33DA7A"> 95.12% (117/123)   </font>|<font color="#33DA7A"> 96.00% (168/175)   </font>|<font color="#33DA7A"> 83.33% (30/36)    </font>|<font color="#33DA7A"> 94.87% (37/39)   </font>|
| contracts/facets/ViewRedemptionFacet.sol                            |<font color="#33DA7A"> 80.00% (4/5)       </font>|<font color="#33DA7A"> 77.78% (7/9)       </font>|<font color="#8B8A88"> 100.00% (0/0)     </font>|<font color="#E9AD0C"> 66.67% (2/3)     </font>|
| contracts/facets/YieldFacet.sol                                     |<font color="#33DA7A"> 97.06% (66/68)     </font>|<font color="#33DA7A"> 95.70% (89/93)     </font>|<font color="#33DA7A"> 88.89% (16/18)    </font>|<font color="#33DA7A"> 87.50% (7/8)     </font>|
| contracts/governance/DittoGovernor.sol                              |<font color="#F66151"> 0.00% (0/10)       </font>|<font color="#F66151"> 0.00% (0/19)       </font>|<font color="#8B8A88"> 100.00% (0/0)     </font>|<font color="#F66151"> 0.00% (0/11)     </font>|
| contracts/governance/DittoTimelockController.sol                    |<font color="#8B8A88"> 100.00% (0/0)      </font>|<font color="#8B8A88"> 100.00% (0/0)      </font>|<font color="#8B8A88"> 100.00% (0/0)     </font>|<font color="#F66151"> 0.00% (0/1)      </font>|
| contracts/libraries/AppStorage.sol                                  |<font color="#33DA7A"> 100.00% (11/11)    </font>|<font color="#33DA7A"> 100.00% (22/22)    </font>|<font color="#33DA7A"> 92.86% (13/14)    </font>|<font color="#33DA7A"> 100.00% (9/9)    </font>|
| contracts/libraries/LibAsset.sol                                    |<font color="#33DA7A"> 100.00% (24/24)    </font>|<font color="#33DA7A"> 100.00% (47/47)    </font>|<font color="#33DA7A"> 75.00% (3/4)      </font>|<font color="#33DA7A"> 100.00% (14/14)  </font>|
| contracts/libraries/LibBridge.sol                                   |<font color="#33DA7A"> 100.00% (2/2)      </font>|<font color="#33DA7A"> 100.00% (4/4)      </font>|<font color="#8B8A88"> 100.00% (0/0)     </font>|<font color="#33DA7A"> 100.00% (1/1)    </font>|
| contracts/libraries/LibBridgeRouter.sol                             |<font color="#33DA7A"> 98.41% (62/63)     </font>|<font color="#33DA7A"> 98.78% (81/82)     </font>|<font color="#33DA7A"> 100.00% (30/30)   </font>|<font color="#33DA7A"> 100.00% (4/4)    </font>|
| contracts/libraries/LibBytes.sol                                    |<font color="#33DA7A"> 100.00% (30/30)    </font>|<font color="#33DA7A"> 100.00% (37/37)    </font>|<font color="#E9AD0C"> 50.00% (1/2)      </font>|<font color="#33DA7A"> 100.00% (1/1)    </font>|
| contracts/libraries/LibDiamond.sol                                  |<font color="#33DA7A"> 86.73% (85/98)     </font>|<font color="#33DA7A"> 87.07% (101/116)   </font>|<font color="#E9AD0C"> 59.26% (32/54)    </font>|<font color="#33DA7A"> 100.00% (8/8)    </font>|
| contracts/libraries/LibDiamondEtherscan.sol                         |<font color="#F66151"> 0.00% (0/3)        </font>|<font color="#F66151"> 0.00% (0/3)        </font>|<font color="#8B8A88"> 100.00% (0/0)     </font>|<font color="#F66151"> 0.00% (0/2)      </font>|
| contracts/libraries/LibOracle.sol                                   |<font color="#33DA7A"> 100.00% (36/36)    </font>|<font color="#33DA7A"> 94.29% (66/70)     </font>|<font color="#E9AD0C"> 71.43% (10/14)    </font>|<font color="#33DA7A"> 100.00% (9/9)    </font>|
| contracts/libraries/LibOrders.sol                                   |<font color="#33DA7A"> 99.73% (376/377)   </font>|<font color="#33DA7A"> 99.80% (495/496)   </font>|<font color="#33DA7A"> 93.92% (139/148)  </font>|<font color="#33DA7A"> 100.00% (37/37)  </font>|
| contracts/libraries/LibPriceDiscount.sol                            |<font color="#33DA7A"> 100.00% (17/17)    </font>|<font color="#33DA7A"> 100.00% (23/23)    </font>|<font color="#33DA7A"> 87.50% (7/8)      </font>|<font color="#33DA7A"> 100.00% (1/1)    </font>|
| contracts/libraries/LibRedemption.sol                               |<font color="#33DA7A"> 100.00% (29/29)    </font>|<font color="#33DA7A"> 100.00% (44/44)    </font>|<font color="#33DA7A"> 100.00% (12/12)   </font>|<font color="#33DA7A"> 100.00% (4/4)    </font>|
| contracts/libraries/LibSRUtil.sol                                   |<font color="#33DA7A"> 100.00% (55/55)    </font>|<font color="#33DA7A"> 97.67% (84/86)     </font>|<font color="#33DA7A"> 94.12% (32/34)    </font>|<font color="#33DA7A"> 100.00% (9/9)    </font>|
| contracts/libraries/LibShortRecord.sol                              |<font color="#33DA7A"> 100.00% (84/84)    </font>|<font color="#33DA7A"> 100.00% (98/98)    </font>|<font color="#33DA7A"> 100.00% (26/26)   </font>|<font color="#33DA7A"> 100.00% (7/7)    </font>|
| contracts/libraries/LibTStore.sol                                   |<font color="#33DA7A"> 83.33% (5/6)       </font>|<font color="#33DA7A"> 85.71% (6/7)       </font>|<font color="#8B8A88"> 100.00% (0/0)     </font>|<font color="#33DA7A"> 75.00% (3/4)     </font>|
| contracts/libraries/LibVault.sol                                    |<font color="#33DA7A"> 100.00% (35/35)    </font>|<font color="#33DA7A"> 100.00% (51/51)    </font>|<font color="#33DA7A"> 100.00% (6/6)     </font>|<font color="#33DA7A"> 100.00% (5/5)    </font>|
| contracts/libraries/PRBMathHelper.sol                               |<font color="#E9AD0C"> 52.50% (42/80)     </font>|<font color="#F66151"> 45.00% (54/120)    </font>|<font color="#F66151"> 27.78% (10/36)    </font>|<font color="#E9AD0C"> 51.22% (21/41)   </font>|
| contracts/libraries/UniswapOracleLibrary.sol                        |<font color="#33DA7A"> 81.25% (13/16)     </font>|<font color="#33DA7A"> 84.62% (22/26)     </font>|<font color="#33DA7A"> 83.33% (5/6)      </font>|<font color="#33DA7A"> 100.00% (2/2)    </font>|
| contracts/libraries/UniswapTickMath.sol                             |<font color="#F66151"> 35.14% (39/111)    </font>|<font color="#F66151"> 43.66% (62/142)    </font>|<font color="#33DA7A"> 78.26% (36/46)    </font>|<font color="#E9AD0C"> 50.00% (1/2)     </font>|
| contracts/libraries/console.sol                                     |<font color="#F66151"> 11.11% (22/198)    </font>|<font color="#F66151"> 14.23% (34/239)    </font>|<font color="#F66151"> 25.00% (2/8)      </font>|<font color="#F66151"> 18.18% (8/44)    </font>|
| contracts/mocks/MockAggregatorV3.sol                                |<font color="#33DA7A"> 75.00% (15/20)     </font>|<font color="#33DA7A"> 75.00% (15/20)     </font>|<font color="#33DA7A"> 100.00% (4/4)     </font>|<font color="#F66151"> 44.44% (4/9)     </font>|
| contracts/mocks/RocketDepositPool.sol                               |<font color="#8B8A88"> 100.00% (0/0)      </font>|<font color="#8B8A88"> 100.00% (0/0)      </font>|<font color="#8B8A88"> 100.00% (0/0)     </font>|<font color="#F66151"> 0.00% (0/1)      </font>|
| contracts/mocks/RocketStorage.sol                                   |<font color="#33DA7A"> 100.00% (3/3)      </font>|<font color="#33DA7A"> 100.00% (3/3)      </font>|<font color="#8B8A88"> 100.00% (0/0)     </font>|<font color="#33DA7A"> 100.00% (3/3)    </font>|
| contracts/mocks/RocketTokenRETH.sol                                 |<font color="#E9AD0C"> 53.33% (8/15)      </font>|<font color="#E9AD0C"> 60.00% (12/20)     </font>|<font color="#F66151"> 12.50% (1/8)      </font>|<font color="#E9AD0C"> 71.43% (5/7)     </font>|
| contracts/mocks/STETH.sol                                           |<font color="#F66151"> 42.86% (3/7)       </font>|<font color="#F66151"> 44.44% (4/9)       </font>|<font color="#E9AD0C"> 50.00% (2/4)      </font>|<font color="#F66151"> 16.67% (1/6)     </font>|
| contracts/mocks/UNSTETH.sol                                         |<font color="#F66151"> 0.00% (0/27)       </font>|<font color="#F66151"> 0.00% (0/36)       </font>|<font color="#F66151"> 0.00% (0/6)       </font>|<font color="#F66151"> 0.00% (0/4)      </font>|
| contracts/tokens/Asset.sol                                          |<font color="#33DA7A"> 100.00% (4/4)      </font>|<font color="#33DA7A"> 100.00% (5/5)      </font>|<font color="#33DA7A"> 100.00% (2/2)     </font>|<font color="#33DA7A"> 100.00% (4/4)    </font>|
| contracts/tokens/Ditto.sol                                          |<font color="#33DA7A"> 100.00% (8/8)      </font>|<font color="#33DA7A"> 100.00% (9/9)      </font>|<font color="#33DA7A"> 100.00% (2/2)     </font>|<font color="#33DA7A"> 100.00% (7/7)    </font>|
| contracts/tokens/yDUSD.sol                                          |<font color="#33DA7A"> 100.00% (47/47)    </font>|<font color="#33DA7A"> 95.29% (81/85)     </font>|<font color="#33DA7A"> 83.33% (20/24)    </font>|<font color="#33DA7A"> 100.00% (10/10)  </font>|
| deploy/DeployDiamond.s.sol                                          |<font color="#F66151"> 0.00% (0/48)       </font>|<font color="#F66151"> 0.00% (0/57)       </font>|<font color="#F66151"> 0.00% (0/4)       </font>|<font color="#F66151"> 0.00% (0/1)      </font>|
| deploy/DeployHelper.sol                                             |<font color="#33DA7A"> 89.08% (155/174)   </font>|<font color="#33DA7A"> 90.00% (171/190)   </font>|<font color="#F66151"> 45.45% (10/22)    </font>|<font color="#E9AD0C"> 50.00% (3/6)     </font>|
| deploy/ImmutableCreate2Factory.sol                                  |<font color="#E9AD0C"> 50.00% (7/14)      </font>|<font color="#E9AD0C"> 53.33% (8/15)      </font>|<font color="#F66151"> 30.00% (3/10)     </font>|<font color="#F66151"> 40.00% (2/5)     </font>|
| deploy/MultiCall3.sol                                               |<font color="#F66151"> 0.00% (0/55)       </font>|<font color="#F66151"> 0.00% (0/57)       </font>|<font color="#F66151"> 0.00% (0/10)      </font>|<font color="#F66151"> 0.00% (0/16)     </font>|
| deploy/migrations/01_remove_functions/01_remove_functions.s.sol     |<font color="#F66151"> 0.00% (0/4)        </font>|<font color="#F66151"> 0.00% (0/5)        </font>|<font color="#8B8A88"> 100.00% (0/0)     </font>|<font color="#F66151"> 0.00% (0/1)      </font>|
| deploy/migrations/02_upgrade_diamondCut/02_upgrade_diamondCut.s.sol |<font color="#F66151"> 5.88% (1/17)       </font>|<font color="#F66151"> 5.00% (1/20)       </font>|<font color="#8B8A88"> 100.00% (0/0)     </font>|<font color="#E9AD0C"> 50.00% (1/2)     </font>|
| deploy/migrations/03_deploy_dao/03_deploy_dao.s.sol                 |<font color="#F66151"> 11.36% (10/88)     </font>|<font color="#F66151"> 12.63% (12/95)     </font>|<font color="#8B8A88"> 100.00% (0/0)     </font>|<font color="#E9AD0C"> 50.00% (1/2)     </font>|
| deploy/migrations/04_etherscan_diamond/04_etherscan_diamond.s.sol   |<font color="#F66151"> 34.78% (16/46)     </font>|<font color="#F66151"> 36.73% (18/49)     </font>|<font color="#8B8A88"> 100.00% (0/0)     </font>|<font color="#E9AD0C"> 50.00% (1/2)     </font>|
| deploy/migrations/05_disable_deposit/05_disable_deposit.s.sol       |<font color="#F66151"> 27.27% (6/22)      </font>|<font color="#F66151"> 27.27% (6/22)      </font>|<font color="#8B8A88"> 100.00% (0/0)     </font>|<font color="#E9AD0C"> 50.00% (1/2)     </font>|
| deploy/migrations/0X_example_migration/0X_example_migration.s.sol   |<font color="#F66151"> 21.54% (14/65)     </font>|<font color="#F66151"> 21.74% (15/69)     </font>|<font color="#8B8A88"> 100.00% (0/0)     </font>|<font color="#F66151"> 33.33% (1/3)     </font>|
| deploy/migrations/MigrationHelper.sol                               |<font color="#33DA7A"> 75.00% (3/4)       </font>|<font color="#E9AD0C"> 60.00% (3/5)       </font>|<font color="#8B8A88"> 100.00% (0/0)     </font>|<font color="#F66151"> 33.33% (1/3)     </font>|
| test/DiamondCut.t.sol                                               |<font color="#33DA7A"> 100.00% (2/2)      </font>|<font color="#33DA7A"> 100.00% (2/2)      </font>|<font color="#8B8A88"> 100.00% (0/0)     </font>|<font color="#33DA7A"> 100.00% (2/2)    </font>|
| test/SSTORE2.t.sol                                                  |<font color="#33DA7A"> 100.00% (12/12)    </font>|<font color="#33DA7A"> 100.00% (12/12)    </font>|<font color="#E9AD0C"> 50.00% (2/4)      </font>|<font color="#33DA7A"> 100.00% (4/4)    </font>|
| test/fork/ForkHelper.sol                                            |<font color="#33DA7A"> 100.00% (30/30)    </font>|<font color="#33DA7A"> 100.00% (32/32)    </font>|<font color="#8B8A88"> 100.00% (0/0)     </font>|<font color="#33DA7A"> 100.00% (1/1)    </font>|
| test/fork/MultiAssetFork.t.sol                                      |<font color="#33DA7A"> 100.00% (39/39)    </font>|<font color="#33DA7A"> 100.00% (40/40)    </font>|<font color="#8B8A88"> 100.00% (0/0)     </font>|<font color="#33DA7A"> 100.00% (1/1)    </font>|
| test/invariants/Handler.sol                                         |<font color="#33DA7A"> 87.72% (457/521)   </font>|<font color="#33DA7A"> 89.33% (586/656)   </font>|<font color="#33DA7A"> 77.19% (88/114)   </font>|<font color="#33DA7A"> 75.44% (43/57)   </font>|
| test/invariants/InvariantsBase.sol                                  |<font color="#F66151"> 3.45% (11/319)     </font>|<font color="#F66151"> 2.93% (13/444)     </font>|<font color="#F66151"> 0.00% (0/52)      </font>|<font color="#F66151"> 4.17% (1/24)     </font>|
| test/invariants/InvariantsSandBox.sol                               |<font color="#F66151"> 0.00% (0/3)        </font>|<font color="#F66151"> 0.00% (0/3)        </font>|<font color="#8B8A88"> 100.00% (0/0)     </font>|<font color="#F66151"> 0.00% (0/1)      </font>|
| test/utils/AddressSet.sol                                           |<font color="#E9AD0C"> 69.57% (16/23)     </font>|<font color="#E9AD0C"> 59.26% (16/27)     </font>|<font color="#E9AD0C"> 62.50% (5/8)      </font>|<font color="#E9AD0C"> 50.00% (4/8)     </font>|
| test/utils/ConstantsTest.sol                                        |<font color="#F66151"> 40.00% (4/10)      </font>|<font color="#F66151"> 29.41% (5/17)      </font>|<font color="#8B8A88"> 100.00% (0/0)     </font>|<font color="#F66151"> 0.00% (0/8)      </font>|
| test/utils/LiquidationHelper.sol                                    |<font color="#33DA7A"> 100.00% (83/83)    </font>|<font color="#33DA7A"> 100.00% (91/91)    </font>|<font color="#E9AD0C"> 66.67% (8/12)     </font>|<font color="#F66151"> 12.50% (1/8)     </font>|
| test/utils/OBFixture.sol                                            |<font color="#33DA7A"> 92.89% (196/211)   </font>|<font color="#33DA7A"> 92.80% (232/250)   </font>|<font color="#33DA7A"> 83.33% (5/6)      </font>|<font color="#F66151"> 13.85% (9/65)    </font>|
| Total                                                               |<font color="#E9AD0C"> 74.33% (3428/4612) </font>|<font color="#33DA7A"> 75.01% (4437/5915) </font>|<font color="#33DA7A"> 77.61% (953/1228) </font>|<font color="#E9AD0C"> 57.35% (468/816) </font>|
</pre>

## Miscellaneous
Employees of DittoETH and employees' family members are ineligible to participate in this audit.



