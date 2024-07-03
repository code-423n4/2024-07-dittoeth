# Report

## Non Critical Issues


| |Issue|Instances|
|-|:-|:-:|
| [NC-1](#NC-1) | `require()` should be used instead of `assert()` | 3 |
| [NC-2](#NC-2) | `constant`s should be defined rather than using magic numbers | 39 |
| [NC-3](#NC-3) | Control structures do not follow the Solidity Style Guide | 157 |
| [NC-4](#NC-4) | Dangerous `while(true)` loop | 5 |
| [NC-5](#NC-5) | Delete rogue `console.log` imports | 2 |
| [NC-6](#NC-6) | Functions should not be longer than 50 lines | 171 |
| [NC-7](#NC-7) | Change int to int256 | 4 |
| [NC-8](#NC-8) | Lines are too long | 1 |
| [NC-9](#NC-9) | Use a `modifier` instead of a `require/if` statement for a special `msg.sender` actor | 12 |
| [NC-10](#NC-10) | Consider using named mappings | 12 |
| [NC-11](#NC-11) | Take advantage of Custom Error's return value property | 110 |
| [NC-12](#NC-12) | Use scientific notation (e.g. `1e18`) rather than exponentiation (e.g. `10**18`) | 3 |
| [NC-13](#NC-13) | Use Underscores for Number Literals (add an underscore every 3 digits) | 8 |
| [NC-14](#NC-14) | Constants should be defined rather than using magic numbers | 12 |
| [NC-15](#NC-15) | Variables need not be initialized to zero | 6 |
### <a name="NC-1"></a>[NC-1] `require()` should be used instead of `assert()`
Prior to solidity version 0.8.0, hitting an assert consumes the **remainder of the transaction's available gas** rather than returning it, as `require()`/`revert()` do. `assert()` should be avoided even past solidity version 0.8.0 as its [documentation](https://docs.soliditylang.org/en/v0.8.14/control-structures.html#panic-via-assert-and-error-via-require) states that "The assert function creates an error of type Panic(uint256). ... Properly functioning code should never create a Panic, not even on invalid external input. If this happens, then there is a bug in your contract which you should fix. Additionally, a require statement (or a custom error) are more friendly in terms of understanding what happened."

*Instances (3)*:
```solidity
File: ./facets/ProposeRedemptionFacet.sol

150:         assert(newBaseRate > 0); // Base rate is always non-zero after redemption

```

```solidity
File: ./facets/SecondaryLiquidationFacet.sol

99:                 assert(tokenContract.balanceOf(msg.sender) < walletBalance);

```

```solidity
File: ./libraries/LibAsset.sol

22:         assert(tokenContract.balanceOf(msg.sender) < walletBalance);

```

### <a name="NC-2"></a>[NC-2] `constant`s should be defined rather than using magic numbers
Even [assembly](https://github.com/code-423n4/2022-05-opensea-seaport/blob/9d7ce4d08bf3c3010304a0476a785c70c0e90ae7/contracts/lib/TokenTransferrer.sol#L35-L39) can benefit from using readable constants instead of hex/numeric literals

*Instances (39)*:
```solidity
File: ./facets/OrdersFacet.sol

77:         if (s.asset[asset].orderIdCounter < 65000) revert Errors.OrderIdCountTooLow();

79:         if (numOrdersToCancel > 1000) revert Errors.CannotCancelMoreThan1000Orders();

144:         uint32 timeDiff = (protocolTime - Asset.initialDiscountTime) / 86400 seconds;

146:         if (timeDiff > 7) {

```

```solidity
File: ./facets/OwnerFacet.sol

240:         if (dethTithePercent > 33_33) revert Errors.InvalidTithe();

246:         require(rewardRate <= 100, "above 100");

251:         require(rewardRate <= 100, "above 100");

262:         require(value > 100, "below 1.0");

263:         require(value <= 500, "above 5.0");

268:         require(value >= 100, "below 1.0");

269:         require(value <= 200, "above 2.0");

274:         require(value >= 100, "below 1.0");

275:         require(value <= 120, "above 1.2");

282:         require(value <= 250, "above 250");

288:         require(value <= 250, "above 250");

311:         require(withdrawalFee <= 200, "above 2.00%");

316:         require(value >= 100, "below 1.0");

317:         require(value <= 200, "above 2.0");

323:         require(value <= 1000, "above 10.0%");

329:         require(value < type(uint16).max, "above 65534");

```

```solidity
File: ./facets/PrimaryLiquidationFacet.sol

57:         if (shortHintArray.length > 10) revert Errors.TooManyHints();

```

```solidity
File: ./facets/ShortRecordFacet.sol

124:         if (ids.length < 2) revert Errors.InsufficientNumberOfShorts();

```

```solidity
File: ./libraries/LibBytes.sol

20:         uint256 proposalDataSize = 62;

21:         require((slate.length - 28) % proposalDataSize == 0, "Invalid data length");

28:             uint256 offset = i * proposalDataSize + 28 + 32;

48:                 fullWord := mload(add(slate, add(offset, 29))) // (29 offset)

54:                 fullWord := mload(add(slate, add(offset, 51))) // (51 offset)

75:             let fullWord := mload(add(slate, 32))

```

```solidity
File: ./libraries/LibOracle.sol

76:         bool invalidFetchData = validateFetchData(roundId, timeStamp, chainlinkPrice) || block.timestamp > 2 hours + timeStamp;

87:             try IDiamond(payable(address(this))).estimateWETHInUSDC(C.UNISWAP_WETH_BASE_AMT, 30 minutes) returns (uint256 twapPrice)

104:                     if (wethBal < 100 ether) {

127:             validateFetchData(baseRoundId, baseTimeStamp, baseChainlinkPrice) || block.timestamp > 2 hours + baseTimeStamp;

133:         uint256 twapPrice = IDiamond(payable(address(this))).estimateWETHInUSDC(C.UNISWAP_WETH_BASE_AMT, 30 minutes);

139:         if (wethBal < 100 ether) revert Errors.InsufficientEthInLiquidityPool();

169:         if (LibOrders.getOffsetTime() - getTime(asset) < 15 minutes) {

```

```solidity
File: ./libraries/LibOrders.sol

835:         if (timeDiff >= 15 minutes) {

```

```solidity
File: ./libraries/LibRedemption.sol

64:         | 1.7   |     3      |

65:         | 2.0   |     6      |

80:             timeToDispute = protocolTime + uint32((m.mul(lastCR - 1.7 ether) + 3 ether) * 1 hours / 1 ether);

```

### <a name="NC-3"></a>[NC-3] Control structures do not follow the Solidity Style Guide
See the [control structures](https://docs.soliditylang.org/en/latest/style-guide.html#control-structures) section of the Solidity Style Guide

*Instances (157)*:
```solidity
File: ./facets/BidOrdersFacet.sol

8: import {Modifiers} from "contracts/libraries/AppStorage.sol";

90:         if (eth < LibAsset.minBidEth(asset)) revert Errors.OrderUnderMinimumSize();

93:         if (s.vaultUser[Asset.vault][sender].ethEscrowed < eth) revert Errors.InsufficientETHEscrowed();

381:         As such, it will be used as the last Id matched (if moving backwards ONLY)

388:         If the bid matches BACKWARDS ONLY, lets say to (ID2), then the linked list will look like this after execution

```

```solidity
File: ./facets/BridgeRouterFacet.sol

8: import {Modifiers} from "contracts/libraries/AppStorage.sol";

64:         if (amount < C.MIN_DEPOSIT) revert Errors.UnderMinimumDeposit();

83:         if (msg.value < C.MIN_DEPOSIT) revert Errors.UnderMinimumDeposit();

102:         if (dethAmount == 0) revert Errors.ParameterIsZero();

134:         if (dethAmount == 0) revert Errors.ParameterIsZero();

164:             if (vault == 0) revert Errors.InvalidBridge();

```

```solidity
File: ./facets/ClaimRedemptionFacet.sol

8: import {Modifiers} from "contracts/libraries/AppStorage.sol";

32:         if (redeemerAssetUser.SSTORE2Pointer == address(0)) revert Errors.InvalidRedemption();

37:         if (LibOrders.getOffsetTime() < timeToDispute) revert Errors.TimeToDisputeHasNotElapsed();

62:         if (redeemerAssetUser.SSTORE2Pointer == address(0)) revert Errors.InvalidRedemption();

68:         if (timeToDispute > LibOrders.getOffsetTime()) revert Errors.TimeToDisputeHasNotElapsed();

71:         if (claimProposal.shorter != msg.sender || claimProposal.shortId != id) revert Errors.CanOnlyClaimYourShort();

```

```solidity
File: ./facets/DisputeRedemptionFacet.sol

8: import {Modifiers} from "contracts/libraries/AppStorage.sol";

36:         if (redeemer == msg.sender) revert Errors.CannotDisputeYourself();

43:         if (redeemerAssetUser.SSTORE2Pointer == address(0)) revert Errors.InvalidRedemption();

48:         if (d.protocolTime >= d.timeToDispute) revert Errors.TimeToDisputeHasElapsed();

76:                     if (d.disputeCR < prevProposal.CR) revert Errors.NotLowestIncorrectIndex();

```

```solidity
File: ./facets/ExitShortFacet.sol

8: import {Modifiers} from "contracts/libraries/AppStorage.sol";

54:         if (buybackAmount > ercDebt || buybackAmount == 0) revert Errors.InvalidBuyback();

103:         if (buybackAmount == 0 || buybackAmount > ercDebt) revert Errors.InvalidBuyback();

107:             if (AssetUser.ercEscrowed < buybackAmount) revert Errors.InsufficientERCEscrowed();

181:         if (e.buybackAmount == 0 || e.buybackAmount > e.ercDebt) revert Errors.InvalidBuyback();

185:             if (ethAmount > e.collateral) revert Errors.InsufficientCollateral();

196:         if (e.ethFilled == 0) revert Errors.ExitShortPriceTooLow();

213:             if (short.ercDebt < LibAsset.minShortErc(Asset)) revert Errors.CannotLeaveDustAmount();

216:             if (getCollateralRatioNonPrice(short) < e.beforeExitCR) revert Errors.PostExitCRLtPreExitCR();

```

```solidity
File: ./facets/MarketShutdownFacet.sol

9: import {Modifiers} from "contracts/libraries/AppStorage.sol";

```

```solidity
File: ./facets/OrdersFacet.sol

8: import {Modifiers} from "contracts/libraries/AppStorage.sol";

32:         if (msg.sender != bid.addr) revert Errors.NotOwner();

45:         if (msg.sender != ask.addr) revert Errors.NotOwner();

58:         if (msg.sender != short.addr) revert Errors.NotOwner();

59:         if (short.orderType != O.LimitShort) revert Errors.NotActiveOrder();

77:         if (s.asset[asset].orderIdCounter < 65000) revert Errors.OrderIdCountTooLow();

79:         if (numOrdersToCancel > 1000) revert Errors.CannotCancelMoreThan1000Orders();

144:         uint32 timeDiff = (protocolTime - Asset.initialDiscountTime) / 86400 seconds;

150:             daysElapsed = timeDiff;

```

```solidity
File: ./facets/OwnerFacet.sol

6: import {Modifiers} from "contracts/libraries/AppStorage.sol";

47:         if (Asset.orderIdCounter != 0) revert Errors.MarketAlreadyCreated();

112:         if (s.ownerCandidate != msg.sender) revert Errors.NotOwnerCandidate();

124:         if (s.dethVault[deth] != 0) revert Errors.VaultAlreadyCreated();

219:         if (vault == 0) revert Errors.InvalidVault();

221:         if (Bridge.vault != 0) revert Errors.BridgeAlreadyCreated();

235:         if (asset == address(0) || oracle == address(0)) revert Errors.ParameterIsZero();

240:         if (dethTithePercent > 33_33) revert Errors.InvalidTithe();

```

```solidity
File: ./facets/PrimaryLiquidationFacet.sol

11: import {Modifiers} from "contracts/libraries/AppStorage.sol";

55:         if (msg.sender == shorter) revert Errors.CannotLiquidateSelf();

57:         if (shortHintArray.length > 10) revert Errors.TooManyHints();

104:         if (

241:         if (a > type(uint88).max) revert Errors.InvalidAmount();

```

```solidity
File: ./facets/ProposeRedemptionFacet.sol

8: import {Modifiers} from "contracts/libraries/AppStorage.sol";

39:         if (block.timestamp > deadline) revert Errors.ProposalExpired(deadline);

41:         if (proposalInput.length > type(uint8).max) revert Errors.TooManyProposals();

48:         if (redemptionAmount < minShortErc) revert Errors.RedemptionUnderMinShortErc();

49:         if (redeemerAssetUser.ercEscrowed < redemptionAmount) revert Errors.InsufficientERCEscrowed();

51:         if (redeemerAssetUser.SSTORE2Pointer != address(0)) revert Errors.ExistingProposedRedemptions();

66:             if (!LibRedemption.validRedemptionSR(currentSR, msg.sender, p.shorter, minShortErc)) continue;

72:             if (p.lastCR > p.currentCR || p.currentCR >= C.MAX_REDEMPTION_CR || p.currentCR < C.ONE_CR) continue;

80:                 if (currentSR.ercDebt - p.amountProposed < minShortErc) break;

88:                 if (LibSRUtil.invalidShortOrder(shortOrder, p.shortId, p.shorter)) continue;

130:             if (redemptionAmount - p.totalAmountProposed < minShortErc) break;

133:         if (p.totalAmountProposed < minShortErc) revert Errors.RedemptionUnderMinShortErc();

158:         if (redemptionFee > maxRedemptionFee) revert Errors.RedemptionFeeTooHigh();

161:         if (VaultUser.ethEscrowed < redemptionFee) revert Errors.InsufficientETHEscrowed();

```

```solidity
File: ./facets/SecondaryLiquidationFacet.sol

11: import {Modifiers} from "contracts/libraries/AppStorage.sol";

69:             if (

79:                 if (LibSRUtil.invalidShortOrder(shortOrder, m.short.id, m.shorter)) continue;

97:                 if (walletBalance < m.short.ercDebt) continue;

101:                 if (AssetUser.ercEscrowed < m.short.ercDebt) continue;

122:             if (liquidateAmountLeft == 0) break;

125:         if (liquidateAmount == liquidateAmountLeft) revert Errors.SecondaryLiquidationNoValidShorts();

151:         if (m.short.ercDebt == 0) return m; // @dev To avoid divide by 0 for CR calc, SR will be skipped anyways

192:         if (a > type(uint88).max) revert Errors.InvalidAmount();

```

```solidity
File: ./facets/ShortOrdersFacet.sol

8: import {Modifiers} from "contracts/libraries/AppStorage.sol";

47:         if (p.CR + C.BID_CR < p.initialCR || p.CR >= C.CRATIO_MAX_INITIAL) revert Errors.InvalidCR();

52:         if (ercAmount < p.minShortErc || p.eth < p.minAskEth) revert Errors.OrderUnderMinimumSize();

58:             uint256 diffCR = p.initialCR - p.CR;

59:             p.ethInitial = minEth.mul(diffCR);

61:             if (vaultUser.ethEscrowed < p.eth.mul(p.CR) + p.ethInitial) revert Errors.InsufficientETHEscrowed();

86:         if (LibSRUtil.checkRecoveryModeViolation(Asset, p.CR, p.oraclePrice)) revert Errors.BelowRecoveryModeCR();

```

```solidity
File: ./facets/ShortRecordFacet.sol

8: import {Modifiers} from "contracts/libraries/AppStorage.sol";

50:         if (VaultUser.ethEscrowed < amount) revert Errors.InsufficientETHEscrowed();

66:         if (cRatio >= C.CRATIO_MAX) revert Errors.CollateralHigherThanMax();

91:         if (amount > short.collateral) revert Errors.InsufficientCollateral();

98:         if (cRatio < LibAsset.initialCR(Asset)) revert Errors.CRLowerThanMin();

99:         if (LibSRUtil.checkRecoveryModeViolation(Asset, cRatio, oraclePrice)) revert Errors.BelowRecoveryModeCR();

122:         if (shortOrderIds.length != ids.length) revert Errors.InvalidNumberOfShortOrderIds();

124:         if (ids.length < 2) revert Errors.InsufficientNumberOfShorts();

155:         if (firstShort.status == SR.Closed) revert Errors.FirstShortDeleted();

167:         if (cRatio >= C.CRATIO_MAX) revert Errors.CollateralHigherThanMax();

```

```solidity
File: ./facets/YieldFacet.sol

7: import {Modifiers} from "contracts/libraries/AppStorage.sol";

69:             if (s.asset[assets[i]].vault != vault) revert Errors.DifferentVaults();

102:             bool isNotRecentlyModified = protocolTime - short.updatedAt > C.YIELD_DELAY_SECONDS;

133:         if (yield <= 1) revert Errors.NoYield();

156:         if (shares <= 1) revert Errors.NoShares();

172:         if ((totalReward - userReward) > type(uint96).max) revert Errors.InvalidAmount();

189:         if (amt <= 1) revert Errors.NoDittoReward();

```

```solidity
File: ./libraries/LibAsset.sol

20:         if (walletBalance < debt) revert Errors.InsufficientWalletBalance();

```

```solidity
File: ./libraries/LibOracle.sol

23:         if (address(oracle) == address(0)) revert Errors.InvalidAsset();

58:                 if (validateFetchData(roundID, timeStamp, price)) revert Errors.InvalidPrice();

78:         uint256 chainlinkDiff =

80:         bool priceDeviation = protocolPrice > 0 && chainlinkDiff.div(protocolPrice) > 0.5 ether;

95:                 uint256 twapDiff = twapPriceInEth > protocolPrice ? twapPriceInEth - protocolPrice : protocolPrice - twapPriceInEth;

128:         if (invalidFetchData || invalidFetchDataBase) revert Errors.InvalidPrice();

134:         if (twapPrice == 0) revert Errors.InvalidTwapPrice();

139:         if (wethBal < 100 ether) revert Errors.InsufficientEthInLiquidityPool();

147:     Helper methods are used to set the values of oraclePrice and oracleTime since they are set to different properties

```

```solidity
File: ./libraries/LibOrders.sol

87:         if (order.orderType == O.MarketBid) return;

107:         if (order.orderType == O.MarketAsk) return;

239:     function verifyBidId(address asset, uint16 _prevId, uint256 _newPrice, uint16 _nextId)

268:     function verifySellId(

389:         int256 direction = verifyId(orders, asset, hintId, price, nextId, orderType);

415:     function verifyId(

426:             return verifySellId(orders, asset, prevId, newPrice, nextId);

428:             return verifyBidId(asset, prevId, newPrice, nextId);

700:             if (matchTotal.fillErc < LibAsset.minShortErc(Asset)) revert Errors.ShortRecordFullyFilledUnderMinSize();

780:                 if (short.orderType != O.LimitShort) continue;

834:         uint256 timeDiff = getOffsetTime() - LibOracle.getTime(asset);

901:         if (orderType == O.Cancelled || orderType == O.Matched) revert Errors.NotActiveOrder();

915:         if (orderType == O.Cancelled || orderType == O.Matched) revert Errors.NotActiveOrder();

949:                 uint88 debtDiff = uint88(minShortErc - shortRecord.ercDebt); // @dev(safe-cast)

953:                     uint88 collateralDiff = shortOrder.price.mulU88(debtDiff).mulU88(cr);

960:                         collateralDiff,

961:                         debtDiff,

967:                     Vault.dethCollateral += collateralDiff;

968:                     Asset.dethCollateral += collateralDiff;

969:                     Asset.ercDebt += debtDiff;

972:                     eth -= collateralDiff;

975:                 s.assetUser[asset][shorter].ercEscrowed += debtDiff;

```

```solidity
File: ./libraries/LibPriceDiscount.sol

31:         if (h.ercDebt <= C.DISCOUNT_UPDATE_THRESHOLD) return;

35:         if (assetCR <= LibAsset.recoveryCR(Asset)) return;

```

```solidity
File: ./libraries/LibRedemption.sol

28:         if (shortRecord.status == SR.Closed || shortRecord.ercDebt < minShortErc || proposer == shorter || shorter == address(this))

```

```solidity
File: ./libraries/LibSRUtil.sol

37:             @dev If somebody exits a short, gets liquidated, decreases their collateral before YIELD_DELAY_SECONDS duration is up,

40:             bool isNotRecentlyModified = LibOrders.getOffsetTime() - updatedAt > C.YIELD_DELAY_SECONDS;

66:             if (invalidShortOrder(shortOrder, shortRecordId, shorter)) revert Errors.InvalidShortOrder();

84:             if (invalidShortOrder(shortOrder, shortRecordId, shorter)) revert Errors.InvalidShortOrder();

94:                 if (shortOrder.ercAmount + shortRecord.ercDebt < minShortErc) revert Errors.CannotLeaveDustAmount();

96:                 if (shorter != msg.sender && shortOrder.shortOrderCR < Asset.initialCR) revert Errors.CannotLeaveDustAmount();

149:         if (shortRecord.status == SR.Closed || shortRecord.ercDebt == 0) revert Errors.InvalidShortId();

```

```solidity
File: ./libraries/LibShortRecord.sol

47:             if (currentShort.status != SR.Closed) shortRecordCount++;

```

```solidity
File: ./libraries/LibVault.sol

81:         if (dethTotalNew <= dethTotal) return;

99:         if (dethYieldRate == 0) return;

```

```solidity
File: ./tokens/yDUSD.sol

40:         if (isDiscounted || WithinDiscountWindow) revert Errors.ERC4626CannotWithdrawBeforeDiscountWindowExpires();

44:         if (amountProposed <= 1) revert Errors.ERC4626AmountProposedTooLow();

47:         if (withdrawal.timeProposed > 0) revert Errors.ERC4626ExistingWithdrawalProposal();

49:         if (amountProposed > maxWithdraw(msg.sender)) revert Errors.ERC4626WithdrawMoreThanMax();

60:         if (withdrawal.timeProposed == 0 && withdrawal.amountProposed <= 1) revert Errors.ERC4626ProposeWithdrawFirst();

67:         if (assets > maxDeposit(receiver)) revert Errors.ERC4626DepositMoreThanMax();

77:         if (newBalance < slippage.mul(shares) + oldBalance) revert Errors.ERC4626DepositSlippageExceeded();

89:         if (timeProposed == 0 && amountProposed <= 1) revert Errors.ERC4626ProposeWithdrawFirst();

91:         if (timeProposed + C.WITHDRAW_WAIT_TIME > uint40(block.timestamp)) revert Errors.ERC4626WaitLongerBeforeWithdrawing();

99:         if (amountProposed > maxWithdraw(owner)) revert Errors.ERC4626WithdrawMoreThanMax();

112:         if (newBalance < slippage.mul(amountProposed) + oldBalance) revert Errors.ERC4626WithdrawSlippageExceeded();

```

### <a name="NC-4"></a>[NC-4] Dangerous `while(true)` loop
Consider using for-loops to avoid all risks of an infinite-loop situation

*Instances (5)*:
```solidity
File: ./facets/BidOrdersFacet.sol

140:         while (true) {

```

```solidity
File: ./facets/YieldFacet.sol

98:         while (true) {

```

```solidity
File: ./libraries/LibOrders.sol

461:         while (true) {

581:         while (true) {

```

```solidity
File: ./libraries/LibShortRecord.sol

44:         while (true) {

```

### <a name="NC-5"></a>[NC-5] Delete rogue `console.log` imports
These shouldn't be deployed in production

*Instances (2)*:
```solidity
File: ./facets/BidOrdersFacet.sol

20: import {console} from "contracts/libraries/console.sol";

```

```solidity
File: ./tokens/yDUSD.sol

13: import {console} from "contracts/libraries/console.sol";

```

### <a name="NC-6"></a>[NC-6] Functions should not be longer than 50 lines
Overly complex code can make understanding functionality more difficult, try to further modularize your code to ensure readability 

*Instances (171)*:
```solidity
File: ./facets/BidOrdersFacet.sol

67:     function createForcedBid(address sender, address asset, uint80 price, uint88 ercAmount, uint16[] calldata shortHintArray)

343:     function _getLowestSell(address asset, MTypes.BidMatchAlgo memory b) private view returns (STypes.Order memory lowestSell) {

```

```solidity
File: ./facets/BridgeRouterFacet.sol

40:     function getDethTotal(uint256 vault) external view nonReentrantView returns (uint256) {

51:     function getBridges(uint256 vault) external view returns (address[] memory) {

63:     function deposit(address bridge, uint88 amount) external nonReentrant {

82:     function depositEth(address bridge) external payable nonReentrant {

101:     function withdraw(address bridge, uint88 dethAmount) external nonReentrant {

133:     function withdrawTapp(address bridge, uint88 dethAmount) external onlyDAO {

148:     function maybeUpdateYield(uint256 vault, uint88 amount) private {

156:     function _getVault(address bridge) private view returns (uint256 vault, uint256 bridgePointer) {

169:     function _ethConversion(uint256 vault, uint88 amount) private view returns (uint88) {

```

```solidity
File: ./facets/ClaimRedemptionFacet.sol

28:     function claimRedemption(address asset) external isNotFrozen(asset) nonReentrant {

56:     function claimRemainingCollateral(address asset, address redeemer, uint8 claimIndex, uint8 id)

77:     function _claimRemainingCollateral(address asset, uint256 vault, address shorter, uint8 shortId) private {

```

```solidity
File: ./facets/DisputeRedemptionFacet.sol

31:     function disputeRedemption(address asset, address redeemer, uint8 incorrectIndex, address disputeShorter, uint8 disputeShortId)

```

```solidity
File: ./facets/ExitShortFacet.sol

42:     function exitShortWallet(address asset, uint8 id, uint88 buybackAmount, uint16 shortOrderId)

91:     function exitShortErcEscrowed(address asset, uint8 id, uint88 buybackAmount, uint16 shortOrderId)

227:     function getCollateralRatioNonPrice(STypes.ShortRecord storage short) internal view returns (uint256 cRatio) {

```

```solidity
File: ./facets/MarketShutdownFacet.sol

30:     function shutdownMarket(address asset) external onlyAdminOrDAO onlyValidAsset(asset) isNotFrozen(asset) nonReentrant {

60:     function redeemErc(address asset, uint88 amtWallet, uint88 amtEscrow) external isPermanentlyFrozen(asset) nonReentrant {

```

```solidity
File: ./facets/OrdersFacet.sol

30:     function cancelBid(address asset, uint16 id) external onlyValidAsset(asset) nonReentrant {

43:     function cancelAsk(address asset, uint16 id) external onlyValidAsset(asset) nonReentrant {

56:     function cancelShort(address asset, uint16 id) external onlyValidAsset(asset) nonReentrant {

71:     function cancelOrderFarFromOracle(address asset, O orderType, uint16 lastOrderId, uint16 numOrdersToCancel)

92:     function cancelManyBids(address asset, uint16 lastOrderId, uint16 numOrdersToCancel) internal {

105:     function cancelManyAsks(address asset, uint16 lastOrderId, uint16 numOrdersToCancel) internal {

118:     function cancelManyShorts(address asset, uint16 lastOrderId, uint16 numOrdersToCancel) internal {

132:     function _matchIsDiscounted(MTypes.HandleDiscount memory h) external onlyDiamond {

```

```solidity
File: ./facets/OwnerFacet.sol

44:     function createMarket(address asset, address yieldVault, STypes.Asset memory a) external onlyDAO {

92:     function owner() external view returns (address) {

96:     function admin() external view returns (address) {

101:     function ownerCandidate() external view returns (address) {

105:     function transferOwnership(address newOwner) external onlyDAO {

118:     function transferAdminship(address newAdmin) external onlyAdminOrDAO {

123:     function createVault(address deth, uint256 vault, MTypes.CreateVaultParams calldata params) external onlyDAO {

133:     function setTithe(uint256 vault, uint16 dethTithePercent) external onlyAdminOrDAO {

138:     function setDittoMatchedRate(uint256 vault, uint16 rewardRate) external onlyAdminOrDAO {

143:     function setDittoShorterRate(uint256 vault, uint16 rewardRate) external onlyAdminOrDAO {

152:     function setInitialCR(address asset, uint16 value) external onlyAdminOrDAO {

157:     function setLiquidationCR(address asset, uint16 value) external onlyAdminOrDAO {

163:     function setForcedBidPriceBuffer(address asset, uint8 value) external onlyAdminOrDAO {

168:     function setPenaltyCR(address asset, uint8 value) external onlyAdminOrDAO {

173:     function setTappFeePct(address asset, uint8 value) external onlyAdminOrDAO {

178:     function setCallerFeePct(address asset, uint8 value) external onlyAdminOrDAO {

183:     function setMinBidEth(address asset, uint8 value) external onlyAdminOrDAO {

188:     function setMinAskEth(address asset, uint8 value) external onlyAdminOrDAO {

193:     function setMinShortErc(address asset, uint16 value) external onlyAdminOrDAO {

198:     function setRecoveryCR(address asset, uint8 value) external onlyAdminOrDAO {

203:     function setDiscountPenaltyFee(address asset, uint16 value) external onlyAdminOrDAO {

208:     function setDiscountMultiplier(address asset, uint16 value) external onlyAdminOrDAO {

213:     function setYieldVault(address asset, address vault) external onlyAdminOrDAO {

218:     function createBridge(address bridge, uint256 vault, uint16 withdrawalFee) external onlyDAO {

229:     function setWithdrawalFee(address bridge, uint16 withdrawalFee) external onlyAdminOrDAO {

234:     function _setAssetOracle(address asset, address oracle) private {

239:     function _setTithe(uint256 vault, uint16 dethTithePercent) private {

245:     function _setDittoMatchedRate(uint256 vault, uint16 rewardRate) private {

250:     function _setDittoShorterRate(uint256 vault, uint16 rewardRate) private {

255:     function _setInitialCR(address asset, uint16 value) private {

261:     function _setLiquidationCR(address asset, uint16 value) private {

267:     function _setForcedBidPriceBuffer(address asset, uint8 value) private {

273:     function _setPenaltyCR(address asset, uint8 value) private {

280:     function _setTappFeePct(address asset, uint8 value) private {

286:     function _setCallerFeePct(address asset, uint8 value) private {

292:     function _setMinBidEth(address asset, uint8 value) private {

298:     function _setMinAskEth(address asset, uint8 value) private {

304:     function _setMinShortErc(address asset, uint16 value) private {

310:     function _setWithdrawalFee(address bridge, uint16 withdrawalFee) private {

315:     function _setRecoveryCR(address asset, uint8 value) private {

321:     function _setDiscountPenaltyFee(address asset, uint16 value) private {

327:     function _setDiscountMultiplier(address asset, uint16 value) private {

333:     function _setYieldVault(address asset, address vault) private {

```

```solidity
File: ./facets/PrimaryLiquidationFacet.sol

48:     function liquidate(address asset, address shorter, uint8 id, uint16[] memory shortHintArray, uint16 shortOrderId)

100:     function _checklowestSell(MTypes.PrimaryLiquidation memory m) private view {

125:     function _setLiquidationStruct(address asset, address shorter, uint16 shortOrderId, STypes.ShortRecord storage shortRecord)

158:     function _performForcedBid(MTypes.PrimaryLiquidation memory m, uint16[] memory shortHintArray) private {

220:     function _liquidationFeeHandler(MTypes.PrimaryLiquidation memory m) private {

240:     function min88(uint256 a, uint88 b) private pure returns (uint88) {

251:     function _fullorPartialLiquidation(MTypes.PrimaryLiquidation memory m) private {

```

```solidity
File: ./facets/SecondaryLiquidationFacet.sol

40:     function liquidateSecondary(address asset, MTypes.BatchLiquidation[] memory batches, uint88 liquidateAmount, bool isWallet)

143:     function _setLiquidationStruct(MTypes.BatchLiquidation memory batch, MTypes.AssetParams memory a)

173:     function _secondaryLiquidationHelper(MTypes.SecondaryLiquidation memory m, MTypes.AssetParams memory a) private {

191:     function min88(uint256 a, uint88 b) private pure returns (uint88) {

196:     function _secondaryLiquidationHelperPartialTapp(MTypes.SecondaryLiquidation memory m, MTypes.AssetParams memory a) private {

```

```solidity
File: ./facets/ShortRecordFacet.sol

40:     function increaseCollateral(address asset, uint8 id, uint88 amount)

83:     function decreaseCollateral(address asset, uint8 id, uint88 amount)

116:     function combineShorts(address asset, uint8[] memory ids, uint16[] memory shortOrderIds)

```

```solidity
File: ./facets/YieldFacet.sol

42:     function updateYield(uint256 vault) external nonReentrant {

48:     function _updateYieldDiamond(uint256 vault) external onlyDiamond {

59:     function distributeYield(address[] calldata assets) external nonReentrant {

83:     function _distributeYield(address asset, uint256 protocolTime)

129:     function _claimYield(uint256 vault, uint88 yield, uint256 dittoYieldShares, uint256 protocolTime) private {

150:     function claimDittoMatchedReward(uint256 vault) external nonReentrant {

185:     function withdrawDittoReward(uint256 vault) external nonReentrant {

```

```solidity
File: ./libraries/LibAsset.sol

17:     function burnMsgSenderDebt(address asset, uint88 debt) internal {

25:     function getAssetCollateralRatio(STypes.Asset storage Asset, uint256 oraclePrice) internal view returns (uint256 assetCR) {

34:     function initialCR(STypes.Asset storage Asset) internal view returns (uint256) {

44:     function liquidationCR(address asset) internal view returns (uint256) {

55:     function forcedBidPriceBuffer(address asset) internal view returns (uint256) {

65:     function penaltyCR(address asset) internal view returns (uint256) {

75:     function tappFeePct(address asset) internal view returns (uint256) {

85:     function callerFeePct(address asset) internal view returns (uint256) {

95:     function minBidEth(address asset) internal view returns (uint256) {

105:     function minAskEth(STypes.Asset storage Asset) internal view returns (uint256) {

113:     function minShortErc(STypes.Asset storage Asset) internal view returns (uint256) {

122:     function recoveryCR(STypes.Asset storage Asset) internal view returns (uint256) {

131:     function discountPenaltyFee(STypes.Asset storage Asset) internal view returns (uint256) {

140:     function discountMultiplier(STypes.Asset storage Asset) internal view returns (uint256) {

```

```solidity
File: ./libraries/LibBytes.sol

11:     function readProposalData(address SSTORE2Pointer, uint8 slateLength)

```

```solidity
File: ./libraries/LibOracle.sol

19:     function getOraclePrice(address asset) internal view returns (uint256) {

131:     function twapCircuitBreaker() private view returns (uint256 twapPriceInEth) {

149:     function setPriceAndTime(address asset, uint256 oraclePrice, uint32 oracleTime) internal {

156:     function getTime(address asset) internal view returns (uint256 creationTime) {

162:     function getPrice(address asset) internal view returns (uint80 oraclePrice) {

168:     function getSavedOrSpotOraclePrice(address asset) internal view returns (uint256) {

176:     function validateFetchData(uint80 roundId, uint256 timeStamp, int256 chainlinkPrice)

```

```solidity
File: ./libraries/LibOrders.sol

32:     function getOffsetTime() internal view returns (uint32 timeInSeconds) {

37:     function convertCR(uint16 cr) internal pure returns (uint256) {

42:     function increaseSharesOnMatch(address asset, STypes.Order memory order, MTypes.Match memory matchTotal, uint88 eth) internal {

57:     function currentOrders(mapping(address => mapping(uint16 => STypes.Order)) storage orders, address asset)

80:     function isShort(STypes.Order memory order) internal pure returns (bool) {

84:     function addBid(address asset, STypes.Order memory order, MTypes.OrderHint[] memory orderHintArray) internal {

104:     function addAsk(address asset, STypes.Order memory order, MTypes.OrderHint[] memory orderHintArray) internal {

129:     function addShort(address asset, STypes.Order memory order, MTypes.OrderHint[] memory orderHintArray) internal {

156:     function addSellOrder(STypes.Order memory incomingOrder, address asset, MTypes.OrderHint[] memory orderHintArray) private {

239:     function verifyBidId(address asset, uint16 _prevId, uint256 _newPrice, uint16 _nextId)

296:     function cancelOrder(mapping(address => mapping(uint16 => STypes.Order)) storage orders, address asset, uint16 id) internal {

324:     function matchOrder(mapping(address => mapping(uint16 => STypes.Order)) storage orders, address asset, uint16 id) internal {

433:     function normalizeOrderType(O o) private pure returns (O newO) {

487:     function updateBidOrdersOnMatch(address asset, uint16 id, bool isOrderFullyFilled) internal {

508:     function updateSellOrdersOnMatch(address asset, MTypes.BidMatchAlgo memory b) internal {

647:     function matchIncomingSell(address asset, STypes.Order memory incomingOrder, MTypes.Match memory matchTotal) private {

669:     function matchIncomingAsk(address asset, STypes.Order memory incomingAsk, MTypes.Match memory matchTotal) private {

688:     function matchIncomingShort(address asset, STypes.Order memory incomingShort, MTypes.Match memory matchTotal) private {

759:     function _updateOracleAndStartingShort(address asset, uint256 savedPrice, uint16[] memory shortHintArray) private {

812:     function updateOracleAndStartingShortViaThreshold(

833:     function updateOracleAndStartingShortViaTimeBidOnly(address asset, uint16[] memory shortHintArray) internal {

841:     function updateStartingShortIdViaShort(address asset, STypes.Order memory incomingShort) internal {

896:     function cancelBid(address asset, uint16 id) internal {

910:     function cancelAsk(address asset, uint16 id) internal {

923:     function cancelShort(address asset, uint16 id) internal {

997:     function min(uint256 a, uint256 b) internal pure returns (uint256) {

1001:     function max(uint256 a, uint256 b) internal pure returns (uint256) {

```

```solidity
File: ./libraries/LibPriceDiscount.sol

22:     function handlePriceDiscount(address asset, uint256 price, uint256 ercAmount) internal {

```

```solidity
File: ./libraries/LibRedemption.sol

21:     function validRedemptionSR(STypes.ShortRecord storage shortRecord, address proposer, address shorter, uint256 minShortErc)

37:     function calculateNewBaseRate(STypes.Asset storage Asset, uint88 ercDebtRedeemed) internal view returns (uint256 newBaseRate) {

50:     function calculateRedemptionFee(uint64 baseRate, uint88 colRedeemed) internal pure returns (uint88 redemptionFee) {

55:     function calculateTimeToDispute(uint256 lastCR, uint32 protocolTime) internal pure returns (uint32 timeToDispute) {

```

```solidity
File: ./libraries/LibSRUtil.sol

22:     function disburseCollateral(address asset, address shorter, uint88 collateral, uint256 dethYieldRate, uint32 updatedAt)

49:     function invalidShortOrder(STypes.Order storage shortOrder, uint8 shortRecordId, address shorter)

59:     function checkCancelShortOrder(address asset, SR initialStatus, uint16 shortOrderId, uint8 shortRecordId, address shorter)

72:     function checkShortMinErc(address asset, SR initialStatus, uint16 shortOrderId, uint8 shortRecordId, address shorter)

103:     function checkRecoveryModeViolation(STypes.Asset storage Asset, uint256 shortRecordCR, uint256 oraclePrice)

123:     function updateErcDebt(STypes.ShortRecord storage short, address asset) internal {

131:     function updateErcDebt(STypes.ShortRecord storage short, uint80 ercDebtRate) internal {

142:     function onlyValidShortRecord(address asset, address shorter, uint8 id)

152:     function reduceErcDebtFee(STypes.Asset storage Asset, STypes.ShortRecord storage short, uint256 ercDebtReduction) internal {

```

```solidity
File: ./libraries/LibShortRecord.sol

23:     function getCollateralRatio(STypes.ShortRecord memory short, uint256 oraclePrice) internal pure returns (uint256 cRatio) {

35:     function getShortRecordCount(address asset, address shorter) internal view returns (uint256 shortRecordCount) {

120:     function deleteShortRecord(address asset, address shorter, uint8 id) internal {

164:     function setShortRecordIds(address asset, address shorter) private returns (uint8 id, uint8 nextId) {

```

```solidity
File: ./libraries/LibVault.sol

23:     function dethTithePercent(uint256 vault) internal view returns (uint256) {

34:     function dittoShorterRate(uint256 vault) internal view returns (uint256) {

44:     function dittoMatchedRate(uint256 vault) internal view returns (uint256) {

50:     function getDethTotal(uint256 vault) internal view returns (uint256 dethTotal) {

```

```solidity
File: ./tokens/yDUSD.sol

43:     function proposeWithdraw(uint104 amountProposed) public {

66:     function deposit(uint256 assets, address receiver) public override returns (uint256) {

84:     function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256) {

123:     function getTimeProposed(address account) external view returns (uint40) {

127:     function getAmountProposed(address account) external view returns (uint104) {

132:     function mint(uint256 shares, address receiver) public override returns (uint256) {

136:     function redeem(uint256 shares, address receiver, address owner) public override returns (uint256) {

```

### <a name="NC-7"></a>[NC-7] Change int to int256
Throughout the code base, some variables are declared as `int`. To favor explicitness, consider changing all instances of `int` to `int256`

*Instances (4)*:
```solidity
File: ./facets/BidOrdersFacet.sol

392:         Here, (ID1) becomes the "First ID" and the shortHint ID [ID5] was the "LastID"

```

```solidity
File: ./libraries/DataTypes.sol

183:     struct OrderHint {

```

```solidity
File: ./libraries/LibOrders.sol

869:             MTypes.OrderHint memory orderHint = orderHintArray[i];

```

```solidity
File: ./libraries/LibRedemption.sol

73:         b = last fixed point (Y)

```

### <a name="NC-8"></a>[NC-8] Lines are too long
Usually lines in source code are limited to [80](https://softwareengineering.stackexchange.com/questions/148677/why-is-80-characters-the-standard-limit-for-code-width) characters. Today's screens are much larger so it's reasonable to stretch this in some cases. Since the files will most likely reside in GitHub, and GitHub starts using a scroll bar in all cases when the length is over [164](https://github.com/aizatto/character-length) characters, the lines below should be split when they reach that length

*Instances (1)*:
```solidity
File: ./facets/PrimaryLiquidationFacet.sol

144:             m.ethDebt = m.short.ercDebt.mul(m.oraclePrice).mul(m.forcedBidPriceBuffer).mul(1 ether + m.tappFeePct + m.callerFeePct); // ethDebt accounts for forcedBidPriceBuffer and potential fees

```

### <a name="NC-9"></a>[NC-9] Use a `modifier` instead of a `require/if` statement for a special `msg.sender` actor
If a function is supposed to be access-controlled, a `modifier` should be used instead of a `require/if` statement for more readability.

*Instances (12)*:
```solidity
File: ./facets/ClaimRedemptionFacet.sol

71:         if (claimProposal.shorter != msg.sender || claimProposal.shortId != id) revert Errors.CanOnlyClaimYourShort();

```

```solidity
File: ./facets/DisputeRedemptionFacet.sol

36:         if (redeemer == msg.sender) revert Errors.CannotDisputeYourself();

```

```solidity
File: ./facets/OrdersFacet.sol

32:         if (msg.sender != bid.addr) revert Errors.NotOwner();

45:         if (msg.sender != ask.addr) revert Errors.NotOwner();

58:         if (msg.sender != short.addr) revert Errors.NotOwner();

```

```solidity
File: ./facets/OwnerFacet.sol

112:         if (s.ownerCandidate != msg.sender) revert Errors.NotOwnerCandidate();

```

```solidity
File: ./facets/PrimaryLiquidationFacet.sol

55:         if (msg.sender == shorter) revert Errors.CannotLiquidateSelf();

```

```solidity
File: ./facets/ProposeRedemptionFacet.sol

66:             if (!LibRedemption.validRedemptionSR(currentSR, msg.sender, p.shorter, minShortErc)) continue;

```

```solidity
File: ./facets/SecondaryLiquidationFacet.sol

99:                 assert(tokenContract.balanceOf(msg.sender) < walletBalance);

```

```solidity
File: ./libraries/LibAsset.sol

22:         assert(tokenContract.balanceOf(msg.sender) < walletBalance);

```

```solidity
File: ./libraries/LibSRUtil.sol

96:                 if (shorter != msg.sender && shortOrder.shortOrderCR < Asset.initialCR) revert Errors.CannotLeaveDustAmount();

```

```solidity
File: ./tokens/yDUSD.sol

49:         if (amountProposed > maxWithdraw(msg.sender)) revert Errors.ERC4626WithdrawMoreThanMax();

```

### <a name="NC-10"></a>[NC-10] Consider using named mappings
Consider moving to solidity version 0.8.18 or later, and using [named mappings](https://ethereum.stackexchange.com/questions/51629/how-to-name-the-arguments-in-mapping/145555#145555) to make it easier to understand the purpose of each mapping

*Instances (12)*:
```solidity
File: ./facets/OrdersFacet.sol

22:     using LibOrders for mapping(address => mapping(uint16 => STypes.Order));

```

```solidity
File: ./libraries/LibOrders.sol

57:     function currentOrders(mapping(address => mapping(uint16 => STypes.Order)) storage orders, address asset)

177:         mapping(address => mapping(uint16 => STypes.Order)) storage orders,

269:         mapping(address => mapping(uint16 => STypes.Order)) storage orders,

296:     function cancelOrder(mapping(address => mapping(uint16 => STypes.Order)) storage orders, address asset, uint16 id) internal {

324:     function matchOrder(mapping(address => mapping(uint16 => STypes.Order)) storage orders, address asset, uint16 id) internal {

331:         mapping(address => mapping(uint16 => STypes.Order)) storage orders,

374:         mapping(address => mapping(uint16 => STypes.Order)) storage orders,

416:         mapping(address => mapping(uint16 => STypes.Order)) storage orders,

454:         mapping(address => mapping(uint16 => STypes.Order)) storage orders,

542:         mapping(address => mapping(uint16 => STypes.Order)) storage orders,

860:         mapping(address => mapping(uint16 => STypes.Order)) storage orders,

```

### <a name="NC-11"></a>[NC-11] Take advantage of Custom Error's return value property
An important feature of Custom Error is that values such as address, tokenID, msg.value can be written inside the () sign, this kind of approach provides a serious advantage in debugging and examining the revert details of dapps such as tenderly.

*Instances (110)*:
```solidity
File: ./facets/BidOrdersFacet.sol

90:         if (eth < LibAsset.minBidEth(asset)) revert Errors.OrderUnderMinimumSize();

93:         if (s.vaultUser[Asset.vault][sender].ethEscrowed < eth) revert Errors.InsufficientETHEscrowed();

```

```solidity
File: ./facets/BridgeRouterFacet.sol

64:         if (amount < C.MIN_DEPOSIT) revert Errors.UnderMinimumDeposit();

83:         if (msg.value < C.MIN_DEPOSIT) revert Errors.UnderMinimumDeposit();

102:         if (dethAmount == 0) revert Errors.ParameterIsZero();

134:         if (dethAmount == 0) revert Errors.ParameterIsZero();

164:             if (vault == 0) revert Errors.InvalidBridge();

```

```solidity
File: ./facets/ClaimRedemptionFacet.sol

32:         if (redeemerAssetUser.SSTORE2Pointer == address(0)) revert Errors.InvalidRedemption();

37:         if (LibOrders.getOffsetTime() < timeToDispute) revert Errors.TimeToDisputeHasNotElapsed();

62:         if (redeemerAssetUser.SSTORE2Pointer == address(0)) revert Errors.InvalidRedemption();

68:         if (timeToDispute > LibOrders.getOffsetTime()) revert Errors.TimeToDisputeHasNotElapsed();

71:         if (claimProposal.shorter != msg.sender || claimProposal.shortId != id) revert Errors.CanOnlyClaimYourShort();

```

```solidity
File: ./facets/DisputeRedemptionFacet.sol

36:         if (redeemer == msg.sender) revert Errors.CannotDisputeYourself();

43:         if (redeemerAssetUser.SSTORE2Pointer == address(0)) revert Errors.InvalidRedemption();

48:         if (d.protocolTime >= d.timeToDispute) revert Errors.TimeToDisputeHasElapsed();

52:                 revert Errors.CannotDisputeWithRedeemerProposal();

62:             revert Errors.InvalidRedemption();

76:                     if (d.disputeCR < prevProposal.CR) revert Errors.NotLowestIncorrectIndex();

157:                 revert Errors.InvalidRedemptionDispute();

160:             revert Errors.DisputeSRUpdatedNearProposalTime();

```

```solidity
File: ./facets/ExitShortFacet.sol

54:         if (buybackAmount > ercDebt || buybackAmount == 0) revert Errors.InvalidBuyback();

103:         if (buybackAmount == 0 || buybackAmount > ercDebt) revert Errors.InvalidBuyback();

107:             if (AssetUser.ercEscrowed < buybackAmount) revert Errors.InsufficientERCEscrowed();

181:         if (e.buybackAmount == 0 || e.buybackAmount > e.ercDebt) revert Errors.InvalidBuyback();

185:             if (ethAmount > e.collateral) revert Errors.InsufficientCollateral();

196:         if (e.ethFilled == 0) revert Errors.ExitShortPriceTooLow();

213:             if (short.ercDebt < LibAsset.minShortErc(Asset)) revert Errors.CannotLeaveDustAmount();

216:             if (getCollateralRatioNonPrice(short) < e.beforeExitCR) revert Errors.PostExitCRLtPreExitCR();

```

```solidity
File: ./facets/MarketShutdownFacet.sol

36:             revert Errors.SufficientCollateral();

```

```solidity
File: ./facets/OrdersFacet.sol

32:         if (msg.sender != bid.addr) revert Errors.NotOwner();

45:         if (msg.sender != ask.addr) revert Errors.NotOwner();

58:         if (msg.sender != short.addr) revert Errors.NotOwner();

59:         if (short.orderType != O.LimitShort) revert Errors.NotActiveOrder();

77:         if (s.asset[asset].orderIdCounter < 65000) revert Errors.OrderIdCountTooLow();

79:         if (numOrdersToCancel > 1000) revert Errors.CannotCancelMoreThan1000Orders();

88:             revert Errors.NotLastOrder();

```

```solidity
File: ./facets/OwnerFacet.sol

47:         if (Asset.orderIdCounter != 0) revert Errors.MarketAlreadyCreated();

112:         if (s.ownerCandidate != msg.sender) revert Errors.NotOwnerCandidate();

124:         if (s.dethVault[deth] != 0) revert Errors.VaultAlreadyCreated();

219:         if (vault == 0) revert Errors.InvalidVault();

221:         if (Bridge.vault != 0) revert Errors.BridgeAlreadyCreated();

235:         if (asset == address(0) || oracle == address(0)) revert Errors.ParameterIsZero();

240:         if (dethTithePercent > 33_33) revert Errors.InvalidTithe();

```

```solidity
File: ./facets/PrimaryLiquidationFacet.sol

55:         if (msg.sender == shorter) revert Errors.CannotLiquidateSelf();

57:         if (shortHintArray.length > 10) revert Errors.TooManyHints();

78:                 revert Errors.SufficientCollateral();

113:             revert Errors.NoSells();

180:                 revert Errors.CannotSocializeDebt();

241:         if (a > type(uint88).max) revert Errors.InvalidAmount();

```

```solidity
File: ./facets/ProposeRedemptionFacet.sol

41:         if (proposalInput.length > type(uint8).max) revert Errors.TooManyProposals();

48:         if (redemptionAmount < minShortErc) revert Errors.RedemptionUnderMinShortErc();

49:         if (redeemerAssetUser.ercEscrowed < redemptionAmount) revert Errors.InsufficientERCEscrowed();

51:         if (redeemerAssetUser.SSTORE2Pointer != address(0)) revert Errors.ExistingProposedRedemptions();

133:         if (p.totalAmountProposed < minShortErc) revert Errors.RedemptionUnderMinShortErc();

158:         if (redemptionFee > maxRedemptionFee) revert Errors.RedemptionFeeTooHigh();

161:         if (VaultUser.ethEscrowed < redemptionFee) revert Errors.InsufficientETHEscrowed();

```

```solidity
File: ./facets/SecondaryLiquidationFacet.sol

125:         if (liquidateAmount == liquidateAmountLeft) revert Errors.SecondaryLiquidationNoValidShorts();

192:         if (a > type(uint88).max) revert Errors.InvalidAmount();

```

```solidity
File: ./facets/ShortOrdersFacet.sol

47:         if (p.CR + C.BID_CR < p.initialCR || p.CR >= C.CRATIO_MAX_INITIAL) revert Errors.InvalidCR();

52:         if (ercAmount < p.minShortErc || p.eth < p.minAskEth) revert Errors.OrderUnderMinimumSize();

61:             if (vaultUser.ethEscrowed < p.eth.mul(p.CR) + p.ethInitial) revert Errors.InsufficientETHEscrowed();

65:             revert Errors.InsufficientETHEscrowed();

86:         if (LibSRUtil.checkRecoveryModeViolation(Asset, p.CR, p.oraclePrice)) revert Errors.BelowRecoveryModeCR();

```

```solidity
File: ./facets/ShortRecordFacet.sol

50:         if (VaultUser.ethEscrowed < amount) revert Errors.InsufficientETHEscrowed();

66:         if (cRatio >= C.CRATIO_MAX) revert Errors.CollateralHigherThanMax();

91:         if (amount > short.collateral) revert Errors.InsufficientCollateral();

98:         if (cRatio < LibAsset.initialCR(Asset)) revert Errors.CRLowerThanMin();

99:         if (LibSRUtil.checkRecoveryModeViolation(Asset, cRatio, oraclePrice)) revert Errors.BelowRecoveryModeCR();

122:         if (shortOrderIds.length != ids.length) revert Errors.InvalidNumberOfShortOrderIds();

124:         if (ids.length < 2) revert Errors.InsufficientNumberOfShorts();

155:         if (firstShort.status == SR.Closed) revert Errors.FirstShortDeleted();

164:             revert Errors.CombinedShortBelowCRThreshold();

167:         if (cRatio >= C.CRATIO_MAX) revert Errors.CollateralHigherThanMax();

```

```solidity
File: ./facets/YieldFacet.sol

69:             if (s.asset[assets[i]].vault != vault) revert Errors.DifferentVaults();

133:         if (yield <= 1) revert Errors.NoYield();

156:         if (shares <= 1) revert Errors.NoShares();

172:         if ((totalReward - userReward) > type(uint96).max) revert Errors.InvalidAmount();

189:         if (amt <= 1) revert Errors.NoDittoReward();

```

```solidity
File: ./libraries/LibAsset.sol

20:         if (walletBalance < debt) revert Errors.InsufficientWalletBalance();

```

```solidity
File: ./libraries/LibOracle.sol

23:         if (address(oracle) == address(0)) revert Errors.InvalidAsset();

58:                 if (validateFetchData(roundID, timeStamp, price)) revert Errors.InvalidPrice();

128:         if (invalidFetchData || invalidFetchDataBase) revert Errors.InvalidPrice();

134:         if (twapPrice == 0) revert Errors.InvalidTwapPrice();

139:         if (wethBal < 100 ether) revert Errors.InsufficientEthInLiquidityPool();

```

```solidity
File: ./libraries/LibOrders.sol

700:             if (matchTotal.fillErc < LibAsset.minShortErc(Asset)) revert Errors.ShortRecordFullyFilledUnderMinSize();

807:             revert Errors.BadShortHint();

892:         revert Errors.BadHintIdArray();

901:         if (orderType == O.Cancelled || orderType == O.Matched) revert Errors.NotActiveOrder();

915:         if (orderType == O.Cancelled || orderType == O.Matched) revert Errors.NotActiveOrder();

```

```solidity
File: ./libraries/LibSRUtil.sol

66:             if (invalidShortOrder(shortOrder, shortRecordId, shorter)) revert Errors.InvalidShortOrder();

84:             if (invalidShortOrder(shortOrder, shortRecordId, shorter)) revert Errors.InvalidShortOrder();

94:                 if (shortOrder.ercAmount + shortRecord.ercDebt < minShortErc) revert Errors.CannotLeaveDustAmount();

96:                 if (shorter != msg.sender && shortOrder.shortOrderCR < Asset.initialCR) revert Errors.CannotLeaveDustAmount();

99:             revert Errors.CannotLeaveDustAmount();

149:         if (shortRecord.status == SR.Closed || shortRecord.ercDebt == 0) revert Errors.InvalidShortId();

```

```solidity
File: ./libraries/LibShortRecord.sol

206:                 revert Errors.CannotMakeMoreThanMaxSR();

```

```solidity
File: ./tokens/yDUSD.sol

40:         if (isDiscounted || WithinDiscountWindow) revert Errors.ERC4626CannotWithdrawBeforeDiscountWindowExpires();

44:         if (amountProposed <= 1) revert Errors.ERC4626AmountProposedTooLow();

47:         if (withdrawal.timeProposed > 0) revert Errors.ERC4626ExistingWithdrawalProposal();

49:         if (amountProposed > maxWithdraw(msg.sender)) revert Errors.ERC4626WithdrawMoreThanMax();

60:         if (withdrawal.timeProposed == 0 && withdrawal.amountProposed <= 1) revert Errors.ERC4626ProposeWithdrawFirst();

67:         if (assets > maxDeposit(receiver)) revert Errors.ERC4626DepositMoreThanMax();

77:         if (newBalance < slippage.mul(shares) + oldBalance) revert Errors.ERC4626DepositSlippageExceeded();

89:         if (timeProposed == 0 && amountProposed <= 1) revert Errors.ERC4626ProposeWithdrawFirst();

91:         if (timeProposed + C.WITHDRAW_WAIT_TIME > uint40(block.timestamp)) revert Errors.ERC4626WaitLongerBeforeWithdrawing();

96:             revert Errors.ERC4626MaxWithdrawTimeHasElapsed();

99:         if (amountProposed > maxWithdraw(owner)) revert Errors.ERC4626WithdrawMoreThanMax();

112:         if (newBalance < slippage.mul(amountProposed) + oldBalance) revert Errors.ERC4626WithdrawSlippageExceeded();

133:         revert Errors.ERC4626CannotMint();

137:         revert Errors.ERC4626CannotRedeem();

```

### <a name="NC-12"></a>[NC-12] Use scientific notation (e.g. `1e18`) rather than exponentiation (e.g. `10**18`)
While this won't save gas in the recent solidity versions, this is shorter and more readable (this is especially true in calculations).

*Instances (3)*:
```solidity
File: ./libraries/DataTypes.sol

96:         uint8 minBidEth; // 10 -> (1 * 10**18 / 10**2) = 0.1 ether

97:         uint8 minAskEth; // 10 -> (1 * 10**18 / 10**2) = 0.1 ether

98:         uint16 minShortErc; // 2000 -> (2000 * 10**18) -> 2000 ether

```

### <a name="NC-13"></a>[NC-13] Use Underscores for Number Literals (add an underscore every 3 digits)

*Instances (8)*:
```solidity
File: ./facets/OrdersFacet.sol

77:         if (s.asset[asset].orderIdCounter < 65000) revert Errors.OrderIdCountTooLow();

79:         if (numOrdersToCancel > 1000) revert Errors.CannotCancelMoreThan1000Orders();

144:         uint32 timeDiff = (protocolTime - Asset.initialDiscountTime) / 86400 seconds;

```

```solidity
File: ./facets/OwnerFacet.sol

80:         _setMinShortErc(asset, a.minShortErc); // 2000 -> 2000 ether

83:         _setDiscountMultiplier(asset, a.discountMultiplier); // 10000 -> 10 ether (10x)

323:         require(value <= 1000, "above 10.0%");

329:         require(value < type(uint16).max, "above 65534");

```

```solidity
File: ./libraries/DataTypes.sol

98:         uint16 minShortErc; // 2000 -> (2000 * 10**18) -> 2000 ether

```

### <a name="NC-14"></a>[NC-14] Constants should be defined rather than using magic numbers

*Instances (12)*:
```solidity
File: ./libraries/DataTypes.sol

98:         uint16 minShortErc; // 2000 -> (2000 * 10**18) -> 2000 ether

```

```solidity
File: ./libraries/LibBytes.sol

42:                 shorter := shr(96, fullWord) // 0x60 = 96 (256-160)

44:                 shortId := and(0xff, shr(88, fullWord)) // 0x58 = 88 (96-8), mask of bytes1 = 0xff * 1

46:                 CR := and(0xffffffffffffffff, shr(24, fullWord)) // 0x18 = 24 (88-64), mask of bytes8 = 0xff * 8

48:                 fullWord := mload(add(slate, add(offset, 29))) // (29 offset)

50:                 ercDebtRedeemed := shr(168, fullWord) // (256-88 = 168)

52:                 colRedeemed := and(0xffffffffffffffffffffff, shr(80, fullWord)) // (256-88-88 = 80), mask of bytes11 = 0xff * 11

54:                 fullWord := mload(add(slate, add(offset, 51))) // (51 offset)

56:                 ercDebtFee := shr(168, fullWord) // (256-88 = 168)

77:             timeProposed := shr(224, fullWord) //256 - 32

79:             timeToDispute := and(0xffffffff, shr(192, fullWord)) //224 - 32, mask of bytes4 = 0xff * 4

81:             oraclePrice := and(0xffffffffffffffffffff, shr(112, fullWord)) //192 - 80, mask of bytes4 = 0xff * 10

```

### <a name="NC-15"></a>[NC-15] Variables need not be initialized to zero
The default value for variables is zero, so initializing them to zero is superfluous.

*Instances (6)*:
```solidity
File: ./facets/ClaimRedemptionFacet.sol

40:         for (uint256 i = 0; i < decodedProposalData.length; i++) {

```

```solidity
File: ./facets/DisputeRedemptionFacet.sol

50:         for (uint256 i = 0; i < d.decodedProposalData.length; i++) {

```

```solidity
File: ./facets/ProposeRedemptionFacet.sol

58:         for (uint8 i = 0; i < proposalInput.length; i++) {

```

```solidity
File: ./libraries/LibBytes.sol

25:         for (uint256 i = 0; i < slateLength; i++) {

```

```solidity
File: ./libraries/LibOrders.sol

73:         for (uint256 i = 0; i < size; i++) {

773:             for (uint256 i = 0; i < shortHintArray.length;) {

```


## Low Issues


| |Issue|Instances|
|-|:-|:-:|
| [L-1](#L-1) | Division by zero not prevented | 17 |
| [L-2](#L-2) | External call recipient may consume all transaction gas | 7 |
| [L-3](#L-3) | Signature use at deadlines should be allowed | 1 |
| [L-4](#L-4) | Loss of precision | 17 |
| [L-5](#L-5) | Use `Ownable2Step.transferOwnership` instead of `Ownable.transferOwnership` | 1 |
| [L-6](#L-6) | Upgradeable contract not initialized | 1 |
### <a name="L-1"></a>[L-1] Division by zero not prevented
The divisions below take an input parameter which does not have any zero-value checks, which may lead to the functions reverting when zero is passed.

*Instances (17)*:
```solidity
File: ./libraries/LibAsset.sol

35:         return (uint256(Asset.initialCR) * 1 ether) / C.TWO_DECIMAL_PLACES;

46:         return (uint256(s.asset[asset].liquidationCR) * 1 ether) / C.TWO_DECIMAL_PLACES;

57:         return (uint256(s.asset[asset].forcedBidPriceBuffer) * 1 ether) / C.TWO_DECIMAL_PLACES;

67:         return (uint256(s.asset[asset].penaltyCR) * 1 ether) / C.TWO_DECIMAL_PLACES;

77:         return (uint256(s.asset[asset].tappFeePct) * 1 ether) / C.THREE_DECIMAL_PLACES;

87:         return (uint256(s.asset[asset].callerFeePct) * 1 ether) / C.THREE_DECIMAL_PLACES;

97:         return (uint256(s.asset[asset].minBidEth) * 1 ether) / C.TWO_DECIMAL_PLACES;

106:         return (uint256(Asset.minAskEth) * 1 ether) / C.TWO_DECIMAL_PLACES;

123:         return (uint256(Asset.recoveryCR) * 1 ether) / C.TWO_DECIMAL_PLACES;

132:         return (uint256(Asset.discountPenaltyFee) * 1 ether) / C.FOUR_DECIMAL_PLACES;

141:         return (uint256(Asset.discountMultiplier) * 1 ether) / C.THREE_DECIMAL_PLACES;

```

```solidity
File: ./libraries/LibOracle.sol

93:                 uint256 twapPriceNormalized = twapPrice * (1 ether / C.DECIMAL_USDC);

141:         uint256 twapPriceNormalized = twapPrice * (1 ether / C.DECIMAL_USDC);

```

```solidity
File: ./libraries/LibOrders.sol

38:         return (uint256(cr) * 1 ether) / C.TWO_DECIMAL_PLACES;

```

```solidity
File: ./libraries/LibVault.sol

26:         return (uint256(s.vault[vault].dethTithePercent) * 1 ether) / C.FOUR_DECIMAL_PLACES;

36:         return (uint256(s.vault[vault].dittoShorterRate) * 1 ether) / C.TWO_DECIMAL_PLACES;

46:         return (uint256(s.vault[vault].dittoMatchedRate) * 1 ether) / C.TWO_DECIMAL_PLACES;

```

### <a name="L-2"></a>[L-2] External call recipient may consume all transaction gas
There is no limit specified on the amount of gas used, so the recipient can use up all of the transaction's gas, causing it to revert. Use `addr.call{gas: <amount>}("")` or [this](https://github.com/nomad-xyz/ExcessivelySafeCall) library instead.

*Instances (7)*:
```solidity
File: ./facets/DisputeRedemptionFacet.sol

138:                         LibOrders.max(LibAsset.callerFeePct(d.asset), (currentProposal.CR - d.disputeCR).div(currentProposal.CR)),

```

```solidity
File: ./facets/OwnerFacet.sol

77:         _setCallerFeePct(asset, a.callerFeePct); // 5 -> .005 ether

289:         s.asset[asset].callerFeePct = value;

```

```solidity
File: ./facets/PrimaryLiquidationFacet.sol

142:             m.callerFeePct = LibAsset.callerFeePct(asset);

144:             m.ethDebt = m.short.ercDebt.mul(m.oraclePrice).mul(m.forcedBidPriceBuffer).mul(1 ether + m.tappFeePct + m.callerFeePct); // ethDebt accounts for forcedBidPriceBuffer and potential fees

186:             m.short.ercDebt = uint88(m.ethDebt.div(_bidPrice.mul(1 ether + m.callerFeePct + m.tappFeePct))); // @dev(safe-cast)

```

```solidity
File: ./libraries/LibAsset.sol

87:         return (uint256(s.asset[asset].callerFeePct) * 1 ether) / C.THREE_DECIMAL_PLACES;

```

### <a name="L-3"></a>[L-3] Signature use at deadlines should be allowed
According to [EIP-2612](https://github.com/ethereum/EIPs/blob/71dc97318013bf2ac572ab63fab530ac9ef419ca/EIPS/eip-2612.md?plain=1#L58), signatures used on exactly the deadline timestamp are supposed to be allowed. While the signature may or may not be used for the exact EIP-2612 use case (transfer approvals), for consistency's sake, all deadlines should follow this semantic. If the timestamp is an expiration rather than a deadline, consider whether it makes more sense to include the expiration timestamp as a valid timestamp, as is done for deadlines.

*Instances (1)*:
```solidity
File: ./libraries/LibOracle.sol

181:         invalidFetchData = roundId == 0 || timeStamp == 0 || timeStamp > block.timestamp || chainlinkPrice <= 0;

```

### <a name="L-4"></a>[L-4] Loss of precision
Division by large numbers may result in the result being zero, due to solidity not supporting fractions. Consider requiring a minimum amount for the numerator to ensure that it is always larger than the denominator

*Instances (17)*:
```solidity
File: ./libraries/LibAsset.sol

35:         return (uint256(Asset.initialCR) * 1 ether) / C.TWO_DECIMAL_PLACES;

46:         return (uint256(s.asset[asset].liquidationCR) * 1 ether) / C.TWO_DECIMAL_PLACES;

57:         return (uint256(s.asset[asset].forcedBidPriceBuffer) * 1 ether) / C.TWO_DECIMAL_PLACES;

67:         return (uint256(s.asset[asset].penaltyCR) * 1 ether) / C.TWO_DECIMAL_PLACES;

77:         return (uint256(s.asset[asset].tappFeePct) * 1 ether) / C.THREE_DECIMAL_PLACES;

87:         return (uint256(s.asset[asset].callerFeePct) * 1 ether) / C.THREE_DECIMAL_PLACES;

97:         return (uint256(s.asset[asset].minBidEth) * 1 ether) / C.TWO_DECIMAL_PLACES;

106:         return (uint256(Asset.minAskEth) * 1 ether) / C.TWO_DECIMAL_PLACES;

123:         return (uint256(Asset.recoveryCR) * 1 ether) / C.TWO_DECIMAL_PLACES;

132:         return (uint256(Asset.discountPenaltyFee) * 1 ether) / C.FOUR_DECIMAL_PLACES;

141:         return (uint256(Asset.discountMultiplier) * 1 ether) / C.THREE_DECIMAL_PLACES;

```

```solidity
File: ./libraries/LibOracle.sol

93:                 uint256 twapPriceNormalized = twapPrice * (1 ether / C.DECIMAL_USDC);

141:         uint256 twapPriceNormalized = twapPrice * (1 ether / C.DECIMAL_USDC);

```

```solidity
File: ./libraries/LibOrders.sol

38:         return (uint256(cr) * 1 ether) / C.TWO_DECIMAL_PLACES;

```

```solidity
File: ./libraries/LibVault.sol

26:         return (uint256(s.vault[vault].dethTithePercent) * 1 ether) / C.FOUR_DECIMAL_PLACES;

36:         return (uint256(s.vault[vault].dittoShorterRate) * 1 ether) / C.TWO_DECIMAL_PLACES;

46:         return (uint256(s.vault[vault].dittoMatchedRate) * 1 ether) / C.TWO_DECIMAL_PLACES;

```

### <a name="L-5"></a>[L-5] Use `Ownable2Step.transferOwnership` instead of `Ownable.transferOwnership`
Use [Ownable2Step.transferOwnership](https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable2Step.sol) which is safer. Use it as it is more secure due to 2-stage ownership transfer.

**Recommended Mitigation Steps**

Use <a href="https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable2Step.sol">Ownable2Step.sol</a>
  
  ```solidity
      function acceptOwnership() external {
          address sender = _msgSender();
          require(pendingOwner() == sender, "Ownable2Step: caller is not the new owner");
          _transferOwnership(sender);
      }
```

*Instances (1)*:
```solidity
File: ./facets/OwnerFacet.sol

105:     function transferOwnership(address newOwner) external onlyDAO {

```

### <a name="L-6"></a>[L-6] Upgradeable contract not initialized
Upgradeable contracts are initialized via an initializer function rather than by a constructor. Leaving such a contract uninitialized may lead to it being taken over by a malicious user

*Instances (1)*:
```solidity
File: ./libraries/DataTypes.sol

16:     Uninitialized,

```
