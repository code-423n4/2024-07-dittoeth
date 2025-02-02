// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {U256, U88, U80} from "contracts/libraries/PRBMathHelper.sol";

import {IAsset} from "interfaces/IAsset.sol";
import {IyDUSD} from "interfaces/IyDUSD.sol";

import {C, VAULT} from "contracts/libraries/Constants.sol";
import {STypes, MTypes, O, SR} from "contracts/libraries/DataTypes.sol";

import {ConstantsTest} from "test/utils/ConstantsTest.sol";
import {TestTypes} from "test/utils/TestTypes.sol";
import {DeployHelper} from "deploy/DeployHelper.sol";

import {console} from "contracts/libraries/console.sol";

// solhint-disable-next-line max-states-count
contract OBFixture is DeployHelper, ConstantsTest {
    using U256 for uint256;
    using U88 for uint88;
    using U80 for uint80;

    address public randomAddr = makeAddr("random");
    address public receiver = makeAddr("receiver");
    address public sender = makeAddr("sender");
    address public extra = makeAddr("extra");
    address public extra2 = makeAddr("extra2");
    address[] public users = [receiver, sender, extra, extra2];
    address public owner = address(0x71C05a4eA5E9d5b1Ac87Bf962a043f5265d4Bdc8);
    address public noDeposit = makeAddr("noDeposit");

    TestTypes.StorageUser public r = createUserStruct(receiver);
    TestTypes.StorageUser public s = createUserStruct(sender);
    TestTypes.StorageUser public e = createUserStruct(extra);

    //tapp
    TestTypes.StorageUser public t;
    address public tapp; // placeholder - found in deployhelper

    IAsset public token;
    IyDUSD public rebasingToken;
    address public asset;
    uint256 public vault;

    // @dev dev only, don't deploy
    MTypes.OrderHint[] public badOrderHintArray;

    STypes.Order[] public sells;
    uint16[] public shortHintArrayStorage;

    uint16 public initialCR;

    mapping(string name => address _contract) public contracts;

    function setUp() public virtual {
        vm.label(receiver, "receiver");
        vm.label(sender, "sender");
        vm.label(extra, "extra");
        vm.label(owner, "owner");

        // Start
        vm.startPrank(owner, owner);

        skip(C.STARTING_TIME - 1);

        //31337 is chainid for local deployment / obfixture testing
        deployContracts(owner, 31337);
        setFacets(31337);
        postDeploySetup(31337);

        tapp = _diamond;
        t = createUserStruct(tapp);

        //for gas tests
        contracts["reth"] = _reth;
        contracts["steth"] = _steth;
        contracts["deth"] = _deth;
        contracts["bridgeReth"] = _bridgeReth;
        contracts["bridgeSteth"] = _bridgeSteth;
        contracts["dusd"] = _dusd;
        contracts["yDUSD"] = _yDUSD;
        contracts["diamond"] = _diamond;
        contracts["ethAggregator"] = _ethAggregator;
        contracts["ditto"] = _ditto;

        // @dev only testing
        token = dusd;
        rebasingToken = yDUSD;
        asset = _dusd;
        vault = VAULT.ONE;

        vm.stopPrank();

        // @dev prevent the currentTime in tests to equal deployment time
        skip(1 seconds);

        badOrderHintArray.push(MTypes.OrderHint({hintId: 0, creationTime: 123}));

        // @dev Useful for revert test bc can just call storage
        shortHintArrayStorage = setShortHintArray();

        // @dev setting these values to the original values bc I do not want to change all the tests that uses setETH
        vm.startPrank(owner);
        diamond.setWithdrawalFee(_bridgeSteth, 1);
        diamond.setInitialCR(asset, 500);
        diamond.setLiquidationCR(asset, 400);
        diamond.setMinAskEth(asset, 1);
        diamond.setMinBidEth(asset, 1);
        diamond.setDittoShorterRate(vault, 100);
        diamond.setDittoMatchedRate(vault, 100);
        vm.stopPrank();
        initialCR = diamond.getAssetStruct(asset).initialCR;
    }

    function setETH(int256 price) public {
        _setETH(price);
    }

    function setETHChainlinkOnly(int256 price) public {
        _setETHChainlinkOnly(price);
    }

    function createUserStruct(address account) public pure returns (TestTypes.StorageUser memory _s) {
        return TestTypes.StorageUser({addr: account, ethEscrowed: 0, ercEscrowed: 0});
    }

    function getUserStruct(address account) public view returns (TestTypes.StorageUser memory _s) {
        return TestTypes.StorageUser({
            addr: account,
            ethEscrowed: diamond.getVaultUserStruct(vault, account).ethEscrowed,
            ercEscrowed: diamond.getAssetUserStruct(asset, account).ercEscrowed
        });
    }

    function assertEq(O order1, O order2) public pure {
        assertEq(uint8(order1), uint8(order2), "status");
    }

    function assertSR(SR sr1, SR sr2) public pure {
        assertEq(uint8(sr1), uint8(sr2), "status");
    }

    function assertEqShort(STypes.ShortRecord memory a, STypes.ShortRecord memory b) public pure {
        assertEq(uint8(a.status), uint8(b.status), "status");
        assertEq(a.prevId, b.prevId, "prevId");
        assertEq(a.nextId, b.nextId, "nextId");
        assertEq(a.ercDebtRate, b.ercDebtRate, "ercDebtRate");
        assertEq(a.collateral, b.collateral, "collateral");
        assertEq(a.ercDebt, b.ercDebt, "ercDebt");
        assertEq(a.updatedAt, b.updatedAt, "updatedAt");
        assertEq(a.dethYieldRate, b.dethYieldRate, "dethYieldRate");
    }

    function assertStruct(address account, TestTypes.StorageUser memory _ob) public view {
        assertEq(diamond.getVaultUserStruct(vault, account).ethEscrowed, _ob.ethEscrowed, "VaultUser.ethEscrowed");
        assertEq(diamond.getAssetUserStruct(asset, account).ercEscrowed, _ob.ercEscrowed, "AssetUser.ercEscrowed");
    }

    function fundOrder(O orderType, uint80 price, uint88 amount, address account) public {
        if (orderType == O.LimitBid) {
            fundLimitBid(price, amount, account);
        } else if (orderType == O.LimitAsk) {
            fundLimitAsk(price, amount, account);
        } else if (orderType == O.LimitShort) {
            fundLimitShort(price, amount, account);
        } else {
            revert("Invalid OrderType");
        }
    }

    function createBid(
        uint80 price,
        uint88 amount,
        bool market,
        MTypes.OrderHint[] memory _orderHintArray,
        uint16[] memory _shortHintArray,
        address account
    ) public returns (uint256 ethFilled, uint256 ercAmountLeft) {
        vm.prank(account);
        (ethFilled, ercAmountLeft) = diamond.createBid(asset, price, amount, market, _orderHintArray, _shortHintArray);
        return (ethFilled, ercAmountLeft);
    }

    function fundLimitBid(uint80 price, uint88 amount, address account) public returns (uint256 ethFilled, uint256 ercAmountLeft) {
        depositEth(account, price.mulU88(amount));
        badOrderHintArray.push(MTypes.OrderHint({hintId: 0, creationTime: 0}));
        return createBid(price, amount, C.LIMIT_ORDER, badOrderHintArray, shortHintArrayStorage, account);
    }

    function fundLimitBidOpt(uint80 price, uint88 amount, address account)
        public
        returns (uint256 ethFilled, uint256 ercAmountLeft)
    {
        depositEth(account, price.mulU88(amount));
        return limitBidOpt(price, amount, account);
    }

    function limitBidOpt(uint80 price, uint88 amount, address account) public returns (uint256 ethFilled, uint256 ercAmountLeft) {
        MTypes.OrderHint[] memory orderHintArray = diamond.getHintArray(asset, price, O.LimitBid, 1);

        uint16[] memory shortHintArray = setShortHintArray();
        return createBid(price, amount, C.LIMIT_ORDER, orderHintArray, shortHintArray, account);
    }

    function fundMarketBid(uint80 price, uint88 amount, address account)
        public
        returns (uint256 ethFilled, uint256 ercAmountLeft)
    {
        depositEth(account, price.mulU88(amount));
        return createBid(price, amount, C.MARKET_ORDER, badOrderHintArray, shortHintArrayStorage, account);
    }

    function createLimitBid(uint80 price, uint88 amount) public returns (uint256 ethFilled, uint256 ercAmountLeft) {
        return diamond.createBid(asset, price, amount, C.LIMIT_ORDER, badOrderHintArray, shortHintArrayStorage);
    }

    function createAsk(uint80 price, uint88 amount, bool market, MTypes.OrderHint[] memory _orderHintArray, address account)
        public
    {
        vm.prank(account);
        diamond.createAsk(asset, price, amount, market, _orderHintArray);
    }

    function fundLimitAsk(uint80 price, uint88 amount, address account) public {
        depositUsd(account, amount);
        badOrderHintArray.push(MTypes.OrderHint({hintId: 0, creationTime: 0}));
        createAsk(price, amount, C.LIMIT_ORDER, badOrderHintArray, account);
    }

    function fundLimitAskOpt(uint80 price, uint88 amount, address account) public {
        depositUsd(account, amount);
        limitAskOpt(price, amount, account);
    }

    function limitAskOpt(uint80 price, uint88 amount, address account) public returns (uint256 ethFilled, uint256 ercAmountLeft) {
        MTypes.OrderHint[] memory orderHintArray = diamond.getHintArray(asset, price, O.LimitAsk, 1);
        createAsk(price, amount, C.LIMIT_ORDER, orderHintArray, account);
    }

    function fundMarketAsk(uint80 price, uint88 amount, address account) public {
        depositUsd(account, amount);
        createAsk(price, amount, C.MARKET_ORDER, badOrderHintArray, account);
    }

    function createLimitAsk(uint80 price, uint88 amount) public {
        diamond.createAsk(asset, price, amount, C.LIMIT_ORDER, badOrderHintArray);
    }

    function createShort(
        uint80 price,
        uint88 amount,
        MTypes.OrderHint[] memory _orderHintArray,
        uint16[] memory _shortHintArray,
        address account
    ) public {
        vm.prank(account);
        diamond.createLimitShort(asset, price, amount, _orderHintArray, _shortHintArray, initialCR);
    }

    function fundLimitShort(uint80 price, uint88 amount, address account) public {
        depositEth(account, price.mulU88(amount).mulU88(diamond.getAssetNormalizedStruct(asset).initialCR));
        badOrderHintArray.push(MTypes.OrderHint({hintId: 0, creationTime: 0}));
        createShort(price, amount, badOrderHintArray, shortHintArrayStorage, account);
    }

    function fundLimitShortOpt(uint80 price, uint88 amount, address account) public {
        depositEth(account, price.mulU88(amount).mulU88(diamond.getAssetNormalizedStruct(asset).initialCR));
        limitShortOpt(price, amount, account);
    }

    function limitShortOpt(uint80 price, uint88 amount, address account) public returns (uint256 ethFilled) {
        uint16[] memory shortHintArray = setShortHintArray();
        MTypes.OrderHint[] memory orderHintArray = diamond.getHintArray(asset, price, O.LimitShort, 1);
        createShort(price, amount, orderHintArray, shortHintArray, account);
    }

    function createLimitShort(uint80 price, uint88 amount) public {
        diamond.createLimitShort(asset, price, amount, badOrderHintArray, shortHintArrayStorage, initialCR);
    }

    function getShortRecord(address shorter, uint8 id) public view returns (STypes.ShortRecord memory) {
        return diamond.getShortRecord(asset, shorter, id);
    }

    function getShortRecordCount(address shorter) public view returns (uint256) {
        return diamond.getShortRecordCount(asset, shorter);
    }

    function mint(address account, uint88 amount) public {
        token.mint(account, amount);
        //increase ercDebt by amount
        diamond.addErcDebtAsset(asset, amount);
    }

    function depositEth(address account, uint88 amount) public {
        vm.startPrank(account);
        // Fund stETH
        deal(_steth, account, amount);
        // stETH -> dETH
        steth.approve(_bridgeSteth, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        diamond.deposit(_bridgeSteth, amount);
        vm.stopPrank();
    }

    function depositReth(address account, uint88 amount) public {
        vm.startPrank(account);
        // Fund rETH
        deal(_reth, account, amount);
        // rETH -> dETH
        reth.approve(_bridgeReth, 0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
        diamond.deposit(_bridgeReth, amount);
        vm.stopPrank();
    }

    function depositUsd(address account, uint88 amount) public {
        vm.prank(_diamond);
        mint(account, amount);
        vm.prank(account);
        diamond.depositAsset(asset, amount);
    }

    function transferUsd(address from, address to, uint104 amount) public {
        vm.prank(from);
        diamond.withdrawAsset(asset, amount);
        vm.prank(from);
        token.transfer(to, amount);
    }

    function depositEthAndPrank(address account, uint88 amount) public {
        depositEth(account, amount);
        vm.prank(account);
    }

    function depositUsdAndPrank(address account, uint88 amount) public {
        depositUsd(account, amount);
        vm.prank(account);
    }

    function getBids() public view returns (STypes.Order[] memory bids) {
        return diamond.getBids(asset);
    }

    function getAsks() public view returns (STypes.Order[] memory asks) {
        return diamond.getAsks(asset);
    }

    function getShorts() public view returns (STypes.Order[] memory shorts) {
        return diamond.getShorts(asset);
    }

    function increaseCollateral(uint8 id, uint80 amount) public {
        diamond.increaseCollateral(asset, id, amount);
    }

    function decreaseCollateral(uint8 id, uint80 amount) public {
        diamond.decreaseCollateral(asset, id, amount);
    }

    function cancelAsk(uint16 id) public {
        diamond.cancelAsk(asset, id);
    }

    function cancelShort(uint16 id) public {
        diamond.cancelShort(asset, id);
    }

    function cancelBid(uint16 id) public {
        diamond.cancelBid(asset, id);
    }

    function combineShorts(uint8 id1, uint8 id2) public {
        uint8[] memory shortRecordIds = new uint8[](2);
        shortRecordIds[0] = id1;
        shortRecordIds[1] = id2;

        uint16[] memory shortOrderIds = new uint16[](2);
        shortOrderIds[0] = 0;
        shortOrderIds[1] = 0;

        diamond.combineShorts(asset, shortRecordIds, shortOrderIds);
    }

    function exitShort(uint8 id, uint88 amount, uint80 price, address account) public {
        uint16[] memory shortHintArray = setShortHintArray();
        vm.prank(account);
        //No need to deposit since the short's collateral is used to buy back
        diamond.exitShort(asset, id, amount, price, shortHintArray, 0);
    }

    function exitShort(uint8 id, uint88 amount, uint80 price) public {
        //No need to deposit since the short's collateral is used to buy back
        diamond.exitShort(asset, id, amount, price, shortHintArrayStorage, 0);
    }

    function exitShortWallet(uint8 id, uint88 amount, address account) public {
        vm.prank(account);
        //No need to deposit since the short's collateral is used to buy back
        diamond.exitShortWallet(asset, id, amount, 0);
    }

    function exitShortErcEscrowed(uint8 id, uint88 amount, address account) public {
        vm.prank(account);
        //No need to deposit since the short's collateral is used to buy back
        diamond.exitShortErcEscrowed(asset, id, amount, 0);
    }

    function liquidate(address shorter, uint8 id, address account) public returns (uint256 fillEth) {
        uint16[] memory shortHintArray = setShortHintArray();

        vm.prank(account);

        (, fillEth) = diamond.liquidate(asset, shorter, id, shortHintArray, 0);
    }

    function liquidateErcEscrowed(address shorter, uint8 id, uint88 amount, address account) public {
        MTypes.BatchLiquidation[] memory batches = new MTypes.BatchLiquidation[](1);
        batches[0] = MTypes.BatchLiquidation({shorter: shorter, shortId: id, shortOrderId: 0});
        vm.prank(account);
        diamond.liquidateSecondary(asset, batches, amount, false);
    }

    function liquidateWallet(address shorter, uint8 id, uint88 amount, address account) public {
        MTypes.BatchLiquidation[] memory batches = new MTypes.BatchLiquidation[](1);
        batches[0] = MTypes.BatchLiquidation({shorter: shorter, shortId: id, shortOrderId: 0});
        vm.prank(account);
        diamond.liquidateSecondary(asset, batches, amount, true);
    }

    function redeemErc(uint88 amtWallet, uint88 amtEscrow, address account) public {
        vm.prank(account);
        diamond.redeemErc(asset, amtWallet, amtEscrow);
    }

    function min(uint256 a, uint256 b) public pure returns (uint256) {
        return a < b ? a : b;
    }

    function max(uint256 a, uint256 b) public pure returns (uint256) {
        return a > b ? a : b;
    }

    function submitBalances(uint256 _ethSupply, uint256 _rethSupply) public {
        reth.submitBalances(_ethSupply, _rethSupply);
    }

    function getExchangeRate() public view returns (uint256) {
        return reth.getExchangeRate();
    }

    function checkOrdersPriceValidity() public view {
        STypes.Order[] memory bids = getBids();
        for (uint256 i = 1; i < bids.length; i++) {
            assertTrue(bids[i - 1].price >= bids[i].price);
        }

        STypes.Order[] memory asks = getAsks();
        for (uint256 i = 1; i < asks.length; i++) {
            assertTrue(asks[i - 1].price <= asks[i].price);
        }

        STypes.Order[] memory shorts = getShorts();
        for (uint256 i = 1; i < shorts.length; i++) {
            assertTrue(shorts[i - 1].price <= shorts[i].price);
        }
    }

    function getErcInMarket() public view returns (uint256) {
        uint256 sum;
        for (uint256 i = 0; i < getAsks().length; i++) {
            sum += getAsks()[i].ercAmount;
        }
        return sum;
    }

    function getTotalErc() public view returns (uint256) {
        uint256 total;
        total += getErcInMarket();
        total += diamond.getAssetUserStruct(address(token), receiver).ercEscrowed;
        total += diamond.getAssetUserStruct(address(token), sender).ercEscrowed;
        total += diamond.getAssetUserStruct(address(token), extra).ercEscrowed;
        return total;
    }

    function setShortHintArray() public view returns (uint16[] memory) {
        uint16[] memory _shortHintArray = new uint16[](10);

        // @dev these values are basically random.
        // @dev Values 0-3 are guaranteed to be incorrect. 4-8 can sometimes randomly be correct depending on test
        _shortHintArray[0] = 0;
        _shortHintArray[1] = 2391;
        _shortHintArray[2] = 511;
        _shortHintArray[3] = 1;
        _shortHintArray[4] = 100;
        _shortHintArray[5] = 101;
        _shortHintArray[6] = 102;
        _shortHintArray[7] = 103;
        _shortHintArray[8] = 104;
        // @dev Value 9 will always be correct hint
        _shortHintArray[9] = diamond.getShortIdAtOracle(asset);

        return _shortHintArray;
    }

    function skipTimeAndSetEth(uint256 skipTime, int256 ethPrice) public {
        skip(skipTime);
        //setting again to set block.timestamp to baseTimeStamp to prevent stale Oracle data
        _setETH(ethPrice);
    }

    function proposeRedemption(MTypes.ProposalInput[] memory proposalInputs, uint88 redemptionAmount) public {
        diamond.proposeRedemption(asset, proposalInputs, redemptionAmount, MAX_REDEMPTION_FEE, MAX_REDEMPTION_DEADLINE);
    }

    function proposeRedemption(MTypes.ProposalInput[] memory proposalInputs, uint88 redemptionAmount, address redeemer) public {
        uint256 redeemerEthEscrowedBefore = diamond.getVaultUserStruct(vault, redeemer).ethEscrowed;
        uint256 tappEthEscrowedBefore = diamond.getVaultUserStruct(vault, tapp).ethEscrowed;

        vm.prank(redeemer);
        diamond.proposeRedemption(asset, proposalInputs, redemptionAmount, MAX_REDEMPTION_FEE, MAX_REDEMPTION_DEADLINE);

        // Verify that redemptionFee was sent to TAPP
        assertEq(
            diamond.getVaultUserStruct(vault, tapp).ethEscrowed - tappEthEscrowedBefore,
            redeemerEthEscrowedBefore - diamond.getVaultUserStruct(vault, redeemer).ethEscrowed
        );
    }

    function distributeYield(address _addr) internal returns (uint256 reward) {
        // @dev skip bc yield can only be distributed after certain time
        skip(C.YIELD_DELAY_SECONDS + 1);
        address[] memory assets = new address[](1);
        assets[0] = asset;
        uint256 ethEscrowed = diamond.getVaultUserStruct(vault, _addr).ethEscrowed;

        vm.prank(_addr);
        diamond.distributeYield(assets);
        reward = diamond.getVaultUserStruct(vault, _addr).ethEscrowed - ethEscrowed;
    }
}
