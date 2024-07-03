# DittoEth audit details
- Total Prize Pool: $13,100 in USDC
  - HM awards: $11000 in USDC
  - Judge awards: $2100 in USDC
  - Validator awards: XXX XXX USDC
  - Scout awards: $500 USDC
- Join [C4 Discord](https://discord.gg/code4rena) to register
- Submit findings [using the C4 form](https://code4rena.com/contests/2024-07-dittoeth/submit)
- [Read our guidelines for more details](https://docs.code4rena.com/roles/wardens)
- Starts July 2, 2024 20:00 UTC
- Ends July 8, 2024 20:00 UTC

## This is a Private audit

This audit repo and its Discord channel are accessible to **certified wardens only.** Participation in private audits is bound by:

1. Code4rena's [Certified Contributor Terms and Conditions](https://github.com/code-423n4/code423n4.com/blob/main/_data/pages/certified-contributor-terms-and-conditions.md)
2. C4's [Certified Contributor Code of Professional Conduct](https://code4rena.notion.site/Code-of-Professional-Conduct-657c7d80d34045f19eee510ae06fef55)

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
  - ~~There is an issue when `claimRemainingCollateral()` is called on a SR that is included in a proposal and is later correctly disputed.~~ fixed
  - ~~Undecided on how to distribute the redemption fee, maybe to dusd holders rather than just the system.~~ Redemption fee goes to the TAPP
  - ~~Currently allowed to redeem at any CR under 2, even under 1 CR.~~ Cannot redeem under 1 CR

## added known issues
- In the case of collateral efficient SR, protocol can be overly conservative with checkShortMinErc for partial liquidations in reverting (Not worried bc the liquidator can just supply the asks needed to reach full liquidation)
- Is possible to have SR with CR higher than max at small amounts, ie. collateral efficient SR with ethInitial and small partial match
- If you don’t dispute before proposing, can get disputed yourself since dispute doesn’t change updatedAt
- new: ERC4626 Vault (yDUSD.sol)
  - the vault contract is currently immutable, but before deployment will either be a proxy or diamond, or incorporate a way to modify the values
- Found an issue with modifying the ercDebt/updateErcDebt, regarding discountFees/socializing debt from blackswan. Introduced ercDebtFee to allow the fee itself not to be compounded. Didn't cover every case but looking for feedback

✅ SCOUTS: Please format the response above 👆 so its not a wall of text and its readable.

# Overview

[ ⭐️ SPONSORS: add info here ]

## Links

- **Previous audits:**  https://code4rena.com/reports/2024-03-dittoeth
  - ✅ SCOUTS: If there are multiple report links, please format them in a list.
- **Documentation:** https://dittoeth.com/
- **Website:** 🐺 CA: add a link to the sponsor's website
- **X/Twitter:** 🐺 CA: add a link to the sponsor's Twitter
- **Discord:** 🐺 CA: add a link to the sponsor's Discord

---

# Scope

[ ✅ SCOUTS: add scoping and technical details here ]

### Files in scope
- ✅ This should be completed using the `metrics.md` file
- ✅ Last row of the table should be Total: SLOC
- ✅ SCOUTS: Have the sponsor review and and confirm in text the details in the section titled "Scoping Q amp; A"

*For sponsors that don't use the scoping tool: list all files in scope in the table below (along with hyperlinks) -- and feel free to add notes to emphasize areas of focus.*

| Contract | SLOC | Purpose | Libraries used |  
| ----------- | ----------- | ----------- | ----------- |
| [contracts/folder/sample.sol](https://github.com/code-423n4/repo-name/blob/contracts/folder/sample.sol) | 123 | This contract does XYZ | [`@openzeppelin/*`](https://openzeppelin.com/contracts/) |

### Files out of scope
✅ SCOUTS: List files/directories out of scope

## Scoping Q &amp; A

### General questions
### Are there any ERC20's in scope?: Yes

✅ SCOUTS: If the answer above 👆 is "Yes", please add the tokens below 👇 to the table. Otherwise, update the column with "None".

Specific tokens (please specify)
Protocol tokens: Asset.sol (DUSD, DETH, Ditto), LSTs: stETH/rETH

### Are there any ERC777's in scope?: No

✅ SCOUTS: If the answer above 👆 is "Yes", please add the tokens below 👇 to the table. Otherwise, update the column with "None".



### Are there any ERC721's in scope?: Yes

✅ SCOUTS: If the answer above 👆 is "Yes", please add the tokens below 👇 to the table. Otherwise, update the column with "None".

Protocol token: NFT as part of the Diamond, represents a ShortRecord position

### Are there any ERC1155's in scope?: No

✅ SCOUTS: If the answer above 👆 is "Yes", please add the tokens below 👇 to the table. Otherwise, update the column with "None".



✅ SCOUTS: Once done populating the table below, please remove all the Q/A data above.

| Question                                | Answer                       |
| --------------------------------------- | ---------------------------- |
| ERC20 used by the protocol              |       🖊️             |
| Test coverage                           | ✅ SCOUTS: Please populate this after running the test coverage command                          |
| ERC721 used  by the protocol            |            🖊️              |
| ERC777 used by the protocol             |           🖊️                |
| ERC1155 used by the protocol            |              🖊️            |
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
wouldn't worry about this. yDUSD is new as ERC4626 though.

These are old and not looking for compliance audit: 
Asset.sol (DUSD/DETH) - ERC20
Ditto.sol - ERC20
ERC721Facet.sol - ERC721

✅ SCOUTS: Please format the response above 👆 using the template below👇

| Question                                | Answer                       |
| --------------------------------------- | ---------------------------- |
| src/Token.sol                           | ERC20, ERC721                |
| src/NFT.sol                             | ERC721                       |


# Additional context

## Main invariants

## Orderbook

Ditto's orderbook acts similar to central limit orderbook with some changes. In order to make the gas costs low, there is a hint system added to enable a user to place an order in the orderbook mapping. Asks/Shorts are both on the "sell" side of the orderbook. Order structs are reused by implementing the orders as a doubly linked-list in a mapping. HEAD order is used as a starting point to match against.

Ask orders get matched before short orders at the same price.
Bids sorted high to low
Asks/Shorts sorted low to high
Only cancelled/matched orders can be reused (Technically: Left of HEAD (HEAD.prevId) these are the only possible OrderTypes: O.Matched, O.Cancelled, O.Uninitialized).
Since bids/asks/shorts share the same orderId counter, every single orderId should be unique

## Short Orders

shortOrders can only be limit orders. startingShort represents the first short order that can be matched. Normally HEAD.nextId would the next short order in the mapping, but it's not guaranteed that it is matchable since users can still create limit shorts under the oracle price (or they move below oracle once the price updates). Oracle updates from chainlink or elsewhere will cause the startingShort to move, which means the system doesn't know when to start matching from without looping through each short, so the system allows a temporary matching backwards.

shortOrder can't match under oraclePrice
startingShort price must be greater than or equal to oraclePrice
shortOrder with a non-zero (ie. positive) shortRecordId means that the referenced SR is status partialFill

## ShortRecords

ShortRecords are the Vaults/CDPs/Troves of Ditto. SRs represent a collateral/debt position by a shorter. Each user can have multiple SRs, which are stored under their address as a list.

The only time shortRecord debt can be below minShortErc is when it's partially filled and the connected shortOrder has enough ercDebt to make up the difference to minShortErc (Technically: SR.status == PartialFill && shortOrder.ercAmount + ercDebt >= minShortErc)
Similarly, SR can never be SR.FullyFilled and be under minShortErc
FullyFilled SR can never have 0 collateral
Only SR with status Closed can ever be re-used (Technically, only SR.Closed on the left (prevId) side of HEAD, with the exception of HEAD itself)

## Redemptions

Allows dUSD holders to get equivalent amount of ETH back, akin to Liquity. However the system doesn't automatically sort the SR's lowest to highest. Instead, users propose a list of SRs (an immutable slate) to redeem against. There is a dispute period to revert any proposal changes and a corresponding penalty against a proposer if incorrect. Proposers can claim the ETH after the time period, and shorters can also claim any remaining collateral afterwards.

Proposal "slates" are sorted least to highest CR
All CR in proposedData dataTypes should be under 2 CR, above 1 CR
If proposal happens, check to see that there is no issues with SSTORE2 (the way it is saved and read)
Relationship between proposal and SR's current collateral and ercDebt amounts. The sum total should always add up to the original amounts (save those amounts)
SR can be SR.Closed before claim if closed another way (like liquidation)
SR can be partially redeemed in non-last position only if it gets refilled after a full proposal

## BridgeRouter/Bridge

Because the Vault mixes rETH/stETH, a credit system is introduced to allow users to withdraw only what they deposit, anything in excess (due to yield) also checks either LSTs price difference using a TWAP via Uniswap.

deposit/withdraw gives/removes an appropriate amount of virtual dETH (ETH equivalent), no matter if someone deposits an LST (rETH, stETH), or ETH and accounts for yield that is gained over time.

## Misc

NFT can only be SR.FullyFilled
TAPP SR is never moved to the left of HEAD, even when closed bc of full liquidation
All deleted SR have collateral = 0, unless pointing to shortOrder
User should never be able to force SR under initialCR (excluding oracle price change)
Collateral Efficient SR being redeemed always has enough ETH


✅ SCOUTS: Please format the response above 👆 so its not a wall of text and its readable.

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
- Solidity `0.8.25`
- Remove NFT of SR feature, make room for something else
- Make ercDebtRate u80 from u64
- Start using tstore/tload

## Attack ideas (where to focus for bugs)
- 2 new "features": ercDebt increase on price discount (when there's a match under oracle) + the vault that the ercDebt goes to.
- Fixes from the last audit
- In general: redemptions feature, orderbook matching, dust amounts (minShortErc), liquidations at the right time.

✅ SCOUTS: Please format the response above 👆 so its not a wall of text and its readable.

## All trusted roles in the protocol

- Asset can mint/burn with onlyDiamond, 
- for OwnerFacet: onlyAdminOrDAO, onlyDAO

✅ SCOUTS: Please format the response above 👆 using the template below👇

| Role                                | Description                       |
| --------------------------------------- | ---------------------------- |
| Owner                          | Has superpowers                |
| Administrator                             | Can change fees                       |

## Describe any novel or unique curve logic or mathematical models implemented in the contracts:

n/a

✅ SCOUTS: Please format the response above 👆 so its not a wall of text and its readable.

## Running tests

# Use Bun to run TypeScript
curl -fsSL https://bun.sh/install | bash

bun install

# Install foundry for solidity
curl -L https://foundry.paradigm.xyz | bash
foundryup

# .env for tests
echo 'ANVIL_9_PRIVATE_KEY=0x2a871d0798f97d79848a013d4936a73bf4cc922c825d33c1cf7073dff6d409c6' >> .env
echo 'MAINNET_RPC_URL=http://eth.drpc.org' >> .env

# create interfaces (should already be committed into `interfaces/`, but usually in .gitignore)
bun run interfaces-force

# build
bun run build

# unit/fork/invariant tests
bun run test

# gas tests, check `/.gas.json`
bun run test-gas

✅ SCOUTS: Please format the response above 👆 using the template below👇

```bash
git clone https://github.com/code-423n4/2023-08-arbitrum
git submodule update --init --recursive
cd governance
foundryup
make install
make build
make sc-election-test
```
To run code coverage
```bash
make coverage
```
To run gas benchmarks
```bash
make gas
```

✅ SCOUTS: Add a screenshot of your terminal showing the gas report
✅ SCOUTS: Add a screenshot of your terminal showing the test coverage

## Miscellaneous
Employees of DittoETH and employees' family members are ineligible to participate in this audit.



