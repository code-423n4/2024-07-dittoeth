// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

// import {console} from "contracts/libraries/console.sol";

// @dev leave room for others frozen types
// @dev Asset frozen status
enum F {
    Unfrozen,
    Permanent
}

// @dev if this is changed, modify orderTypetoString in libraries/console.sol
// @dev Order types
enum O {
    Uninitialized,
    LimitBid,
    LimitAsk,
    MarketBid,
    MarketAsk,
    LimitShort,
    Cancelled,
    Matched
}

// @dev ShortRecord status
enum SR {
    PartialFill,
    FullyFilled,
    Closed
}

// 2**n-1 with 18 decimals (prices, amount)
// uint64 = 18.45
// uint72 = 4.722k
// uint80 = 1.2m
// uint88 = 300m
// uint96 = 79B
// uint104 = 1.2t

// DataTypes used in storage
library STypes {
    // 2 slots
    struct Order {
        // SLOT 1: 88 + 80 + 16 + 16 + 16 + 8 + 32 = 256
        uint88 ercAmount; // max 300m erc
        uint80 price; // max 1.2m eth
        // max orders 65k, with id re-use
        uint16 prevId;
        uint16 id;
        uint16 nextId;
        O orderType;
        // @dev diff against contract creation timestamp to prevent overflow in 2106
        uint32 creationTime; // seconds
        // SLOT 2: 160 + 8 + 16 + 8 = 192 (64 unused)
        address addr; // 160
        O prevOrderType;
        // @dev storing as 170 with 2 decimals -> 1.70 ether
        uint16 shortOrderCR; // @dev CR from the shorter only used for limit short
        uint8 shortRecordId; // @dev only used for LimitShort
        uint64 filler;
    }

    // 2 slots
    // @dev dethYieldRate should match Vault
    struct ShortRecord {
        // SLOT 1: 88 + 88 + 80 = 256
        uint88 collateral; // price * ercAmount * initialCR
        uint88 ercDebt; // same as Order.ercAmount
        uint80 dethYieldRate;
        // SLOT 2: 88 + 80 + 32 + 8 + 8 + 8 + 8 = 216 (24 remaining)
        SR status;
        uint8 prevId;
        uint8 id;
        uint8 nextId;
        uint80 ercDebtRate; // socialized penalty rate
        uint32 updatedAt; // seconds
        uint88 ercDebtFee;
        uint24 filler1;
    }

    // uint8:  [0-255]
    // uint16: [0-65_535]
    // @dev see testMultiAssetSettings()
    struct Asset {
        // SLOT 1: 104 + 88 + 16 + 16 + 16 + 8 + 8 = 256 (0 unused)
        uint104 ercDebt; // max 20.2T
        uint88 dethCollateral;
        uint16 startingShortId;
        uint16 orderIdCounter; // max is uint16 but need to throw/handle that?
        uint16 initialCR; // 5 ether -> [1-10, 2 decimals]
        F frozen; // 0 or 1
        uint8 vault;
        // SLOT 2 (Liquidation Parameters)
        //64 + 8*8 + 16*2 + 32 = 192 (64 unused)
        uint8 minBidEth; // 10 -> (1 * 10**18 / 10**2) = 0.1 ether
        uint8 minAskEth; // 10 -> (1 * 10**18 / 10**2) = 0.1 ether
        uint16 minShortErc; // 2000 -> (2000 * 10**18) -> 2000 ether
        uint8 penaltyCR; // 1.1 ether -> [1-2, 2 decimals]
        uint8 tappFeePct; // 0.025 ether -> [0-2.5%, 3 decimals]
        uint8 callerFeePct; // 0.005 ether -> [0-2.5%, 3 decimals]
        uint8 forcedBidPriceBuffer; // 1.1 ether -> [1-2, 2 decimals]
        uint8 assetId;
        uint64 baseRate;
        uint16 liquidationCR; // 1.5 ether -> [1-5, 2 decimals]
        uint8 recoveryCR; // 1.5 ether -> [1-2, 2 decimals]
        //TODO: Make fn and set lastRedemption to ZERO on mainnet remove fn
        uint32 lastRedemptionTime; //in seconds;
        uint64 filler1; //ercDebtRate used to be here
        // SLOT 3 (Chainlink)
        //160 (96 unused)
        address oracle; // for non-usd asset
        uint96 filler2;
        // SLOT 4 (Discount)
        // 104 + 32 + 32 + 16 + 16 = 200 (56 unused)
        uint104 discountedErcMatched;
        uint32 initialDiscountTime;
        uint32 lastDiscountTime;
        uint16 discountPenaltyFee;
        uint16 discountMultiplier;
        uint56 filler3;
        // SLOT 5 (debtFee)
        // 88 + 80 = 168 (88 unused)
        uint88 ercDebtFee;
        //TODO: ercDebtRate moved from slot 2 to slot 5. Account for this in migration
        uint80 ercDebtRate; // socialized penalty rate
        uint88 filler4;
    }

    // 3 slots
    // @dev dethYieldRate should match ShortRecord
    struct Vault {
        // SLOT 1: 88 + 88 + 80 = 256 (0 unused)
        uint88 dethCollateral; // max 309m, 18 decimals
        uint88 dethTotal; // max 309m, 18 decimals
        uint80 dethYieldRate; // onlyUp
        // SLOT 2: 88 + 16 + 16 = 120 (136 unused)
        // tracked for shorter ditto rewards
        uint88 dethCollateralReward; // onlyUp
        uint16 dethTithePercent; // [0-100, 2 decimals]
        uint16 dittoShorterRate; // per unit of dethCollateral
        uint136 filler2;
        // SLOT 3: 128 + 96 + 16 + 16 = 256
        uint128 dittoMatchedShares;
        uint96 dittoMatchedReward; // max 79B, 18 decimals
        uint16 dittoMatchedRate;
        uint16 dittoMatchedTime; // last claim (in days) from STARTING_TIME
    }

    struct AssetUser {
        // SLOT 1: 104 + 56 + 8 = 168 (88 unused)
        uint104 ercEscrowed;
        uint56 filler1;
        uint8 shortRecordCounter;
        uint88 filler2;
        //SLOT 2: 160 + 8 = 168 (88 unused)
        address SSTORE2Pointer;
        uint8 slateLength;
        uint88 filler3;
    }

    // 1 slots
    struct VaultUser {
        // SLOT 1: 88 + 88 + 80 = 256 (0 unused)
        uint88 ethEscrowed;
        uint88 dittoMatchedShares;
        uint80 dittoReward; // max 1.2m, 18 decimals
        // SLOT 2: 88 + 88 = 172 (80 unused)
        // Credits only needed for VAULT.ONE with mixed LST
        uint88 bridgeCreditReth;
        uint88 bridgeCreditSteth;
    }

    struct Bridge {
        // SLOT 1: 16 + 8 = 24 (232 unused)
        uint8 vault;
        uint16 withdrawalFee;
    }
}

