// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {U256, U80, U88} from "contracts/libraries/PRBMathHelper.sol";
import {AddressSet, LibAddressSet} from "test/utils/AddressSet.sol";
import {C} from "contracts/libraries/Constants.sol";
import {STypes, SR, MTypes, O} from "contracts/libraries/DataTypes.sol";

import {IAsset} from "interfaces/IAsset.sol";
import {IOBFixture} from "interfaces/IOBFixture.sol";
import {IDiamond} from "interfaces/IDiamond.sol";
import {IMockAggregatorV3} from "interfaces/IMockAggregatorV3.sol";

import {VAULT} from "contracts/libraries/Constants.sol";
import {console} from "contracts/libraries/console.sol";
import {ConstantsTest} from "test/utils/ConstantsTest.sol";

/// @dev The handler is the set of valid actions that can be performed during an invariant test run.
/* solhint-disable no-console */
// solhint-disable-next-line max-states-count
contract Handler is ConstantsTest {
    using U256 for uint256;
    using U80 for uint80;
    using U88 for uint88;
    using LibAddressSet for AddressSet;

    IOBFixture public s_ob;
    IMockAggregatorV3 public ethAggregator;
    address public _ethAggregator;
    address public asset;
    address public deth;
    uint256 public vault;
    address public _diamond;
    IDiamond public diamond;
    address public _reth;
    IAsset public reth;
    address public _bridgeReth;
    address public _steth;
    IAsset public steth;
    address public _bridgeSteth;

    // GHOST VARIABLES
    address internal currentUser;
    AddressSet internal s_Users;
    AddressSet internal s_Shorters;
    AddressSet internal s_ErcHolders;
    AddressSet internal s_Redeemers;
    uint16 public ghost_orderId;
    uint88 public ghost_ethEscrowed;
    uint104 public ghost_ercEscrowed;
    uint256 public ghost_oracleTime;
    uint256 public ghost_oraclePrice;
    uint80 public ghost_dethYieldRate;
    uint88 public ghost_dethCollateralReward;
    uint256 public ghost_protocolTime;
    uint256 public ghost_blockTimestampMod;
    // GHOST VARIABLES - Asserts
    uint256 public ghost_checkOracleTime;
    // GHOST VARIABLES - Counters
    uint256 public ghost_exitShort;
    uint256 public ghost_primaryLiquidation;
    uint256 public ghost_secondaryLiquidation;
    uint256 public ghost_proposeRedemption;
    uint256 public ghost_disputeRedemption;
    uint256 public ghost_claimRedemption;
    uint256 public ghost_claimRemainingCollateral;
    uint256 public ghost_matchAtDiscount;

    uint256 public ghost_exitShortSRGtZeroCounter;
    uint256 public ghost_exitShortComplete;
    uint256 public ghost_secondaryLiquidationSRGtZeroCounter;
    uint256 public ghost_secondaryLiquidationComplete;
    uint256 public ghost_primaryLiquidationSRGtZeroCounter;
    uint256 public ghost_primaryLiquidationComplete;
    uint256 public ghost_proposeRedemptionComplete;
    uint256 public ghost_disputeRedemptionComplete;
    uint256 public ghost_claimRedemptionComplete;
    uint256 public ghost_claimRemainingCollateralComplete;

    uint256 public ghost_exitShortNoAsksCounter;
    uint256 public ghost_exitShortCancelledShortCounter;
    uint256 public ghost_secondaryLiquidationSameUserCounter;
    uint256 public ghost_secondaryLiquidationCancelledShortCounter;
    uint256 public ghost_secondaryLiquidationErcEscrowedShortCounter;
    uint256 public ghost_secondaryLiquidationWalletShortCounter;
    uint256 public ghost_primaryLiquidationSameUserCounter;
    uint256 public ghost_primaryLiquidationCancelledShortCounter;
    uint256 public ghost_proposeRedemptionEmptyProposalCounter;
    uint256 public ghost_disputeRedemptionNoProposals;
    uint256 public ghost_disputeRedemptionTimeElapsed;
    uint256 public ghost_disputeRedemptionNA;

    uint256 public ghost_denominator;
    uint256 public ghost_numerator;

    // OUTPUT VARS - used to print a summary of calls and reverts during certain actions
    // uint256 internal s_swapToCalls;
    // uint256 internal s_swapToFails;

    constructor(IOBFixture ob) {
        s_ob = ob;
        _diamond = ob.contracts("diamond");
        diamond = IDiamond(payable(_diamond));
        asset = ob.contracts("dusd");
        deth = ob.contracts("deth");
        _ethAggregator = ob.contracts("ethAggregator");
        ethAggregator = IMockAggregatorV3(_ethAggregator);
        _steth = ob.contracts("steth");
        steth = IAsset(_steth);
        _reth = ob.contracts("reth");
        reth = IAsset(_reth);
        _bridgeReth = ob.contracts("bridgeReth");
        _bridgeSteth = ob.contracts("bridgeSteth");
        vault = VAULT.ONE;
    }

    //MODIFIERS
    modifier advanceTime() {
        // @dev 12 seconds to replicate how often a block gets added on average
        skip_ghost(12 seconds);
        vm.roll(block.number + 1);
        _;
    }

    // @dev change price by +/- .5% randomly
    modifier advancePrice(uint8 addressSeed) {
        uint256 oracleTime = diamond.getOracleTimeT(asset);
        uint256 currentOraclePrice = diamond.getOraclePriceT(asset);
        uint256 newOraclePrice;
        if (addressSeed % 3 == 0 && block.timestamp < oracleTime + 2 hours) {
            // no change unless oracle price is stale
            newOraclePrice = currentOraclePrice;
        } else if (addressSeed % 2 == 0) {
            newOraclePrice = currentOraclePrice.mul(1.005 ether);
        } else {
            newOraclePrice = currentOraclePrice.mul(0.995 ether);
        }

        int256 newOraclePriceInv = int256(newOraclePrice.inv());
        // @dev Don't change saved oracle data, just chainlink!
        ethAggregator.setRoundData(
            92233720368547778907 wei,
            newOraclePriceInv / C.BASE_ORACLE_DECIMALS,
            block.timestamp,
            block.timestamp,
            92233720368547778907 wei
        );
        _;
    }

    modifier useExistingUser(uint8 userSeed) {
        currentUser = s_Users.rand(userSeed);
        _;
    }

    modifier useExistingShorter(uint8 userSeed) {
        currentUser = s_Shorters.rand(userSeed);
        _;
    }

    modifier useExistingErcHolder(uint8 userSeed) {
        currentUser = s_ErcHolders.rand(userSeed);
        _;
    }

    modifier useExistingRedeemer(uint8 userSeed) {
        currentUser = s_Redeemers.rand(userSeed);
        _;
    }

    // Using this modifier as a workaround bc original test was buggy
    // ghost_oracleTime is updated with latest state at beginning of every function
    // ghost_checkOracleTime is potentially updated at the end of every function
    modifier checkSingularAsserts() {
        _;
        if (ghost_oracleTime > diamond.getOracleTimeT(asset)) {
            ghost_checkOracleTime++;
        }
    }

    //HELPERS
    function skip_ghost(uint256 skipTime) internal {
        if (ghost_protocolTime == 0) {
            // block.timestamp keeps changing?
            ghost_blockTimestampMod = block.timestamp;
        }

        skip(skipTime);
        ghost_protocolTime = block.timestamp - ghost_blockTimestampMod;
    }

    function _seedToAddress(uint8 addressSeed) internal pure returns (address) {
        return address(uint160(_bound(addressSeed, 2, type(uint8).max)));
    }

    function boundU16(uint16 x, uint256 min, uint256 max) internal pure returns (uint16) {
        return uint16(_bound(uint256(x), uint256(min), uint256(max)));
    }

    function boundU80(uint80 x, uint256 min, uint256 max) internal pure returns (uint80) {
        return uint80(_bound(uint256(x), uint256(min), uint256(max)));
    }

    function boundU88(uint88 x, uint256 min, uint256 max) internal pure returns (uint88) {
        return uint88(_bound(uint256(x), uint256(min), uint256(max)));
    }

    function boundU104(uint104 x, uint256 min, uint256 max) internal pure returns (uint104) {
        return uint104(_bound(uint256(x), uint256(min), uint256(max)));
    }

    function getUsers() public view returns (address[] memory) {
        return s_Users.addrs;
    }

    function getShorters() public view returns (address[] memory) {
        return s_Shorters.addrs;
    }

    function getRedeemers() public view returns (address[] memory) {
        return s_Redeemers.addrs;
    }

    function initialGhostVarSetUp(address _msgSender) public {
        ghost_orderId = diamond.getAssetNormalizedStruct(asset).orderId;
        ghost_ethEscrowed = diamond.getVaultUserStruct(vault, _msgSender).ethEscrowed;
        ghost_ercEscrowed = diamond.getAssetUserStruct(asset, _msgSender).ercEscrowed;
        ghost_oracleTime = diamond.getOracleTimeT(asset);
        ghost_dethYieldRate = diamond.getVaultStruct(vault).dethYieldRate;
        ghost_dethCollateralReward = diamond.getVaultStruct(vault).dethCollateralReward;
    }

    function reduceUsers(uint256 acc, function(uint256,address) external returns (uint256) func) public returns (uint256) {
        return s_Users.reduce(acc, func);
    }

    function reduceShorters(uint256 acc, function(uint256,address) external returns (uint256) func) public returns (uint256) {
        return s_Shorters.reduce(acc, func);
    }

    function updateShorters() public {
        uint256 length = s_Users.length();
        for (uint256 i; i < length; ++i) {
            address addr = s_Users.addrs[i];
            STypes.ShortRecord[] memory shortRecords = diamond.getShortRecords(asset, addr);
            bool isShorter = shortRecords.length > 0 && shortRecords[0].collateral > 0;

            if (isShorter) {
                s_Shorters.add(addr);
            } else {
                s_Shorters.remove(addr);
            }
        }
    }

    function updateErcHolders() public {
        uint256 length = s_Users.length();
        for (uint256 i; i < length; ++i) {
            address addr = s_Users.addrs[i];
            uint104 ercEscrowed = diamond.getAssetUserStruct(asset, addr).ercEscrowed;
            bool ercHolder = ercEscrowed > 0;

            if (ercHolder) {
                s_ErcHolders.add(addr);
            } else {
                s_ErcHolders.remove(addr);
            }
        }
    }

    function updateRedeemers() public {
        uint256 length = s_Users.length();
        for (uint256 i; i < length; ++i) {
            address addr = s_Users.addrs[i];
            bool redeemer = diamond.getAssetUserStruct(asset, addr).SSTORE2Pointer != address(0);

            if (redeemer) {
                s_Redeemers.add(addr);
            } else {
                s_Redeemers.remove(addr);
            }
        }
    }

    //MAIN INVARIANT FUNCTIONS
    function cancelOrder(uint16 index, uint8 addressSeed)
        public
        advanceTime
        advancePrice(addressSeed)
        useExistingUser(addressSeed)
        checkSingularAsserts
    {
        initialGhostVarSetUp(currentUser);
        STypes.Order[] memory bids = diamond.getUserOrders(asset, currentUser, O.LimitBid);
        STypes.Order[] memory asks = diamond.getUserOrders(asset, currentUser, O.LimitAsk);
        STypes.Order[] memory shorts = diamond.getUserOrders(asset, currentUser, O.LimitShort);

        if (index % 3 == 0 && bids.length > 0) {
            index = boundU16(index, 0, uint16(bids.length - 1));
            console.log(string.concat("vm.prank(", vm.toString(currentUser), ");"));
            console.log(string.concat("diamond.cancelBid(", vm.toString(asset), ",", vm.toString(bids[index].id), ");"));
            vm.prank(currentUser);
            diamond.cancelBid(asset, bids[index].id);
            ghost_oraclePrice = diamond.getOraclePriceT(asset);
        } else if (index % 3 == 1 && asks.length > 0) {
            index = boundU16(index, 0, uint16(asks.length - 1));
            console.log(string.concat("vm.prank(", vm.toString(currentUser), ");"));
            console.log(string.concat("diamond.cancelAsk(", vm.toString(asset), ",", vm.toString(asks[index].id), ");"));
            vm.prank(currentUser);
            diamond.cancelAsk(asset, asks[index].id);
            ghost_oraclePrice = diamond.getOraclePriceT(asset);
        } else if (index % 3 == 2 && shorts.length > 0) {
            index = boundU16(index, 0, uint16(shorts.length - 1));
            console.log(string.concat("vm.prank(", vm.toString(currentUser), ");"));
            console.log(string.concat("diamond.cancelShort(", vm.toString(asset), ",", vm.toString(shorts[index].id), ");"));
            vm.prank(currentUser);
            diamond.cancelShort(asset, shorts[index].id);
            ghost_oraclePrice = diamond.getOraclePriceT(asset);
        } else {
            console.log("cancelorder [skip]");
        }

        updateErcHolders();
    }

    function _createLimitBid(uint80 price, uint88 amount, uint8 addressSeed)
        public
        advanceTime
        advancePrice(addressSeed)
        useExistingUser(addressSeed)
        checkSingularAsserts
    {
        initialGhostVarSetUp(currentUser);

        uint88 ethEscrowed = diamond.getVaultUserStruct(vault, currentUser).ethEscrowed;
        if (ethEscrowed < price.mulU88(amount)) {
            return;
        }

        MTypes.OrderHint[] memory orderHintArray = diamond.getHintArray(asset, price, O.LimitBid, 1);
        uint16[] memory shortHintArray = new uint16[](1);
        shortHintArray[0] = diamond.getShortIdAtOracle(asset);

        console.log(string.concat("vm.prank(", vm.toString(currentUser), ");"));
        console.log(
            string.concat(
                "createBid(",
                vm.toString(asset),
                ",",
                vm.toString(price),
                ",",
                vm.toString(amount),
                ",",
                "C.LIMIT_ORDER",
                ",",
                "orderHintArray",
                ",",
                "shortHintArray",
                ");"
            )
        );
        vm.prank(currentUser);
        diamond.createBid(asset, price, amount, C.LIMIT_ORDER, orderHintArray, shortHintArray);
        updateShorters();
        updateErcHolders();
        ghost_oraclePrice = diamond.getOraclePriceT(asset);
    }

    function createLimitBidSmall(uint80 price, uint88 amount, uint8 addressSeed) public {
        // bound inputs
        price = boundU80(price, DEFAULT_PRICE / 2, DEFAULT_PRICE * 2);
        amount = boundU88(amount, 500 ether, diamond.getMinShortErc(asset));
        _createLimitBid(price, amount, addressSeed);
    }

    function createLimitBid(uint80 price, uint88 amount, uint8 addressSeed) public {
        // bound inputs
        price = boundU80(price, DEFAULT_PRICE / 2, DEFAULT_PRICE * 2);
        amount = boundU88(amount, DEFAULT_AMOUNT, DEFAULT_AMOUNT * 10);
        _createLimitBid(price, amount, addressSeed);
    }

    function createLimitBidDiscounted(uint80 price, uint88 amount, uint8 addressSeed)
        public
        advanceTime
        advancePrice(addressSeed)
        useExistingUser(addressSeed)
        checkSingularAsserts
    {
        // bound inputs
        uint80 initialErcDebtRate = diamond.getAssetStruct(asset).ercDebtRate;
        uint80 savedPrice = diamond.getOraclePriceT(asset);
        price = boundU80(price, savedPrice.mul(0.9 ether), savedPrice.mul(0.99 ether));
        amount = boundU88(amount, DEFAULT_AMOUNT, DEFAULT_AMOUNT * 10);
        _createLimitBid(price, amount, addressSeed);
        if (diamond.getAssetStruct(asset).ercDebtRate > initialErcDebtRate) ghost_matchAtDiscount++;
    }

    function _createLimitAsk(uint80 price, uint88 amount, uint8 addressSeed)
        public
        advanceTime
        advancePrice(addressSeed)
        useExistingUser(addressSeed)
        checkSingularAsserts
    {
        initialGhostVarSetUp(currentUser);

        uint104 ercEscrowed = diamond.getAssetUserStruct(asset, currentUser).ercEscrowed;
        if (ercEscrowed < amount) {
            return;
        }

        MTypes.OrderHint[] memory orderHintArray = diamond.getHintArray(asset, price, O.LimitAsk, 1);
        console.log(string.concat("vm.prank(", vm.toString(currentUser), ");"));
        console.log(
            string.concat(
                "createAsk(",
                vm.toString(asset),
                ",",
                vm.toString(price),
                ",",
                vm.toString(amount),
                ",",
                "C.LIMIT_ORDER",
                ",",
                "orderHintArray",
                ");"
            )
        );
        vm.prank(currentUser);
        diamond.createAsk(asset, price, amount, C.LIMIT_ORDER, orderHintArray);
        updateErcHolders();
        ghost_oraclePrice = diamond.getOraclePriceT(asset);
    }

    function createLimitAsk(uint80 price, uint88 amount, uint8 addressSeed)
        public
        advanceTime
        advancePrice(addressSeed)
        useExistingUser(addressSeed)
        checkSingularAsserts
    {
        // bound inputs
        price = boundU80(price, DEFAULT_PRICE / 2, DEFAULT_PRICE * 2);
        amount = boundU88(amount, DEFAULT_AMOUNT, DEFAULT_AMOUNT * 10);
        _createLimitAsk(price, amount, addressSeed);
    }

    function createLimitAskDiscounted(uint80 price, uint88 amount, uint8 addressSeed)
        public
        advanceTime
        advancePrice(addressSeed)
        useExistingUser(addressSeed)
        checkSingularAsserts
    {
        // bound inputs
        uint80 initialErcDebtRate = diamond.getAssetStruct(asset).ercDebtRate;
        uint80 savedPrice = diamond.getOraclePriceT(asset);
        price = boundU80(price, savedPrice.mul(0.9 ether), savedPrice.mul(0.99 ether));
        amount = boundU88(amount, DEFAULT_AMOUNT, DEFAULT_AMOUNT * 10);

        // @dev Give user usd to sell
        _createLimitBid(savedPrice, amount, addressSeed);
        _createLimitShort(savedPrice, amount, addressSeed);

        _createLimitAsk(price, amount, addressSeed);
        if (diamond.getAssetStruct(asset).ercDebtRate > initialErcDebtRate) ghost_matchAtDiscount++;
    }

    function _createLimitShort(uint80 price, uint88 amount, uint8 addressSeed)
        public
        advanceTime
        advancePrice(addressSeed)
        useExistingUser(addressSeed)
        checkSingularAsserts
    {
        // bound inputs
        price = boundU80(price, DEFAULT_PRICE / 2, DEFAULT_PRICE * 2);

        uint88 ethEscrowed = diamond.getVaultUserStruct(vault, currentUser).ethEscrowed;

        if (ethEscrowed <= price.mulU88(amount).mulU88(diamond.getAssetNormalizedStruct(asset).initialCR)) {
            return;
        }

        MTypes.OrderHint[] memory orderHintArray = diamond.getHintArray(asset, price, O.LimitShort, 1);
        uint16[] memory shortHintArray = new uint16[](1);
        shortHintArray[0] = diamond.getShortIdAtOracle(asset);

        console.log(string.concat("vm.prank(", vm.toString(currentUser), ");"));
        console.log(
            string.concat(
                "createLimitShort(",
                vm.toString(asset),
                ",",
                vm.toString(price),
                ",",
                vm.toString(amount),
                ",",
                "orderHintArray",
                ",",
                "shortHintArray",
                ",",
                vm.toString(diamond.getAssetStruct(asset).initialCR),
                ");"
            )
        );

        vm.startPrank(currentUser);
        diamond.createLimitShort(asset, price, amount, orderHintArray, shortHintArray, diamond.getAssetStruct(asset).initialCR);
        vm.stopPrank();
        updateShorters();
        updateErcHolders();
        ghost_oraclePrice = diamond.getOraclePriceT(asset);
    }

    function createLimitShortSmall(uint80 price, uint88 amount, uint8 addressSeed) public {
        // bound inputs
        amount = boundU88(amount, diamond.getMinShortErc(asset), DEFAULT_AMOUNT);
        _createLimitShort(price, amount, addressSeed);
    }

    function createLimitShort(uint80 price, uint88 amount, uint8 addressSeed) public {
        // bound inputs
        amount = boundU88(amount, DEFAULT_AMOUNT, DEFAULT_AMOUNT * 10);
        _createLimitShort(price, amount, addressSeed);
    }

    function exitShort(uint80 price, uint256 index, uint8 addressSeed)
        public
        advanceTime
        advancePrice(addressSeed)
        useExistingShorter(addressSeed)
        checkSingularAsserts
    {
        ghost_exitShort++;
        initialGhostVarSetUp(currentUser);
        STypes.ShortRecord[] memory shortRecords = diamond.getShortRecords(asset, currentUser);

        if (shortRecords.length == 0) return;

        //bound inputs
        index = bound(index, 1, shortRecords.length);
        // @dev sometimes the short collateral will not be enough to exit short bc price will be too high
        price = boundU80(price, diamond.getOraclePriceT(asset).div(1.1 ether), diamond.getOraclePriceT(asset).mul(1.1 ether));

        STypes.ShortRecord memory shortRecord = shortRecords[index - 1];
        ghost_exitShortSRGtZeroCounter++;
        if (shortRecord.status == SR.Closed) {
            ghost_exitShortCancelledShortCounter++;
            return;
        }

        if (diamond.getAsks(asset).length == 0) {
            ghost_exitShortNoAsksCounter++;
            return;
        }

        console.log(
            string.concat(
                "exitShort(",
                vm.toString(shortRecord.id),
                ",",
                vm.toString(shortRecord.ercDebt),
                ",",
                vm.toString(price),
                ",",
                vm.toString(currentUser),
                ");"
            )
        );
        s_ob.exitShort(shortRecord.id, shortRecord.ercDebt, uint80(price), currentUser);
        ghost_exitShortComplete++;
        updateShorters();
        ghost_oraclePrice = diamond.getOraclePriceT(asset);
    }

    function secondaryLiquidation(uint88 amount, uint256 index, uint8 addressSeed)
        public
        advanceTime
        advancePrice(addressSeed)
        useExistingShorter(addressSeed)
        checkSingularAsserts
    {
        ghost_secondaryLiquidation++;
        initialGhostVarSetUp(currentUser);
        STypes.ShortRecord[] memory shortRecords = diamond.getShortRecords(asset, currentUser);
        if (shortRecords.length == 0) return;
        // bound inputs
        index = bound(index, 1, shortRecords.length);
        STypes.ShortRecord memory shortRecord = shortRecords[index - 1];

        ghost_secondaryLiquidationSRGtZeroCounter++;
        // bound inputs
        amount = boundU88(amount, DEFAULT_AMOUNT, DEFAULT_AMOUNT * 10);

        address liquidator = s_ErcHolders.rand(addressSeed); // @dev Same as useExistingErcHolder
        if (liquidator == currentUser) {
            ghost_secondaryLiquidationSameUserCounter++;
            return;
        }

        if (shortRecord.status == SR.Closed) {
            ghost_secondaryLiquidationCancelledShortCounter++;
            return;
        }

        // @dev reduce price to liquidation levels
        int256 preLiquidationPrice = int256(diamond.getOraclePriceT(asset).inv());
        s_ob.setETH(750 ether);
        console.log("setETH(750 ether);");

        // @dev randomly choose between erc vs wallet approach
        if (addressSeed % 2 == 0) {
            if (diamond.getAssetUserStruct(asset, liquidator).ercEscrowed < shortRecord.ercDebt) {
                s_ob.setETH(preLiquidationPrice);
                return;
            }

            console.log(
                string.concat(
                    "liquidateErcEscrowed(",
                    vm.toString(currentUser),
                    ",",
                    vm.toString(shortRecord.id),
                    ",",
                    vm.toString(shortRecord.ercDebt),
                    ",",
                    vm.toString(liquidator),
                    ");"
                )
            );

            s_ob.liquidateErcEscrowed(currentUser, shortRecord.id, shortRecord.ercDebt, liquidator);
            ghost_secondaryLiquidationErcEscrowedShortCounter++;
        } else {
            if (IAsset(asset).balanceOf(liquidator) >= shortRecord.ercDebt) {
                console.log(
                    string.concat(
                        "liquidateWallet(",
                        vm.toString(currentUser),
                        ",",
                        vm.toString(shortRecord.id),
                        ",",
                        vm.toString(shortRecord.ercDebt),
                        ",",
                        vm.toString(liquidator),
                        ");"
                    )
                );
                s_ob.liquidateWallet(currentUser, shortRecord.id, shortRecord.ercDebt, liquidator);
                ghost_secondaryLiquidationWalletShortCounter++;
            } else if (diamond.getAssetUserStruct(asset, liquidator).ercEscrowed >= shortRecord.ercDebt) {
                //withdraw
                console.log(string.concat("vm.prank(", vm.toString(liquidator), ");"));
                console.log(string.concat("diamond.withdrawAsset(asset,", vm.toString(shortRecord.ercDebt), ");"));
                console.log(
                    string.concat(
                        "liquidateWallet(",
                        vm.toString(currentUser),
                        ",",
                        vm.toString(shortRecord.id),
                        ",",
                        vm.toString(shortRecord.ercDebt),
                        ",",
                        vm.toString(liquidator),
                        ");"
                    )
                );
                vm.prank(liquidator);
                diamond.withdrawAsset(asset, shortRecord.ercDebt);

                s_ob.liquidateWallet(currentUser, shortRecord.id, shortRecord.ercDebt, liquidator);
                ghost_secondaryLiquidationWalletShortCounter++;
            } else {
                s_ob.setETH(preLiquidationPrice);
                return;
            }
        }

        // @dev reset price back to original levels
        s_ob.setETH(preLiquidationPrice);

        updateShorters();
        updateErcHolders();
        ghost_secondaryLiquidationComplete++;
        ghost_oraclePrice = diamond.getOraclePriceT(asset);
    }

    function createLimitAskForLiquidation(uint80 price, uint88 amount, uint8 addressSeed)
        public
        useExistingErcHolder(addressSeed)
        checkSingularAsserts
    {
        uint88 ercEscrowed = uint88(diamond.getAssetUserStruct(asset, currentUser).ercEscrowed);
        if (ercEscrowed < amount) {
            amount = ercEscrowed;
        }

        MTypes.OrderHint[] memory orderHintArray = diamond.getHintArray(asset, price, O.LimitAsk, 1);
        console.log(string.concat("vm.prank(", vm.toString(currentUser), ");"));
        console.log(
            string.concat(
                "createAsk(",
                vm.toString(asset),
                ",",
                vm.toString(price),
                ",",
                vm.toString(amount),
                ",",
                "C.LIMIT_ORDER",
                ",",
                "orderHintArray",
                ");"
            )
        );
        vm.prank(currentUser);
        diamond.createAsk(asset, price, amount, C.LIMIT_ORDER, orderHintArray);
        updateErcHolders();
    }

    function primaryLiquidation(uint256 index, uint8 addressSeed)
        public
        advanceTime
        advancePrice(addressSeed)
        useExistingShorter(addressSeed)
        checkSingularAsserts
    {
        ghost_primaryLiquidation++;
        initialGhostVarSetUp(currentUser);
        STypes.ShortRecord[] memory shortRecords = diamond.getShortRecords(asset, currentUser);

        if (shortRecords.length == 0) return;

        // bound inputs
        index = bound(index, 1, shortRecords.length);
        STypes.ShortRecord memory shortRecord = shortRecords[index - 1];

        ghost_primaryLiquidationSRGtZeroCounter++;
        address liquidator = s_Users.rand(addressSeed); // @dev Same as useExistingUser
        if (liquidator == currentUser) {
            ghost_primaryLiquidationSameUserCounter++;
            return;
        }

        if (shortRecord.status == SR.Closed) {
            ghost_primaryLiquidationCancelledShortCounter++;
            return;
        }

        int256 preLiquidationPrice = int256(diamond.getOraclePriceT(asset).inv());

        // @dev create ask for liquidation
        console.log(
            string.concat(
                "fundLimitAskOpt(",
                vm.toString(uint80(diamond.getOraclePriceT(asset))),
                ",",
                vm.toString(shortRecord.ercDebt),
                ",",
                vm.toString(liquidator),
                ");"
            )
        );

        // @dev reduce price to liquidation levels
        console.log("setETH(1500 ether);");
        s_ob.setETH(1500 ether);

        // More likely for liquidation to go through
        createLimitAskForLiquidation(uint80(diamond.getOraclePriceT(asset)), shortRecord.ercDebt, addressSeed);

        // Update starting short since ETH price artificially set
        uint16[] memory shortHintArray = new uint16[](1);
        shortHintArray[0] = diamond.getShortIdAtOracle(asset);
        diamond.updateStartingShortId(asset, shortHintArray);

        console.log(
            string.concat(
                "liquidate(", vm.toString(currentUser), ",", vm.toString(shortRecord.id), ",", vm.toString(liquidator), ");"
            )
        );

        uint256 fillEth = s_ob.liquidate(currentUser, shortRecord.id, liquidator);

        console.log(string.concat("fillEth = ", vm.toString(fillEth)));

        // @dev reset price back to original levels
        s_ob.setETH(preLiquidationPrice);
        updateShorters();
        updateErcHolders();
        ghost_primaryLiquidationComplete++;
        ghost_oraclePrice = diamond.getOraclePriceT(asset);
    }

    function depositEth(uint8 addressSeed, uint88 amountIn) public checkSingularAsserts {
        // bound address seed
        address msgSender = _seedToAddress(addressSeed);
        initialGhostVarSetUp(msgSender);

        // bound inputs
        amountIn = boundU88(amountIn, C.MIN_DEPOSIT, 10000 ether);
        console.log(string.concat("give(", vm.toString(msgSender), ",", vm.toString(amountIn), ");"));
        give(msgSender, amountIn);

        address bridge;
        if (amountIn % 2 == 0) {
            bridge = _bridgeSteth;
        } else {
            bridge = _bridgeReth;
        }

        console.log(string.concat("vm.prank(", vm.toString(msgSender), ");"));
        console.log(
            string.concat(
                "diamond.depositEth{value:", vm.toString(amountIn), "}(", amountIn % 2 == 0 ? "_bridgeSteth" : "_bridgeReth", ");"
            )
        );

        vm.prank(msgSender);
        diamond.depositEth{value: amountIn}(bridge);
        s_Users.add(msgSender);

        console.log(
            string.concat(
                "// bridge=",
                vm.toString(diamond.getDethTotal(vault)),
                " dethTotal=",
                vm.toString(diamond.getVaultStruct(vault).dethTotal)
            )
        );
    }

    function deposit(uint8 addressSeed, uint88 amountIn) public checkSingularAsserts {
        address msgSender = _seedToAddress(addressSeed);
        initialGhostVarSetUp(msgSender);

        amountIn = boundU88(amountIn, C.MIN_DEPOSIT, 10000 ether);

        address bridge;
        vm.startPrank(msgSender);
        if (amountIn % 2 == 0) {
            bridge = _bridgeSteth;
            give(_steth, msgSender, amountIn);
            give(_steth, amountIn);
            steth.approve(_bridgeSteth, type(uint88).max);

            console.log(string.concat("give(_steth,", vm.toString(msgSender), ",", vm.toString(amountIn), ");"));
            console.log(string.concat("give(_steth,", vm.toString(amountIn), ");"));
            console.log(string.concat("vm.prank(", vm.toString(msgSender), ");"));
            console.log(string.concat("steth.approve(_bridgeSteth, type(uint88).max);"));
        } else {
            bridge = _bridgeReth;
            give(_reth, msgSender, amountIn);
            give(_reth, amountIn);
            reth.approve(_bridgeReth, type(uint88).max);

            console.log(string.concat("give(_reth,", vm.toString(msgSender), ",", vm.toString(amountIn), ");"));
            console.log(string.concat("give(_reth,", vm.toString(amountIn), ");"));
            console.log(string.concat("vm.prank(", vm.toString(msgSender), ");"));
            console.log(string.concat("reth.approve(_bridgeReth, type(uint88).max);"));
        }

        console.log(string.concat("vm.prank(", vm.toString(msgSender), ");"));
        console.log(
            string.concat("diamond.deposit(", amountIn % 2 == 0 ? "_bridgeSteth" : "_bridgeReth", ",", vm.toString(amountIn), ");")
        );

        diamond.deposit(bridge, amountIn);
        vm.stopPrank();
        s_Users.add(msgSender);

        console.log(
            string.concat(
                "// bridge=",
                vm.toString(diamond.getDethTotal(vault)),
                " dethTotal=",
                vm.toString(diamond.getVaultStruct(vault).dethTotal)
            )
        );
    }

    function withdraw(uint8 addressSeed, uint88 amountOut) public useExistingUser(addressSeed) checkSingularAsserts {
        initialGhostVarSetUp(currentUser);
        address bridge;

        uint88 escrowed = diamond.getVaultUserStruct(vault, currentUser).ethEscrowed;
        if (escrowed <= 1) {
            return;
        } else {
            amountOut = boundU88(amountOut, 1, escrowed);
        }

        if (steth.balanceOf(_bridgeSteth) >= amountOut) {
            bridge = _bridgeSteth;
        } else if (reth.balanceOf(_bridgeReth) >= amountOut) {
            bridge = _bridgeReth;
        } else {
            return;
        }

        console.log(string.concat("vm.prank(", vm.toString(currentUser), ");"));
        console.log(
            string.concat(
                "diamond.withdraw(", amountOut % 2 == 0 ? "_bridgeSteth" : "_bridgeReth", ",", vm.toString(amountOut), ");"
            )
        );

        vm.prank(currentUser);
        diamond.withdraw(bridge, amountOut);

        console.log(
            string.concat(
                "// bridge=",
                vm.toString(diamond.getDethTotal(vault)),
                " dethTotal=",
                vm.toString(diamond.getVaultStruct(vault).dethTotal),
                " ethEscrowed=",
                vm.toString(escrowed)
            )
        );
    }

    function fakeYield(uint64 amountIn) public checkSingularAsserts {
        initialGhostVarSetUp(currentUser);

        amountIn = uint64(_bound(amountIn, 0.1 ether, 1 ether));
        address bridge;
        if (amountIn % 2 == 0) {
            bridge = _bridgeSteth;
            give(_steth, _bridgeSteth, amountIn);
        } else {
            bridge = _bridgeReth;
            give(_reth, _bridgeReth, amountIn);
        }
        vm.prank(makeAddr("1"));
        diamond.updateYield(vault);

        console.log(
            string.concat(
                "// bridge=",
                vm.toString(diamond.getDethTotal(vault)),
                " dethTotal=",
                vm.toString(diamond.getVaultStruct(vault).dethTotal)
            )
        );
    }

    function distributeYield(uint8 addressSeed)
        public
        advancePrice(addressSeed)
        useExistingShorter(addressSeed)
        checkSingularAsserts
    {
        skip_ghost(C.YIELD_DELAY_SECONDS + 1);
        initialGhostVarSetUp(currentUser);

        if (diamond.getYield(asset, currentUser) <= 1) return;

        address[] memory assets = new address[](1);
        assets[0] = asset;

        vm.prank(currentUser);
        diamond.distributeYield(assets);
    }

    function distributeYieldAll() public checkSingularAsserts {
        skip_ghost(C.YIELD_DELAY_SECONDS + 1);
        initialGhostVarSetUp(currentUser); // Address doesn't matter here

        address[] memory assets = new address[](1);
        assets[0] = asset;

        uint256 length = s_Shorters.addrs.length;
        address currentShorter;
        for (uint256 i; i < length; ++i) {
            currentShorter = s_Shorters.addrs[i];
            if (diamond.getYield(asset, currentShorter) <= 1) continue;
            vm.prank(currentShorter);
            diamond.distributeYield(assets);
        }
    }

    function claimDittoMatchedReward(uint8 addressSeed)
        public
        advancePrice(addressSeed)
        useExistingUser(addressSeed)
        checkSingularAsserts
    {
        initialGhostVarSetUp(currentUser);

        if (diamond.getVaultUserStruct(vault, currentUser).dittoMatchedShares <= 1) {
            return;
        }

        vm.prank(currentUser);
        diamond.claimDittoMatchedReward(vault);

        // Ensure some later matches get ditto rewards for matching
        skip_ghost(C.MIN_DURATION);
    }

    function claimDittoMatchedRewardAll(uint8 addressSeed)
        public
        advancePrice(addressSeed)
        useExistingUser(addressSeed)
        checkSingularAsserts
    {
        initialGhostVarSetUp(currentUser); // Address doesn't matter here

        uint256 length = s_Users.addrs.length;
        address currentClaimer;
        for (uint256 i; i < length; ++i) {
            currentClaimer = s_Users.addrs[i];
            if (diamond.getVaultUserStruct(vault, currentClaimer).dittoMatchedShares > 1) {
                vm.prank(currentClaimer);
                diamond.claimDittoMatchedReward(vault);
            }
        }

        // Ensure some later matches get ditto rewards for matching
        skip_ghost(C.MIN_DURATION);
    }

    //VAULT Functions
    function depositAsset(uint8 addressSeed, uint104 amount)
        public
        advanceTime
        advancePrice(addressSeed)
        useExistingUser(addressSeed)
        checkSingularAsserts
    {
        initialGhostVarSetUp(currentUser);
        uint256 balance = IAsset(asset).balanceOf(currentUser);

        if (balance == 0) return;
        // bound inputs
        amount = boundU104(amount, balance, balance);
        vm.prank(currentUser);
        diamond.depositAsset(asset, amount);

        updateErcHolders();
    }

    function withdrawAsset(uint8 addressSeed, uint104 amount)
        public
        advanceTime
        advancePrice(addressSeed)
        useExistingUser(addressSeed)
        checkSingularAsserts
    {
        initialGhostVarSetUp(currentUser);
        uint104 ercEscrowed = diamond.getAssetUserStruct(asset, currentUser).ercEscrowed;
        if (ercEscrowed == 0) return;
        // bound inputs
        amount = boundU104(amount, ercEscrowed, ercEscrowed);
        vm.prank(currentUser);
        diamond.withdrawAsset(asset, amount);

        updateErcHolders();
    }

    function withdrawDittoReward(uint8 addressSeed)
        public
        advanceTime
        advancePrice(addressSeed)
        useExistingUser(addressSeed)
        checkSingularAsserts
    {
        initialGhostVarSetUp(currentUser);
        uint80 dittoReward = diamond.getVaultUserStruct(vault, currentUser).dittoReward;
        if (dittoReward <= 1) return;
        // bound inputs
        vm.prank(currentUser);
        diamond.withdrawDittoReward(vault);
    }

    function withdrawDittoRewardAll() public advanceTime checkSingularAsserts {
        initialGhostVarSetUp(currentUser); // Address doesn't matter

        uint256 length = s_Users.addrs.length;
        address currentClaimer;
        for (uint256 i; i < length; ++i) {
            currentClaimer = s_Users.addrs[i];
            if (diamond.getVaultUserStruct(vault, currentUser).dittoReward > 1) {
                vm.prank(currentClaimer);
                diamond.withdrawDittoReward(vault);
            }
        }
    }

    // Shorts Stuff - re-organize page later
    function increaseCollateral(uint88 amount, uint256 index, uint8 addressSeed)
        public
        advanceTime
        advancePrice(addressSeed)
        useExistingShorter(addressSeed)
        checkSingularAsserts
    {
        initialGhostVarSetUp(currentUser);

        STypes.ShortRecord[] memory shortRecords = diamond.getShortRecords(asset, currentUser);

        console.log("shortRecords.length == 0");
        if (shortRecords.length == 0) return;
        // bound inputs
        amount = boundU88(amount, DEFAULT_PRICE / 10, DEFAULT_PRICE);
        index = bound(index, 1, shortRecords.length);
        STypes.ShortRecord memory shortRecord = shortRecords[index - 1];

        console.log(string.concat("diamond.increaseCollateral(asset,", vm.toString(shortRecord.id), ",", vm.toString(amount), ");"));
        vm.prank(currentUser);
        diamond.increaseCollateral(asset, shortRecord.id, amount);
        ghost_oraclePrice = diamond.getOraclePriceT(asset);
    }

    function decreaseCollateral(uint88 amount, uint256 index, uint8 addressSeed)
        public
        advanceTime
        advancePrice(addressSeed)
        useExistingShorter(addressSeed)
        checkSingularAsserts
    {
        initialGhostVarSetUp(currentUser);

        STypes.ShortRecord[] memory shortRecords = diamond.getShortRecords(asset, currentUser);

        console.log("shortRecords.length == 0");
        if (shortRecords.length == 0) return;
        // bound inputs
        index = bound(index, 1, shortRecords.length);
        STypes.ShortRecord memory shortRecord = shortRecords[index - 1];
        // @dev bounding this to prevent reducing CR too low
        amount = boundU88(amount, shortRecord.collateral / 10, shortRecord.collateral / 6);

        console.log(string.concat("diamond.decreaseCollateral(asset,", vm.toString(shortRecord.id), ",", vm.toString(amount), ");"));
        vm.prank(currentUser);
        diamond.decreaseCollateral(asset, shortRecord.id, amount);
        ghost_oraclePrice = diamond.getOraclePriceT(asset);
    }

    function combineShorts(uint8 addressSeed)
        public
        advanceTime
        advancePrice(addressSeed)
        useExistingShorter(addressSeed)
        checkSingularAsserts
    {
        initialGhostVarSetUp(currentUser);

        STypes.ShortRecord[] memory shortRecords = diamond.getShortRecords(asset, currentUser);

        console.log("shortRecords.length < 2");
        if (shortRecords.length < 2) return;

        uint8[] memory ids = new uint8[](shortRecords.length);
        uint16[] memory shortOrderIds = new uint16[](shortRecords.length);

        for (uint256 i = 0; i < shortRecords.length; i++) {
            ids[i] = shortRecords[i].id;
            uint16 shortOrderId = diamond.getShortOrderId(asset, currentUser, shortRecords[i].id);
            shortOrderIds[i] = shortOrderId;
        }

        vm.prank(currentUser);
        diamond.combineShorts(asset, ids, shortOrderIds);
        ghost_oraclePrice = diamond.getOraclePriceT(asset);
    }

    function proposeRedemption(uint256 index, uint8 addressSeed)
        public
        advancePrice(addressSeed)
        useExistingErcHolder(addressSeed)
        checkSingularAsserts
    {
        ghost_proposeRedemption++;
        initialGhostVarSetUp(currentUser);

        MTypes.ProposalInput[] memory proposalInputs = new MTypes.ProposalInput[](3);
        // Attempt to propose three SR
        for (uint256 i = 0; i < 3; i++) {
            // Select Shorter
            address currentShorter = s_Shorters.rand(addressSeed); // Mimic useExistingShorter
            // Get SR
            STypes.ShortRecord[] memory shortRecords = diamond.getShortRecords(asset, currentShorter);
            if (shortRecords.length == 0) continue;
            index = bound(index, 1, shortRecords.length);
            STypes.ShortRecord memory shortRecord = shortRecords[index - 1];
            // Set slate
            uint16 shortOrderId = diamond.getShortOrderId(asset, currentShorter, shortRecord.id);
            proposalInputs[i] = MTypes.ProposalInput({shorter: currentShorter, shortId: shortRecord.id, shortOrderId: shortOrderId});
            // Select next shorter
            unchecked {
                addressSeed++;
            }
        }

        // Check for empty proposalInputs
        if (proposalInputs[0].shortId + proposalInputs[1].shortId + proposalInputs[2].shortId == 0) {
            ghost_proposeRedemptionEmptyProposalCounter++;
            return;
        }

        uint88 redemptionAmount = uint88(diamond.getAssetUserStruct(asset, currentUser).ercEscrowed);
        int256 preLiquidationPrice = int256(diamond.getOraclePriceT(asset).inv());

        // @dev reduce price to redemption levels
        s_ob.setETH(900 ether);
        console.log("setETH(900 ether);");

        // dev Allow some disputes to happen
        skip_ghost(C.DISPUTE_REDEMPTION_BUFFER / 2);

        s_ob.proposeRedemption(proposalInputs, redemptionAmount, currentUser);
        console.log(
            string.concat(
                "proposeRedemption([",
                vm.toString(proposalInputs[0].shorter),
                "-",
                vm.toString(proposalInputs[0].shortId),
                "-",
                vm.toString(proposalInputs[0].shortOrderId),
                ",",
                vm.toString(proposalInputs[1].shorter),
                "-",
                vm.toString(proposalInputs[1].shortId),
                "-",
                vm.toString(proposalInputs[1].shortOrderId),
                ",",
                vm.toString(proposalInputs[2].shorter),
                "-",
                vm.toString(proposalInputs[2].shortId),
                "-",
                vm.toString(proposalInputs[2].shortOrderId),
                "],",
                vm.toString(redemptionAmount),
                ",",
                vm.toString(currentUser),
                ");"
            )
        );

        // @dev reset price back to original levels
        s_ob.setETH(preLiquidationPrice);
        ghost_oraclePrice = diamond.getOraclePriceT(asset);
        updateShorters();
        updateErcHolders();
        updateRedeemers();
        ghost_proposeRedemptionComplete++;
    }

    function disputeRedemption(uint8 addressSeed)
        public
        advancePrice(addressSeed)
        useExistingUser(addressSeed)
        checkSingularAsserts
    {
        ghost_disputeRedemption++;
        initialGhostVarSetUp(currentUser);

        if (s_Redeemers.length() == 0) {
            ghost_disputeRedemptionNoProposals++;
            return;
        }

        address redeemer = s_Redeemers.rand(addressSeed); // @dev Same as useExistingRedeemer

        (
            uint32 timeProposed,
            uint32 timeToDispute,
            uint80 oraclePrice,
            uint80 ercDebtRate,
            MTypes.ProposalData[] memory decodedProposalData
        ) = diamond.readProposalData(asset, redeemer);

        if (diamond.getOffsetTime() >= timeToDispute) {
            ghost_disputeRedemptionTimeElapsed++;
            return;
        }

        // @dev Dispute the first SR, avoids NotLowestIncorrectIndex error
        MTypes.ProposalData memory incorrectProposal = decodedProposalData[0];

        // Forcibly find a valid dispute, if its exists
        address shorter;
        uint8 shortRecordId;
        for (uint256 i = 0; i < s_Shorters.length(); i++) {
            shorter = s_Shorters.addrs[i];
            if (redeemer == shorter || shorter == address(diamond)) continue; // @dev From validRedemptionSR
            STypes.ShortRecord[] memory shorts = diamond.getShortRecords(asset, shorter); // @dev Screens out SR.Closed
            for (uint256 j = 0; j < shorts.length; j++) {
                STypes.ShortRecord memory shortRecord = shorts[j];
                if (shortRecord.ercDebt < diamond.getMinShortErc(asset)) continue; // @dev From validRedemptionSR
                if (shortRecord.updatedAt + C.DISPUTE_REDEMPTION_BUFFER > timeProposed) continue;
                // Replicate updateErcDebt()
                if (ercDebtRate != shortRecord.ercDebtRate) {
                    shortRecord.ercDebt += shortRecord.ercDebt.mulU88(ercDebtRate - shortRecord.ercDebtRate);
                }
                // Replicate getCollateralRatio()
                uint256 disputeCR = shortRecord.collateral.div(shortRecord.ercDebt.mul(oraclePrice));
                if (disputeCR < incorrectProposal.CR && disputeCR >= C.ONE_CR) {
                    shortRecordId = shortRecord.id;
                    break;
                }
            }

            if (shortRecordId > 0) break;
        }

        if (shortRecordId == 0) {
            ghost_disputeRedemptionNA++;
            return;
        }

        vm.prank(currentUser);
        diamond.disputeRedemption(asset, redeemer, 0, shorter, shortRecordId);
        console.log(
            string.concat(
                "disputeRedemption([", vm.toString(currentUser), ",", vm.toString(redeemer), ",", vm.toString(shorter), ");"
            )
        );

        updateShorters();
        updateErcHolders();
        updateRedeemers();
        ghost_disputeRedemptionComplete++;
    }

    function claimRedemption(uint8 addressSeed)
        public
        advanceTime
        advancePrice(addressSeed)
        useExistingRedeemer(addressSeed)
        checkSingularAsserts
    {
        ghost_claimRedemption++;
        initialGhostVarSetUp(currentUser);

        vm.prank(currentUser);
        diamond.claimRedemption(asset);

        updateShorters();
        updateErcHolders();
        updateRedeemers();
        ghost_claimRedemptionComplete++;
    }

    function claimRemainingCollateral(uint8 addressSeed)
        public
        advanceTime
        advancePrice(addressSeed)
        useExistingRedeemer(addressSeed)
        checkSingularAsserts
    {
        ghost_claimRemainingCollateral++;
        initialGhostVarSetUp(currentUser);

        (,,,, MTypes.ProposalData[] memory decodedProposalData) = diamond.readProposalData(asset, currentUser);
        // Claim the collateral for the first SR in the slate
        MTypes.ProposalData memory claimProposal = decodedProposalData[0];

        vm.prank(claimProposal.shorter);
        diamond.claimRemainingCollateral(asset, currentUser, 0, claimProposal.shortId);

        updateShorters();
        updateErcHolders();
        updateRedeemers();
        ghost_claimRemainingCollateralComplete++;
    }
}
