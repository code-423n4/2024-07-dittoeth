// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {STypes} from "contracts/libraries/DataTypes.sol";
import {InvariantsBase} from "./InvariantsBase.sol";

import {console} from "contracts/libraries/console.sol";

/// @dev This contract deploys the target contract, the Handler, adds the Handler's actions to the invariant fuzzing
/// @dev targets, then defines invariants that should always hold throughout any invariant run.
contract InvariantsNFT is InvariantsBase {
    function setUp() public override {
        super.setUp();

        targetSelector(FuzzSelector({addr: address(s_handler), selectors: selectors}));
        targetContract(address(s_handler));
    }

    function statefulFuzz_NFT() public view {
        NFTsHaveOnlyOneShortRecord();
        TokenIdOnlyIncreases();

        // console.log(s_handler.ghost_mintNFT());
        // console.log(s_handler.ghost_mintNFTComplete());
        // console.log(s_handler.ghost_transferNFT());
        // console.log(s_handler.ghost_transferNFTComplete());
    }

    function NFTsHaveOnlyOneShortRecord() public view {
        address[] memory users = s_handler.getUsers();
        for (uint256 i = 0; i < users.length; i++) {
            STypes.ShortRecord[] memory shortRecords = diamond.getShortRecords(asset, users[i]);
            for (uint256 j = 0; j < shortRecords.length; j++) {
                STypes.ShortRecord memory shortRecord = shortRecords[j];
                uint40 tokenId = shortRecord.tokenId;
                if (tokenId == 0) {
                    continue;
                } else {
                    STypes.NFT memory nft = diamond.getNFT(tokenId);
                    assertEq(nft.shortRecordId, shortRecord.id);
                    assertEq(nft.owner, users[i]);
                }
            }
        }
    }

    function TokenIdOnlyIncreases() public view {
        assertGe(diamond.getTokenId(), s_handler.ghost_tokenIdCounter());
    }
}