// @dev DataTypes only used in memory
library MTypes {
    struct OrderHint {
        uint16 hintId;
        uint256 creationTime;
    }

    struct BatchLiquidation {
        address shorter;
        uint8 shortId;
        uint16 shortOrderId;
    }

    struct Match {
        uint88 fillEth;
        uint88 fillErc;
        uint256 colUsed;
        uint88 dittoMatchedShares;
        uint256 lastMatchPrice;
        // Below used only for bids
        uint88 shortFillEth; // Includes colUsed + fillEth from shorts
        uint104 askFillErc; // Subset of fillErc
        bool ratesQueried; // Save gas when matching shorts
        uint80 dethYieldRate;
        uint80 ercDebtRate;
    }

    struct ExitShort {
        address asset;
        uint256 ercDebt;
        uint88 collateral;
        uint88 ethFilled;
        uint88 ercAmountLeft;
        uint88 ercFilled;
        uint256 beforeExitCR;
        uint88 buybackAmount;
        bool shortOrderIsCancelled;
    }

    struct CombineShorts {
        uint88 collateral;
        uint88 ercDebt;
        uint256 yield;
        uint256 ercDebtSocialized;
        uint88 ercDebtFee;
    }

    struct PrimaryLiquidation {
        address asset;
        uint256 vault;
        STypes.ShortRecord short;
        uint16 shortOrderId;
        address shorter;
        uint256 cRatio;
        uint256 oraclePrice;
        uint256 forcedBidPriceBuffer;
        uint256 ethDebt;
        uint88 ethFilled;
        uint88 ercDebtMatched;
        bool loseCollateral;
        uint256 tappFeePct;
        uint256 callerFeePct;
        uint88 gasFee;
        uint88 totalFee; // gasFee + tappFee + callerFee
        uint256 penaltyCR;
    }

    struct SecondaryLiquidation {
        STypes.ShortRecord short;
        uint16 shortOrderId;
        bool isPartialFill;
        address shorter;
        uint88 liquidatorCollateral;
        uint256 cRatio;
    }

    struct AssetParams {
        address asset;
        uint256 penaltyCR;
        uint256 oraclePrice;
        uint256 liquidationCR;
        uint256 minShortErc;
        uint80 ercDebtRate;
    }

    struct BidMatchAlgo {
        uint16 askId;
        uint16 shortHintId;
        uint16 shortId;
        uint16 prevShortId;
        uint16 firstShortIdBelowOracle;
        uint16 matchedAskId;
        uint16 matchedShortId;
        bool isMovingBack;
        bool isMovingFwd;
        uint256 oraclePrice;
        uint16 dustAskId;
        uint16 dustShortId;
    }

    struct CreateVaultParams {
        uint16 dethTithePercent;
        uint16 dittoMatchedRate;
        uint16 dittoShorterRate;
    }

    struct CreateLimitShortParam {
        uint256 eth;
        uint256 CR;
        uint256 initialCR;
        uint256 ethInitial;
        uint256 minShortErc;
        uint256 minAskEth;
        uint256 oraclePrice;
    }

    // @dev saved via SSTORE2
    // @dev total bytes: 232 + 176 = 408
    struct ProposalData {
        // SLOT 1: 160 + 8 + 88 = 232 (24 unused)
        address shorter;
        uint8 shortId;
        uint64 CR;
        // SLOT 2: 88 + 88 = 176 (80 unused)
        uint88 ercDebtRedeemed;
        uint88 colRedeemed;
        //SLOT 3: 88
        uint88 ercDebtFee;
    }

    struct ProposalInput {
        address shorter;
        uint8 shortId;
        uint16 shortOrderId;
    }

    struct ProposeRedemption {
        address asset;
        address shorter;
        uint8 shortId;
        uint16 shortOrderId;
        uint32 protocolTime;
        uint88 totalAmountProposed;
        uint88 totalColRedeemed;
        uint256 currentCR;
        uint256 lastCR;
        uint8 redemptionCounter;
        uint80 oraclePrice;
        uint88 amountProposed;
        uint88 colRedeemed;
        uint80 ercDebtRate;
        uint88 ercDebtFee;
        uint88 totalErcDebtFee;
    }

    struct DisputeRedemption {
        address asset;
        address redeemer;
        uint32 timeProposed;
        uint32 timeToDispute;
        uint80 oraclePrice;
        uint80 ercDebtRate;
        MTypes.ProposalData[] decodedProposalData;
        uint88 incorrectCollateral;
        uint88 incorrectErcDebt;
        uint256 minShortErc;
        uint256 disputeCR;
        uint32 protocolTime;
        uint80 dethYieldRate;
        uint88 ercDebtFee;
    }

    struct HandleDiscount {
        address asset;
        uint256 savedPrice;
        uint256 ercDebt;
        uint256 price;
        uint256 ercAmount;
    }
}
