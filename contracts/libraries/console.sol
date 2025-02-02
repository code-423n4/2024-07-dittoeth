// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {U256} from "contracts/libraries/PRBMathHelper.sol";
import {AppStorage, appStorage} from "contracts/libraries/AppStorage.sol";
import {Strings} from "@openzeppelin/contracts/utils/Strings.sol";

import {IDiamondLoupe} from "contracts/interfaces/IDiamondLoupe.sol";
import {STypes, MTypes, O, SR} from "contracts/libraries/DataTypes.sol";
import {C} from "contracts/libraries/Constants.sol";
import {TestTypes} from "test/utils/TestTypes.sol";

address constant CONSOLE_ADDRESS = address(0x000000000000000000636F6e736F6c652e6c6f67);

/* solhint-disable */
function _castLogPayloadViewToPure(function(bytes memory) internal view fnIn)
    pure
    returns (function(bytes memory) internal pure fnOut)
{
    assembly {
        fnOut := fnIn
    }
}

function _sendLogPayload(bytes memory payload) pure {
    _castLogPayloadViewToPure(_sendLogPayloadView)(payload);
}

function _sendLogPayloadView(bytes memory payload) view {
    uint256 payloadLength = payload.length;
    address consoleAddress = CONSOLE_ADDRESS;
    assembly {
        let payloadStart := add(payload, 32)
        let r := staticcall(gas(), consoleAddress, payloadStart, payloadLength, 0, 0)
    }
}
/* solhint-enable */

