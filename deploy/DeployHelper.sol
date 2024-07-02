// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {U256} from "contracts/libraries/PRBMathHelper.sol";
import {Test} from "forge-std/Test.sol";

import {MTypes, STypes} from "contracts/libraries/DataTypes.sol";
import {C, VAULT} from "contracts/libraries/Constants.sol";
import {Diamond} from "contracts/Diamond.sol";
import {IDiamondCut} from "contracts/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "contracts/interfaces/IDiamondLoupe.sol";

import {IDiamond} from "interfaces/IDiamond.sol";
import {ITestFacet} from "interfaces/ITestFacet.sol";

import {IBridge} from "contracts/interfaces/IBridge.sol";
import {IAsset} from "interfaces/IAsset.sol";
import {IyDUSD} from "interfaces/IyDUSD.sol";

import {IMockAggregatorV3} from "interfaces/IMockAggregatorV3.sol";
import {ISTETH} from "interfaces/ISTETH.sol";
import {IRocketStorage} from "interfaces/IRocketStorage.sol";
import {IRocketTokenRETH} from "interfaces/IRocketTokenRETH.sol";
import {IUNSTETH} from "interfaces/IUNSTETH.sol";
import {Multicall3} from "deploy/MultiCall3.sol";

//DO NOT REMOVE. WIll BREAK CI
import {ImmutableCreate2Factory} from "deploy/ImmutableCreate2Factory.sol";

// import {console} from "contracts/libraries/console.sol";

interface IImmutableCreate2Factory {
    function safeCreate2(bytes32 salt, bytes memory contractCreationCode) external returns (address);
}

