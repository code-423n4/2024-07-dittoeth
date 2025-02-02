// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {AppStorage, appStorage} from "contracts/libraries/AppStorage.sol";
import {C} from "contracts/libraries/Constants.sol";
import {U256} from "contracts/libraries/PRBMathHelper.sol";

// import {console} from "contracts/libraries/console.sol";

library LibBridge {
    using U256 for uint256;

    // default of .0050 ether, stored in uint16 as 50
    // range of [0-15%],
    // 4 decimal places, divide by 10000
    // i.e. 1234 -> .1234 ether -> 12.34%
    // @dev fee to withdrawal from that bridge
    function withdrawalFee(address bridge) internal view returns (uint256) {
        AppStorage storage s = appStorage();
        return (uint256(s.bridge[bridge].withdrawalFee) * 1 ether) / C.FOUR_DECIMAL_PLACES;
    }
}
