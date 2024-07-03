// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {MTypes} from "contracts/libraries/DataTypes.sol";
import {SSTORE2} from "solmate/utils/SSTORE2.sol";

// import {console} from "contracts/libraries/console.sol";

library LibBytes {
    // Custom decode since SSTORE.write was written directly in proposeRedemption
    function readProposalData(address SSTORE2Pointer, uint8 slateLength)
        internal
        view
        returns (uint32, uint32, uint80, uint80, MTypes.ProposalData[] memory)
    {
        bytes memory slate = SSTORE2.read(SSTORE2Pointer);

        // ProposalData is 62 bytes
        // -28 to account for timeProposed, timeToDispute, oraclePrice, and ercDebtRate at start of slate
        uint256 proposalDataSize = 62;
        require((slate.length - 28) % proposalDataSize == 0, "Invalid data length");

        MTypes.ProposalData[] memory data = new MTypes.ProposalData[](slateLength);

        for (uint256 i = 0; i < slateLength; i++) {
            // 28 for fixed timeProposed, timeToDispute, oraclePrice, and ercDebtRate values
            // 32 offset for array length, mulitply by each ProposalData
            uint256 offset = i * proposalDataSize + 28 + 32;

            address shorter; // bytes20
            uint8 shortId; // bytes1
            uint64 CR; // bytes8
            uint88 ercDebtRedeemed; // bytes11
            uint88 colRedeemed; // bytes11
            uint88 ercDebtFee; // bytes11

            assembly {
                // mload works 32 bytes at a time
                let fullWord := mload(add(slate, offset))

                // read 20 bytes (160 bits)
                shorter := shr(96, fullWord) // 0x60 = 96 (256-160)
                // read 1 bytes (8 bits)
                shortId := and(0xff, shr(88, fullWord)) // 0x58 = 88 (96-8), mask of bytes1 = 0xff * 1
                // read 8 bytes (64 bits)
                CR := and(0xffffffffffffffff, shr(24, fullWord)) // 0x18 = 24 (88-64), mask of bytes8 = 0xff * 8

                fullWord := mload(add(slate, add(offset, 29))) // (29 offset)
                // read 11 bytes (88 bits)
                ercDebtRedeemed := shr(168, fullWord) // (256-88 = 168)
                // read 11 bytes (88 bits)
                colRedeemed := and(0xffffffffffffffffffffff, shr(80, fullWord)) // (256-88-88 = 80), mask of bytes11 = 0xff * 11

                fullWord := mload(add(slate, add(offset, 51))) // (51 offset)
                // read 11 bytes (88 bits)
                ercDebtFee := shr(168, fullWord) // (256-88 = 168)
            }

            data[i] = MTypes.ProposalData({
                shorter: shorter,
                shortId: shortId,
                CR: CR,
                ercDebtRedeemed: ercDebtRedeemed,
                colRedeemed: colRedeemed,
                ercDebtFee: ercDebtFee
            });
        }

        uint32 timeProposed; // bytes4
        uint32 timeToDispute; // bytes4
        uint80 oraclePrice; //bytes10
        uint80 ercDebtRate; //bytes10
        assembly {
            // 32 length
            let fullWord := mload(add(slate, 32))
            // read 4 bytes (32 bits)
            timeProposed := shr(224, fullWord) //256 - 32
            // read 4 bytes (32 bits)
            timeToDispute := and(0xffffffff, shr(192, fullWord)) //224 - 32, mask of bytes4 = 0xff * 4
            // read 10 bytes (80 bits)
            oraclePrice := and(0xffffffffffffffffffff, shr(112, fullWord)) //192 - 80, mask of bytes4 = 0xff * 10
            // read 10 bytes (80 bits)
            ercDebtRate := and(0xffffffffffffffffffff, shr(32, fullWord)) //112 - 80, mask of bytes4 = 0xff * 10
        }

        return (timeProposed, timeToDispute, oraclePrice, ercDebtRate, data);
    }
}