// solhint-disable-next-line contract-name-camelcase
library console {
    using U256 for uint256;

    function logBytes(bytes memory p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes)", p0));
    }

    function logBytes1(bytes1 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes1)", p0));
    }

    function logBytes4(bytes4 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes4)", p0));
    }

    function logBytes8(bytes8 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes8)", p0));
    }

    function logBytes11(bytes11 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bytes11)", p0));
    }

    function log(uint256 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint)", p0));
    }

    function log(uint256 p0, uint256 p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,uint)", p0, p1));
    }

    function log(uint256 p0, uint256 p1, uint256 p2) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint,uint,uint)", p0, p1, p2));
    }

    function log(int256 p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(int)", p0));
    }

    function log(string memory p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string)", p0));
    }

    function log(bool p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(bool)", p0));
    }

    function log(address p0) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(address)", p0));
    }

    function log(string memory p0, uint256 p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint)", p0, p1));
    }

    function log(string memory p0, string memory p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,string)", p0, p1));
    }

    function log(string memory p0, bool p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,bool)", p0, p1));
    }

    function log(string memory p0, address p1) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,address)", p0, p1));
    }

    function log(string memory p0, uint256 p1, uint256 p2, string memory p3) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint,uint,string)", p0, p1, p2, p3));
    }

    function log(O o) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint)", o));
    }

    function log(SR status) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(uint)", status));
    }

    // @dev may not be in sync with DataTypes
    function orderTypetoString(O o) private pure returns (string memory orderType) {
        string[] memory typeToString = new string[](8);
        typeToString[0] = "Uninitialized";
        typeToString[1] = "LimitBid";
        typeToString[2] = "LimitAsk";
        typeToString[3] = "MarketBid";
        typeToString[4] = "MarketAsk";
        typeToString[5] = "LimitShort";
        typeToString[6] = "Cancelled";
        typeToString[7] = "Matched";
        return typeToString[uint8(o)];
    }

    function orderTypetoString2(O o) private pure returns (string memory orderType) {
        string[] memory typeToString = new string[](8);
        typeToString[0] = "U!";
        typeToString[1] = "LB";
        typeToString[2] = "LA";
        typeToString[3] = "MA";
        typeToString[4] = "MB";
        typeToString[5] = "LS";
        typeToString[6] = "C!";
        typeToString[7] = "M!";
        return typeToString[uint8(o)];
    }

    function padId(uint16 id) private pure returns (string memory _id) {
        if (id == 1) {
            return "HED";
        }

        return Strings.toString(id);
    }

    function shortRecordStatustoString(SR s) private pure returns (string memory orderType) {
        string[] memory typeToString = new string[](3);
        typeToString[0] = "PartialFill";
        typeToString[1] = "FullyFilled";
        typeToString[2] = "Cancelled";
        return typeToString[uint8(s)];
    }

    function addrToString(address a) private pure returns (string memory label) {
        // 0x0000000000000000000000000000000000000002 -> 2
        string[] memory typeToString = new string[](4);
        typeToString[0] = "zero(0)";
        typeToString[1] = "receiver(1)";
        typeToString[2] = "sender(2)";
        typeToString[3] = "extra(3)";

        uint160 num = uint160(a);

        if (num <= 3) {
            return typeToString[num];
        }
        return "addr";
    }

    function newLine() internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string)", ""));
    }

    function logId(STypes.Order memory _order) internal pure {
        string memory orderType = orderTypetoString2(_order.orderType);
        _sendLogPayload(
            abi.encodeWithSignature(
                "log(string,string,string,string)",
                _order.id == C.HEAD ? "H!" : orderType,
                padId(_order.prevId),
                padId(_order.id),
                padId(_order.nextId)
            )
        );
    }

    function log(IDiamondLoupe.Facet memory _facet) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string)", "Facet"));
        _sendLogPayload(abi.encodeWithSignature("log(string,address)", "facetAddress:", _facet.facetAddress));
        for (uint256 i = 0; i < _facet.functionSelectors.length; i++) {
            logBytes4(_facet.functionSelectors[i]);
        }
        newLine();
    }

    function log(IDiamondLoupe.Facet[] memory _facets) internal pure {
        for (uint256 i = 0; i < _facets.length; i++) {
            log(_facets[i]);
        }
    }

    function log(STypes.Order memory _order) internal pure {
        if (_order.id == 1) {
            _sendLogPayload(abi.encodeWithSignature("log(string,uint,uint,uint)", "HEAD:", _order.prevId, _order.id, _order.nextId));
        } else {
            _sendLogPayload(
                abi.encodeWithSignature(
                    "log(string)",
                    string.concat(
                        orderTypetoString(_order.orderType),
                        // Strings.toString(uint8(_order.orderType)),
                        ": ",
                        addrToString(_order.addr),
                        ", cTime: ",
                        Strings.toString(_order.creationTime),
                        ", iCR: ",
                        Strings.toString(_order.shortOrderCR)
                    )
                )
            );
            _sendLogPayload(
                abi.encodeWithSignature("log(string,uint,uint,uint)", "id(s):", _order.prevId, _order.id, _order.nextId)
            );
            _sendLogPayload(abi.encodeWithSignature("log(string,uint)", "price:", _order.price));
            _sendLogPayload(abi.encodeWithSignature("log(string,uint)", "ercAmount:", _order.ercAmount));
            _sendLogPayload(abi.encodeWithSignature("log(string,uint)", "shortRecordId:", _order.shortRecordId));
        }

        newLine();
    }

    function log(STypes.Order[] memory _orders) internal pure {
        for (uint256 i = 0; i < _orders.length; i++) {
            log(_orders[i]);
        }
    }

    function log(STypes.ShortRecord memory _short) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string)", "Short"));
        _sendLogPayload(abi.encodeWithSignature("log(string,uint,uint)", "id(s):", _short.prevId, _short.nextId));
        _sendLogPayload(abi.encodeWithSignature("log(string,uint)", "updatedAt:", _short.updatedAt));
        _sendLogPayload(abi.encodeWithSignature("log(string,uint)", "dethYieldRate:", _short.dethYieldRate));
        _sendLogPayload(abi.encodeWithSignature("log(string,uint)", "collateral:", _short.collateral));
        _sendLogPayload(abi.encodeWithSignature("log(string)", shortRecordStatustoString(_short.status)));

        _sendLogPayload(abi.encodeWithSignature("log(string,uint)", "ercDebt:", _short.ercDebt));
        _sendLogPayload(abi.encodeWithSignature("log(string,uint)", "ercDebtFee:", _short.ercDebtFee));
    }

    function zeroPad(uint256 length, uint256 number) internal pure returns (string memory) {
        string memory numberStr = Strings.toString(number);

        uint256 zeros = length - bytes(numberStr).length;
        bytes memory buffer = new bytes(length);
        uint256 index = 0;
        while (index < zeros) {
            buffer[index++] = "0";
        }
        for (uint256 i = 0; i < bytes(numberStr).length; i++) {
            buffer[index++] = bytes(numberStr)[i];
        }
        return string(buffer);
    }

    function weiToEther(uint256 amountInWei) public pure returns (string memory) {
        // Convert wei to ether (1 ether = 10^18 wei)
        uint256 amountInEther = amountInWei / 1 ether;
        // Calculate the fractional part (wei remaining after converting to ether)
        uint256 fractionalWei = amountInWei % 1 ether;
        string memory fractionalString = zeroPad(18, fractionalWei);
        return string.concat(Strings.toString(amountInEther), ".", fractionalString);
    }

    function logErcDebt(address user, uint256 ercDebt) internal pure {
        string memory ercDebtInEther = weiToEther(ercDebt);

        if (uint256(uint160(user)) < 9) {
            _sendLogPayload(
                abi.encodeWithSignature("log(string,string)", string.concat("0x", Strings.toString(uint160(user))), ercDebtInEther)
            );
        } else {
            _sendLogPayload(abi.encodeWithSignature("log(address,string)", user, ercDebtInEther));
        }
    }

    function log(STypes.ShortRecord[] memory _srs) internal pure {
        for (uint256 i = 0; i < _srs.length; i++) {
            log(_srs[i]);
        }
    }

    function log(TestTypes.StorageUser memory _storageUser) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string)", "Storage User"));
        _sendLogPayload(abi.encodeWithSignature("log(string,address)", "addr:", _storageUser.addr));
        _sendLogPayload(abi.encodeWithSignature("log(string,uint)", "ethEscrowed:", _storageUser.ethEscrowed));
        _sendLogPayload(abi.encodeWithSignature("log(string,uint)", "ercEscrowed:", _storageUser.ercEscrowed));
    }

    function log(MTypes.BidMatchAlgo memory _b) internal pure {
        _sendLogPayload(abi.encodeWithSignature("log(string,uint)", "askId", _b.askId));
        _sendLogPayload(abi.encodeWithSignature("log(string,uint)", "shortHintId", _b.shortHintId));
        _sendLogPayload(abi.encodeWithSignature("log(string,uint)", "shortId", _b.shortId));
        _sendLogPayload(abi.encodeWithSignature("log(string,uint)", "prevShortId", _b.prevShortId));
        _sendLogPayload(abi.encodeWithSignature("log(string,uint)", "firstShortIdBelowOracle", _b.firstShortIdBelowOracle));
        _sendLogPayload(abi.encodeWithSignature("log(string,uint)", "matchedAskId", _b.matchedAskId));
        _sendLogPayload(abi.encodeWithSignature("log(string,uint)", "matchedShortId", _b.matchedShortId));
        _sendLogPayload(abi.encodeWithSignature("log(string,bool)", "isMovingBack", _b.isMovingBack));
        _sendLogPayload(abi.encodeWithSignature("log(string,bool)", "isMovingFwd", _b.isMovingFwd));
        _sendLogPayload(abi.encodeWithSignature("log(string,uint)", "oraclePrice", _b.oraclePrice));
    }

    /* solhint-disable no-console */
    function logBids(address asset) external view {
        AppStorage storage s = appStorage();
        STypes.Order memory o = s.bids[asset][C.HEAD];
        console.log(o);

        uint16 currentId = o.nextId;
        while (currentId != C.TAIL) {
            o = s.bids[asset][currentId];
            console.log(o);
            currentId = o.nextId;
        }
        console.log("--");
    }

    function logAsks(address asset) external view {
        AppStorage storage s = appStorage();
        STypes.Order memory o = s.asks[asset][C.HEAD];
        console.log(o);
        uint16 currentId = o.nextId;
        while (currentId != C.TAIL) {
            o = s.asks[asset][currentId];
            console.log(o);
            currentId = o.nextId;
        }
        console.log("--");
    }

    function logShorts(address asset) external view {
        AppStorage storage s = appStorage();
        STypes.Order memory o = s.shorts[asset][C.HEAD];
        console.log(o);
        uint16 currentId = o.nextId;
        while (currentId != C.TAIL) {
            o = s.shorts[asset][currentId];
            console.log(o);
            currentId = o.nextId;
        }
        console.log("--");
    }

    function logInactiveBids(address asset) external view {
        AppStorage storage s = appStorage();
        STypes.Order memory o = s.bids[asset][C.HEAD];
        console.log(o);
        uint16 currentId = o.prevId;
        while (currentId != C.HEAD) {
            o = s.bids[asset][currentId];
            console.log(o);
            currentId = o.prevId;
        }
        console.log("--");
    }

    function logInactiveAsks(address asset) external view {
        AppStorage storage s = appStorage();
        STypes.Order memory o = s.asks[asset][C.HEAD];
        console.log(o);
        uint16 currentId = o.prevId;
        while (currentId != C.HEAD) {
            o = s.asks[asset][currentId];
            console.log(o);
            currentId = o.prevId;
        }
        console.log("--");
    }

    function logInactiveShorts(address asset) external view {
        AppStorage storage s = appStorage();
        STypes.Order memory o = s.shorts[asset][C.HEAD];
        console.log(o);
        uint16 currentId = o.prevId;
        while (currentId != C.HEAD) {
            o = s.shorts[asset][currentId];
            console.log(o);
            currentId = o.prevId;
        }
        console.log("--");
    }

    function logAllShorts(address asset) internal view {
        AppStorage storage s = appStorage();
        uint16 currentId = s.shorts[asset][C.HEAD].prevId;
        uint256 prevOrderSize;
        uint256 nextOrderSize;
        uint16 lastPrevId = C.HEAD;
        while (currentId != C.HEAD) {
            lastPrevId = currentId;
            currentId = s.shorts[asset][currentId].prevId;
            prevOrderSize++;
        }
        currentId = s.shorts[asset][C.HEAD].nextId;
        while (currentId != C.TAIL) {
            nextOrderSize++;
            currentId = s.shorts[asset][currentId].nextId;
        }

        STypes.Order[] memory orderArr = new STypes.Order[](prevOrderSize + nextOrderSize + 1);
        orderArr[prevOrderSize] = s.shorts[asset][C.HEAD];

        currentId = s.shorts[asset][C.HEAD].prevId;
        for (uint256 i = 0; i < prevOrderSize; i++) {
            orderArr[prevOrderSize - i - 1] = s.shorts[asset][currentId];
            currentId = s.shorts[asset][currentId].prevId;
        }
        currentId = s.shorts[asset][C.HEAD].nextId;
        for (uint256 i = 0; i < nextOrderSize; i++) {
            orderArr[prevOrderSize + i + 1] = s.shorts[asset][currentId];
            currentId = s.shorts[asset][currentId].nextId;
        }

        console.log("==LOG SHORTS==");
        for (uint256 i = 0; i < orderArr.length; i++) {
            console.logId(orderArr[i]);
        }
        console.log("== ==");
    }
}