/* solhint-disable max-states-count */
contract DeployHelper is Test {
    using U256 for uint256;

    IImmutableCreate2Factory public factory;
    address public _immutableCreate2Factory;

    bool public isMock = true;
    bool public isLocalDeploy = false;

    IDiamond public diamond;
    address public _diamond;
    address public _diamondLoupe;
    address public _diamondCut;

    address public _askOrders;
    address public _bidOrders;
    address public _bridgeRouter;
    address public _exitShort;
    address public _liquidatePrimary;
    address public _liquidateSecondary;
    address public _marketShutdown;
    address public _orders;
    address public _ownerFacet;
    address public _shortOrders;
    address public _shortRecord;
    address public _testFacet;
    address public _twapFacet;
    address public _vaultFacet;
    address public _viewFacet;
    address public _viewRedemptionFacet;
    address public _yield;
    address public _proposeRedemption;
    address public _disputeRedemption;
    address public _claimRedemption;

    ITestFacet public testFacet;

    bytes4[] internal loupeSelectors = [
        IDiamond.facets.selector,
        IDiamond.facetFunctionSelectors.selector,
        IDiamond.facetAddresses.selector,
        IDiamond.facetAddress.selector
    ];
    bytes4[] internal askOrdersSelectors =
        [IDiamond.createAsk.selector, IDiamond._cancelAsk.selector, IDiamond._cancelShort.selector];
    bytes4[] internal bidOrdersSelectors = [IDiamond.createBid.selector, IDiamond.createForcedBid.selector];
    bytes4[] internal bridgeRouterSelectors = [
        IDiamond.getDethTotal.selector,
        IDiamond.getBridges.selector,
        IDiamond.deposit.selector,
        IDiamond.depositEth.selector,
        IDiamond.withdraw.selector,
        IDiamond.withdrawTapp.selector
    ];
    bytes4[] internal exitShortSelectors =
        [IDiamond.exitShortWallet.selector, IDiamond.exitShortErcEscrowed.selector, IDiamond.exitShort.selector];
    bytes4[] internal liquidatePrimarySelectors = [IDiamond.liquidate.selector];
    bytes4[] internal liquidateSecondarySelectors = [IDiamond.liquidateSecondary.selector];
    bytes4[] internal marketShutdownSelectors = [IDiamond.shutdownMarket.selector, IDiamond.redeemErc.selector];
    bytes4[] internal ordersSelectors = [
        IDiamond.cancelAsk.selector,
        IDiamond.cancelBid.selector,
        IDiamond.cancelShort.selector,
        IDiamond.cancelOrderFarFromOracle.selector,
        IDiamond._matchIsDiscounted.selector
    ];
    bytes4[] internal ownerSelectors = [
        IDiamond.transferOwnership.selector,
        IDiamond.claimOwnership.selector,
        IDiamond.owner.selector,
        IDiamond.admin.selector,
        IDiamond.transferAdminship.selector,
        IDiamond.ownerCandidate.selector,
        IDiamond.setTithe.selector,
        IDiamond.setDittoMatchedRate.selector,
        IDiamond.setDittoShorterRate.selector,
        IDiamond.setInitialCR.selector,
        IDiamond.setLiquidationCR.selector,
        IDiamond.setForcedBidPriceBuffer.selector,
        IDiamond.setPenaltyCR.selector,
        IDiamond.setTappFeePct.selector,
        IDiamond.setCallerFeePct.selector,
        IDiamond.setMinBidEth.selector,
        IDiamond.setMinAskEth.selector,
        IDiamond.setMinShortErc.selector,
        IDiamond.createBridge.selector,
        IDiamond.createVault.selector,
        IDiamond.createMarket.selector,
        IDiamond.setWithdrawalFee.selector,
        IDiamond.setRecoveryCR.selector,
        IDiamond.setDiscountPenaltyFee.selector,
        IDiamond.setDiscountMultiplier.selector,
        IDiamond.setYieldVault.selector
    ];
    bytes4[] internal shortOrdersSelectors = [IDiamond.createLimitShort.selector];
    bytes4[] internal shortRecordSelectors =
        [IDiamond.increaseCollateral.selector, IDiamond.decreaseCollateral.selector, IDiamond.combineShorts.selector];
    bytes4[] internal testSelectors = [
        ITestFacet.setLiquidationCRT.selector,
        ITestFacet.getAskKey.selector,
        ITestFacet.getBidKey.selector,
        ITestFacet.getBidOrder.selector,
        ITestFacet.getAskOrder.selector,
        ITestFacet.getShortOrder.selector,
        ITestFacet.currentInactiveBids.selector,
        ITestFacet.currentInactiveAsks.selector,
        // ITestFacet.currentInactiveShorts.selector,
        ITestFacet.setReentrantStatus.selector,
        ITestFacet.getReentrantStatus.selector,
        ITestFacet.setOracleTimeAndPrice.selector,
        ITestFacet.setBaseOracle.selector,
        ITestFacet.getOracleTimeT.selector,
        ITestFacet.getOraclePriceT.selector,
        ITestFacet.setStartingShortId.selector,
        ITestFacet.setDethYieldRate.selector,
        ITestFacet.nonZeroVaultSlot0.selector,
        ITestFacet.setforcedBidPriceBufferT.selector,
        ITestFacet.setErcDebtRateAsset.selector,
        ITestFacet.setOrderIdT.selector,
        ITestFacet.getAssetNormalizedStruct.selector,
        ITestFacet.getBridgeNormalizedStruct.selector,
        ITestFacet.getWithdrawalFeePct.selector,
        ITestFacet.setEthEscrowed.selector,
        ITestFacet.setBridgeCredit.selector,
        ITestFacet.getUserOrders.selector,
        ITestFacet.setFrozenT.selector,
        ITestFacet.getAssets.selector,
        ITestFacet.updateStartingShortId.selector,
        ITestFacet.deleteBridge.selector,
        ITestFacet.dittoShorterRate.selector,
        ITestFacet.dittoMatchedRate.selector,
        ITestFacet.setAssetOracle.selector,
        ITestFacet.setErcDebt.selector,
        ITestFacet.setErcDebtAsset.selector,
        ITestFacet.setDiscountedErcMatchedAsset.selector,
        ITestFacet.setInitialDiscountTimeAsset.selector,
        ITestFacet.addErcDebtAsset.selector,
        ITestFacet.setLastRedemptionTime.selector,
        ITestFacet.setBaseRate.selector,
        ITestFacet.setMinShortErcT.selector,
        ITestFacet.addErcDebtFee.selector
    ];
    bytes4[] internal twapSelectors = [IDiamond.estimateWETHInUSDC.selector];
    bytes4[] internal vaultFacetSelectors = [IDiamond.depositAsset.selector, IDiamond.withdrawAsset.selector];
    bytes4[] internal viewRedemptionSelectors =
        [IDiamond.getTimeToDispute.selector, IDiamond.getRedemptionFee.selector, IDiamond.readProposalData.selector];
    bytes4[] internal viewSelectors = [
        IDiamond.getDethBalance.selector,
        IDiamond.getAssetBalance.selector,
        IDiamond.getVault.selector,
        IDiamond.getBridgeVault.selector,
        IDiamond.getDethYieldRate.selector,
        IDiamond.getBids.selector,
        IDiamond.getBidHintId.selector,
        IDiamond.getAsks.selector,
        IDiamond.getAskHintId.selector,
        IDiamond.getShorts.selector,
        IDiamond.getShortHintId.selector,
        IDiamond.getShortIdAtOracle.selector,
        IDiamond.getHintArray.selector,
        IDiamond.getCollateralRatio.selector,
        IDiamond.getOracleAssetPrice.selector,
        IDiamond.getProtocolAssetPrice.selector,
        IDiamond.getProtocolAssetTime.selector,
        IDiamond.getTithe.selector,
        IDiamond.getUndistributedYield.selector,
        IDiamond.getYield.selector,
        IDiamond.getDittoMatchedReward.selector,
        IDiamond.getDittoReward.selector,
        IDiamond.getAssetCollateralRatio.selector,
        IDiamond.getShortRecord.selector,
        IDiamond.getShortRecords.selector,
        IDiamond.getShortRecordCount.selector,
        IDiamond.getAssetUserStruct.selector,
        IDiamond.getVaultUserStruct.selector,
        IDiamond.getVaultStruct.selector,
        IDiamond.getAssetStruct.selector,
        IDiamond.getBridgeStruct.selector,
        IDiamond.getOffsetTime.selector,
        IDiamond.getShortOrderId.selector,
        IDiamond.getShortOrderIdArray.selector,
        IDiamond.getMinShortErc.selector,
        IDiamond.getTimeSinceDiscounted.selector,
        IDiamond.getInitialDiscountTime.selector,
        IDiamond.getExpectedSRDebt.selector
    ];
    bytes4[] internal yieldSelectors = [
        IDiamond.updateYield.selector,
        IDiamond._updateYieldDiamond.selector,
        IDiamond.distributeYield.selector,
        IDiamond.claimDittoMatchedReward.selector,
        IDiamond.withdrawDittoReward.selector
    ];

    bytes4[] internal proposeRedemptionSelectors = [IDiamond.proposeRedemption.selector];

    bytes4[] internal disputeRedemptionSelectors = [IDiamond.disputeRedemption.selector];

    bytes4[] internal claimRedemptionSelectors = [IDiamond.claimRedemption.selector, IDiamond.claimRemainingCollateral.selector];

    IDiamondCut.FacetCut[] public cut;

    IBridge public bridgeSteth;
    address public _bridgeSteth;
    IBridge public bridgeReth;
    address public _bridgeReth;

    IAsset public deth;
    address public _deth;
    IAsset public dusd;
    address public _dusd;
    IAsset public ditto;
    address public _ditto;
    IyDUSD public yDUSD;
    address public _yDUSD;

    //mocks
    address public _multicall3;
    ISTETH public steth;
    address public _steth;
    IUNSTETH public unsteth;
    address public _unsteth;
    IMockAggregatorV3 public ethAggregator;
    address public _ethAggregator;
    IRocketStorage public rocketStorage;
    address public _rocketStorage;
    IRocketTokenRETH public reth;
    address public _reth;

    function getSelector(string memory _func) internal pure returns (bytes4) {
        return bytes4(keccak256(bytes(_func)));
    }

    function deployContracts(address _owner, uint256 chainId) internal {
        string memory profile = vm.envOr("FOUNDRY_PROFILE", string("default"));
        bool isGas = keccak256(abi.encodePacked(profile)) == keccak256(abi.encodePacked("testgas"));
        if (chainId == 31337) {
            //mocks
            _immutableCreate2Factory = deployCode(
                isGas
                    ? "foundry/artifacts-gas/ImmutableCreate2Factory.sol/ImmutableCreate2Factory.json"
                    : "foundry/artifacts/ImmutableCreate2Factory.sol/ImmutableCreate2Factory.json"
            );

            if (isMock) {
                _steth = deployCode(isGas ? "foundry/artifacts-gas/STETH.sol/STETH.json" : "foundry/artifacts/STETH.sol/STETH.json");
                _unsteth = deployCode(
                    isGas ? "foundry/artifacts-gas/UNSTETH.sol/UNSTETH.json" : "foundry/artifacts/UNSTETH.sol/UNSTETH.json",
                    abi.encode(_steth)
                );
                _reth = deployCode(
                    isGas
                        ? "foundry/artifacts-gas/RocketTokenRETH.sol/RocketTokenRETH.json"
                        : "foundry/artifacts/RocketTokenRETH.sol/RocketTokenRETH.json"
                );
                _rocketStorage = deployCode(
                    isGas
                        ? "foundry/artifacts-gas/RocketStorage.sol/RocketStorage.json"
                        : "foundry/artifacts/RocketStorage.sol/RocketStorage.json",
                    abi.encode(_reth)
                );
                reth = IRocketTokenRETH(_reth);
                _ethAggregator = deployCode(
                    isGas
                        ? "foundry/artifacts-gas/MockAggregatorV3.sol/MockAggregatorV3.json"
                        : "foundry/artifacts/MockAggregatorV3.sol/MockAggregatorV3.json"
                );
                rocketStorage = IRocketStorage(_rocketStorage);
                rocketStorage.setDeposit(_reth);
                rocketStorage.setReth(_reth);
            }

            if (isLocalDeploy) {
                _immutableCreate2Factory = address(0x0000000000FFe8B47B3e2130213B802212439497);
                _steth = address(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
                _unsteth = address(0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1);
                _rocketStorage = address(0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46);
                _ethAggregator = deployCode("MockAggregatorV3.sol");
            }
        } else if (chainId == 1) {
            _immutableCreate2Factory = address(0x0000000000FFe8B47B3e2130213B802212439497);
            _steth = address(0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84);
            _unsteth = address(0x889edC2eDab5f40e902b864aD4d7AdE8E412F9B1);
            _rocketStorage = address(0x1d8f8f00cfa6758d7bE78336684788Fb0ee0Fa46);
            _ethAggregator = address(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419);
        } else if (chainId == 5) {
            _immutableCreate2Factory = address(0x0000000000FFe8B47B3e2130213B802212439497);
            _steth = address(0x1643E812aE58766192Cf7D2Cf9567dF2C37e9B7F);
            _unsteth = address(0xCF117961421cA9e546cD7f50bC73abCdB3039533);
            _rocketStorage = address(0xd8Cd47263414aFEca62d6e2a3917d6600abDceB3);
            _ethAggregator = address(0xD4a33860578De61DBAbDc8BFdb98FD742fA7028e);
        }
        rocketStorage = IRocketStorage(_rocketStorage);
        _reth = rocketStorage.getAddress(keccak256(abi.encodePacked("contract.address", "rocketTokenRETH")));
        steth = ISTETH(_steth);
        unsteth = IUNSTETH(payable(_unsteth));
        ethAggregator = IMockAggregatorV3(_ethAggregator);

        factory = IImmutableCreate2Factory(_immutableCreate2Factory);

        bytes32 salt = bytes32(0);

        _diamondCut = factory.safeCreate2(
            salt,
            abi.encodePacked(
                vm.getCode(
                    isGas
                        ? "foundry/artifacts-gas/DiamondCutFacet.sol/DiamondCutFacet.json"
                        : "foundry/artifacts/DiamondCutFacet.sol/DiamondCutFacet.json"
                )
            )
        );

        salt = 0x00000000000000000000000000000000000000005272369be7612000004a33fd;

        _diamond =
            factory.safeCreate2(salt, abi.encodePacked(type(Diamond).creationCode, abi.encode(_owner, _diamondCut, _ethAggregator)));

        //  bytes memory bytecode = abi.encodePacked(
        //     type(Diamond).creationCode, abi.encode(_owner, _diamondCut, _ethAggregator)
        // );
        // emit log_bytes32(keccak256(bytecode));
        //Tokens
        _deth = factory.safeCreate2(
            0x00000000000000000000000000000000000000008b5840c757a12000007ca931,
            abi.encodePacked(
                vm.getCode(isGas ? "foundry/artifacts-gas/Asset.sol/Asset.json" : "foundry/artifacts/Asset.sol/Asset.json"),
                abi.encode(_diamond, "Ditto ETH", "DETH")
            )
        );

        _ditto = factory.safeCreate2(
            0x0000000000000000000000000000000000000000d7cd33daa1d61000005fb55f,
            abi.encodePacked(
                vm.getCode(isGas ? "foundry/artifacts-gas/Ditto.sol/Ditto.json" : "foundry/artifacts/Ditto.sol/Ditto.json"),
                abi.encode(_diamond, _owner)
            )
        );

        _dusd = factory.safeCreate2(
            0x00000000000000000000000000000000000000008458c43e4f5a5800007b8f59,
            abi.encodePacked(
                vm.getCode(isGas ? "foundry/artifacts-gas/Asset.sol/Asset.json" : "foundry/artifacts/Asset.sol/Asset.json"),
                abi.encode(_diamond, "Ditto USD", "DUSD")
            )
        );

        //TODO: Use create2Crunch to create a vanity address
        _yDUSD = factory.safeCreate2(
            0x0000000000000000000000000000000000000000E7f64c3335940dB91596F7dC,
            abi.encodePacked(
                vm.getCode(isGas ? "foundry/artifacts-gas/yDUSD.sol/yDUSD.json" : "foundry/artifacts/yDUSD.sol/yDUSD.json"),
                abi.encode("Yield Ditto USD", "yDUSD", _dusd, _diamond)
            )
        );

        //Bridges
        _bridgeReth = factory.safeCreate2(
            salt,
            abi.encodePacked(
                vm.getCode(
                    isGas
                        ? "foundry/artifacts-gas/BridgeReth.sol/BridgeReth.json"
                        : "foundry/artifacts/BridgeReth.sol/BridgeReth.json"
                ),
                abi.encode(_rocketStorage, _diamond)
            )
        );
        _bridgeSteth = factory.safeCreate2(
            salt,
            abi.encodePacked(
                vm.getCode(
                    isGas
                        ? "foundry/artifacts-gas/BridgeSteth.sol/BridgeSteth.json"
                        : "foundry/artifacts/BridgeSteth.sol/BridgeSteth.json"
                ),
                abi.encode(_steth, _unsteth, _diamond)
            )
        );

        //Facets
        _diamondLoupe = factory.safeCreate2(
            salt,
            abi.encodePacked(
                vm.getCode(
                    isGas
                        ? "foundry/artifacts-gas/DiamondLoupeFacet.sol/DiamondLoupeFacet.json"
                        : "foundry/artifacts/DiamondLoupeFacet.sol/DiamondLoupeFacet.json"
                )
            )
        );
        _ownerFacet = factory.safeCreate2(
            salt,
            abi.encodePacked(
                vm.getCode(
                    isGas
                        ? "foundry/artifacts-gas/OwnerFacet.sol/OwnerFacet.json"
                        : "foundry/artifacts/OwnerFacet.sol/OwnerFacet.json"
                )
            )
        );
        _viewFacet = factory.safeCreate2(
            salt,
            abi.encodePacked(
                vm.getCode(
                    isGas ? "foundry/artifacts-gas/ViewFacet.sol/ViewFacet.json" : "foundry/artifacts/ViewFacet.sol/ViewFacet.json"
                ),
                abi.encode(_dusd)
            )
        );

        _viewRedemptionFacet = factory.safeCreate2(
            salt,
            abi.encodePacked(
                vm.getCode(
                    isGas
                        ? "foundry/artifacts-gas/ViewRedemptionFacet.sol/ViewRedemptionFacet.json"
                        : "foundry/artifacts/ViewRedemptionFacet.sol/ViewRedemptionFacet.json"
                )
            )
        );

        if (chainId == 31337) {
            _yield = factory.safeCreate2(
                salt,
                abi.encodePacked(
                    vm.getCode(
                        isGas
                            ? "foundry/artifacts-gas/YieldFacet.sol/YieldFacet.json"
                            : "foundry/artifacts/YieldFacet.sol/YieldFacet.json"
                    ),
                    abi.encode(_ditto, 6 ether)
                )
            );
        } else {
            _yield = factory.safeCreate2(
                salt,
                abi.encodePacked(
                    vm.getCode(
                        isGas
                            ? "foundry/artifacts-gas/YieldFacet.sol/YieldFacet.json"
                            : "foundry/artifacts/YieldFacet.sol/YieldFacet.json"
                    ),
                    abi.encode(_ditto, 2 ether)
                )
            );
        }
        _vaultFacet = factory.safeCreate2(
            salt,
            abi.encodePacked(
                vm.getCode(
                    isGas
                        ? "foundry/artifacts-gas/VaultFacet.sol/VaultFacet.json"
                        : "foundry/artifacts/VaultFacet.sol/VaultFacet.json"
                ),
                abi.encode(_deth)
            )
        );
        _bridgeRouter = factory.safeCreate2(
            salt,
            abi.encodePacked(
                vm.getCode(
                    isGas
                        ? "foundry/artifacts-gas/BridgeRouterFacet.sol/BridgeRouterFacet.json"
                        : "foundry/artifacts/BridgeRouterFacet.sol/BridgeRouterFacet.json"
                ),
                abi.encode(_bridgeReth, _bridgeSteth)
            )
        );
        _shortRecord = factory.safeCreate2(
            salt,
            abi.encodePacked(
                vm.getCode(
                    isGas
                        ? "foundry/artifacts-gas/ShortRecordFacet.sol/ShortRecordFacet.json"
                        : "foundry/artifacts/ShortRecordFacet.sol/ShortRecordFacet.json"
                ),
                abi.encode(_dusd)
            )
        );
        _askOrders = factory.safeCreate2(
            salt,
            abi.encodePacked(
                vm.getCode(
                    isGas
                        ? "foundry/artifacts-gas/AskOrdersFacet.sol/AskOrdersFacet.json"
                        : "foundry/artifacts/AskOrdersFacet.sol/AskOrdersFacet.json"
                )
            )
        );
        _shortOrders = factory.safeCreate2(
            salt,
            abi.encodePacked(
                vm.getCode(
                    isGas
                        ? "foundry/artifacts-gas/ShortOrdersFacet.sol/ShortOrdersFacet.json"
                        : "foundry/artifacts/ShortOrdersFacet.sol/ShortOrdersFacet.json"
                )
            )
        );
        _bidOrders = factory.safeCreate2(
            salt,
            abi.encodePacked(
                vm.getCode(
                    isGas
                        ? "foundry/artifacts-gas/BidOrdersFacet.sol/BidOrdersFacet.json"
                        : "foundry/artifacts/BidOrdersFacet.sol/BidOrdersFacet.json"
                )
            )
        );

        _orders = factory.safeCreate2(
            salt,
            abi.encodePacked(
                vm.getCode(
                    isGas
                        ? "foundry/artifacts-gas/OrdersFacet.sol/OrdersFacet.json"
                        : "foundry/artifacts/OrdersFacet.sol/OrdersFacet.json"
                )
            )
        );

        _exitShort = factory.safeCreate2(
            salt,
            abi.encodePacked(
                vm.getCode(
                    isGas
                        ? "foundry/artifacts-gas/ExitShortFacet.sol/ExitShortFacet.json"
                        : "foundry/artifacts/ExitShortFacet.sol/ExitShortFacet.json"
                ),
                abi.encode(_dusd)
            )
        );
        _liquidatePrimary = factory.safeCreate2(
            salt,
            abi.encodePacked(
                vm.getCode(
                    isGas
                        ? "foundry/artifacts-gas/PrimaryLiquidationFacet.sol/PrimaryLiquidationFacet.json"
                        : "foundry/artifacts/PrimaryLiquidationFacet.sol/PrimaryLiquidationFacet.json"
                ),
                abi.encode(_dusd)
            )
        );
        _liquidateSecondary = factory.safeCreate2(
            salt,
            abi.encodePacked(
                vm.getCode(
                    isGas
                        ? "foundry/artifacts-gas/SecondaryLiquidationFacet.sol/SecondaryLiquidationFacet.json"
                        : "foundry/artifacts/SecondaryLiquidationFacet.sol/SecondaryLiquidationFacet.json"
                )
            )
        );
        _marketShutdown = factory.safeCreate2(
            salt,
            abi.encodePacked(
                vm.getCode(
                    isGas
                        ? "foundry/artifacts-gas/MarketShutdownFacet.sol/MarketShutdownFacet.json"
                        : "foundry/artifacts/MarketShutdownFacet.sol/MarketShutdownFacet.json"
                )
            )
        );

        _twapFacet = factory.safeCreate2(
            salt,
            abi.encodePacked(
                vm.getCode(
                    isGas ? "foundry/artifacts-gas/TWAPFacet.sol/TWAPFacet.json" : "foundry/artifacts/TWAPFacet.sol/TWAPFacet.json"
                )
            )
        );

        _proposeRedemption = factory.safeCreate2(
            salt,
            abi.encodePacked(
                vm.getCode(
                    isGas
                        ? "foundry/artifacts-gas/ProposeRedemptionFacet.sol/ProposeRedemptionFacet.json"
                        : "foundry/artifacts/ProposeRedemptionFacet.sol/ProposeRedemptionFacet.json"
                )
            )
        );

        _disputeRedemption = factory.safeCreate2(
            salt,
            abi.encodePacked(
                vm.getCode(
                    isGas
                        ? "foundry/artifacts-gas/DisputeRedemptionFacet.sol/DisputeRedemptionFacet.json"
                        : "foundry/artifacts/DisputeRedemptionFacet.sol/DisputeRedemptionFacet.json"
                ),
                abi.encode(_dusd)
            )
        );

        _claimRedemption = factory.safeCreate2(
            salt,
            abi.encodePacked(
                vm.getCode(
                    isGas
                        ? "foundry/artifacts-gas/ClaimRedemptionFacet.sol/ClaimRedemptionFacet.json"
                        : "foundry/artifacts/ClaimRedemptionFacet.sol/ClaimRedemptionFacet.json"
                ),
                abi.encode(_dusd)
            )
        );

        if (chainId == 31337) {
            _testFacet = factory.safeCreate2(
                salt,
                abi.encodePacked(
                    vm.getCode(
                        isGas
                            ? "foundry/artifacts-gas/TestFacet.sol/TestFacet.json"
                            : "foundry/artifacts/TestFacet.sol/TestFacet.json"
                    ),
                    abi.encode(_dusd)
                )
            );

            assertNotEq(_deth, address(0));
            assertNotEq(_dusd, address(0));
            assertNotEq(_ditto, address(0));
            assertNotEq(_yDUSD, address(0));
            assertNotEq(_bridgeReth, address(0));
            assertNotEq(_bridgeSteth, address(0));
            assertNotEq(_diamond, address(0));

            _multicall3 = factory.safeCreate2(salt, abi.encodePacked(type(Multicall3).creationCode));

            testFacet = ITestFacet(_diamond);

            deth = IAsset(_deth);
            dusd = IAsset(_dusd);
            ditto = IAsset(_ditto);
            yDUSD = IyDUSD(_yDUSD);

            bridgeReth = IBridge(_bridgeReth);
            bridgeSteth = IBridge(_bridgeSteth);
        } else {
            _multicall3 = address(0xcA11bde05977b3631167028862bE2a173976CA11);
        }
    }

    function setFacets(uint256 chainId) public {
        cut.push(
            IDiamondCut.FacetCut({
                facetAddress: _diamondLoupe,
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: loupeSelectors
            })
        );
        cut.push(
            IDiamondCut.FacetCut({
                facetAddress: _shortRecord,
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: shortRecordSelectors
            })
        );
        cut.push(
            IDiamondCut.FacetCut({
                facetAddress: _vaultFacet,
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: vaultFacetSelectors
            })
        );
        cut.push(
            IDiamondCut.FacetCut({
                facetAddress: _bridgeRouter,
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: bridgeRouterSelectors
            })
        );
        cut.push(
            IDiamondCut.FacetCut({
                facetAddress: _bidOrders,
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: bidOrdersSelectors
            })
        );
        cut.push(
            IDiamondCut.FacetCut({
                facetAddress: _askOrders,
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: askOrdersSelectors
            })
        );
        cut.push(
            IDiamondCut.FacetCut({
                facetAddress: _shortOrders,
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: shortOrdersSelectors
            })
        );
        cut.push(
            IDiamondCut.FacetCut({
                facetAddress: _exitShort,
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: exitShortSelectors
            })
        );
        cut.push(
            IDiamondCut.FacetCut({
                facetAddress: _liquidatePrimary,
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: liquidatePrimarySelectors
            })
        );
        cut.push(
            IDiamondCut.FacetCut({
                facetAddress: _liquidateSecondary,
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: liquidateSecondarySelectors
            })
        );
        cut.push(
            IDiamondCut.FacetCut({
                facetAddress: _ownerFacet,
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: ownerSelectors
            })
        );
        cut.push(
            IDiamondCut.FacetCut({facetAddress: _yield, action: IDiamondCut.FacetCutAction.Add, functionSelectors: yieldSelectors})
        );
        cut.push(
            IDiamondCut.FacetCut({
                facetAddress: _viewFacet,
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: viewSelectors
            })
        );
        cut.push(
            IDiamondCut.FacetCut({
                facetAddress: _viewRedemptionFacet,
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: viewRedemptionSelectors
            })
        );
        cut.push(
            IDiamondCut.FacetCut({facetAddress: _orders, action: IDiamondCut.FacetCutAction.Add, functionSelectors: ordersSelectors})
        );
        cut.push(
            IDiamondCut.FacetCut({
                facetAddress: _marketShutdown,
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: marketShutdownSelectors
            })
        );
        cut.push(
            IDiamondCut.FacetCut({
                facetAddress: _twapFacet,
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: twapSelectors
            })
        );

        cut.push(
            IDiamondCut.FacetCut({
                facetAddress: _proposeRedemption,
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: proposeRedemptionSelectors
            })
        );
        cut.push(
            IDiamondCut.FacetCut({
                facetAddress: _disputeRedemption,
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: disputeRedemptionSelectors
            })
        );
        cut.push(
            IDiamondCut.FacetCut({
                facetAddress: _claimRedemption,
                action: IDiamondCut.FacetCutAction.Add,
                functionSelectors: claimRedemptionSelectors
            })
        );

        if (chainId == 31337) {
            cut.push(
                IDiamondCut.FacetCut({
                    facetAddress: _testFacet,
                    action: IDiamondCut.FacetCutAction.Add,
                    functionSelectors: testSelectors
                })
            );
        }
    }

    function postDeploySetup(uint256 chainId) public {
        diamond = IDiamond(payable(_diamond));
        diamond.diamondCut(cut, address(0), "");

        if (chainId == 31337 && isMock) {
            _setETH(4000 ether);
        }

        MTypes.CreateVaultParams memory vaultParams;
        vaultParams.dethTithePercent = 10_00;
        vaultParams.dittoMatchedRate = 0;
        vaultParams.dittoShorterRate = 0;
        diamond.createVault({deth: _deth, vault: VAULT.ONE, params: vaultParams});

        diamond.createBridge({
            bridge: _bridgeReth,
            vault: VAULT.ONE,
            withdrawalFee: 50 // 0.5%
        });
        diamond.createBridge({
            bridge: _bridgeSteth,
            vault: VAULT.ONE,
            withdrawalFee: 25 // 0.25%
        });

        STypes.Asset memory a;
        a.vault = uint8(VAULT.ONE);
        a.oracle = _ethAggregator;
        a.initialCR = 170; // 170 -> 1.70 ether
        a.liquidationCR = 150; // 150 -> 1.5 ether
        a.forcedBidPriceBuffer = 110; // 110 -> 1.1 ether
        a.penaltyCR = 110; // 110 -> 1.1 ether
        a.tappFeePct = 25; //25 -> .025 ether
        a.callerFeePct = 5; //5 -> .005 ether
        a.minBidEth = 10; // 1 -> 0.1 ether
        a.minAskEth = 10; // 1 -> 0.1 ether
        a.minShortErc = 2000; // 2000 -> 2000 ether
        a.recoveryCR = 150; // 150 -> 1.5 ether
        a.discountPenaltyFee = 10; // 10 -> .001 ether (.1%)
        a.discountMultiplier = 10000; // 10000 -> 10 ether (10x)
        diamond.createMarket({asset: _dusd, yieldVault: _yDUSD, a: a});

        if (chainId == 31337) {
            IDiamondLoupe.Facet[] memory facets = diamond.facets();
            // @dev first facet is DiamondCutFacet
            assertEq(facets.length, cut.length + 1);
            for (uint256 i = 0; i < facets.length - 1; i++) {
                assertNotEq(facets[i].facetAddress, address(0));
                assertEq(facets[i + 1].functionSelectors.length, cut[i].functionSelectors.length);
                for (uint256 y = 0; y < facets[i + 1].functionSelectors.length; y++) {
                    assertEq(facets[i + 1].functionSelectors[y], cut[i].functionSelectors[y]);
                }
            }

            STypes.Vault memory vaultConfig = diamond.getVaultStruct(VAULT.ONE);
            assertEq(vaultConfig.dethTithePercent, 10_00);
            assertEq(vaultConfig.dittoMatchedRate, 0);
            assertEq(vaultConfig.dittoShorterRate, 0);

            STypes.Bridge memory bridgeRethConfig = diamond.getBridgeStruct(_bridgeReth);
            STypes.Bridge memory bridgeStethConfig = diamond.getBridgeStruct(_bridgeSteth);
            assertEq(bridgeRethConfig.withdrawalFee, 50);
            assertEq(bridgeStethConfig.withdrawalFee, 25);

            STypes.Asset memory assetStruct = diamond.getAssetStruct(_dusd);
            assertEq(a.initialCR, assetStruct.initialCR);
            assertEq(a.minBidEth, assetStruct.minBidEth);
            assertEq(a.minAskEth, assetStruct.minAskEth);
            assertEq(a.minShortErc, assetStruct.minShortErc);
            assertEq(a.oracle, assetStruct.oracle);
            assertEq(VAULT.ONE, assetStruct.vault);
            assertEq(a.liquidationCR, assetStruct.liquidationCR);
            assertEq(a.penaltyCR, assetStruct.penaltyCR);
            assertEq(a.forcedBidPriceBuffer, assetStruct.forcedBidPriceBuffer);
            assertEq(a.tappFeePct, assetStruct.tappFeePct);
            assertEq(a.callerFeePct, assetStruct.callerFeePct);
            assertEq(a.recoveryCR, assetStruct.recoveryCR);
            assertEq(a.discountPenaltyFee, assetStruct.discountPenaltyFee);
        }
    }

    function _setETHChainlinkOnly(int256 amount) internal {
        ethAggregator = IMockAggregatorV3(_ethAggregator);

        ethAggregator.setRoundData(
            92233720368547778907 wei, amount / C.BASE_ORACLE_DECIMALS, block.timestamp, block.timestamp, 92233720368547778907 wei
        );
    }

    function _setETH(int256 amount) public {
        _setETHChainlinkOnly(amount);

        if (amount != 0) {
            uint256 assetPrice = (uint256(amount)).inv();
            testFacet.setOracleTimeAndPrice(_dusd, assetPrice);
        }
    }
}
