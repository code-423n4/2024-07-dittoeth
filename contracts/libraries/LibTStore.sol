// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

// import {console} from "contracts/libraries/console.sol";

library LibTStore {
    bytes32 constant forcedBidSlot = keccak256("forcedBid");

    function tstore(bytes32 slot, uint256 val) internal {
        assembly {
            tstore(slot, val)
        }
    }

    function tload(bytes32 slot) internal view returns (uint256 val) {
        assembly {
            val := tload(slot)
        }
    }

    function setForcedBid(bool forcedBid) internal {
        tstore(forcedBidSlot, forcedBid ? 1 : 0);
    }

    function isForcedBid() internal view returns (bool) {
        uint256 val;

        bytes32 slot = forcedBidSlot;
        assembly {
            val := tload(slot)
        }

        return val == 1;
    }
}
