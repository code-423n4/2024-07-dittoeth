// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {ERC20, ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract STETH is ERC20, ERC20Permit {
    constructor() ERC20("Liquid staked Ether 2.0", "stETH") ERC20Permit("Liquid staked Ether 2.0") {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }

    function burn(uint256 amount) public {
        _burn(msg.sender, amount);
    }

    // @dev mock should only be called from unsteth
    function transferWithdrawalEth(uint256 amount) external {
        (bool sent,) = msg.sender.call{value: amount}("");
        assert(sent);
    }

    function submit(address ref) external payable returns (uint256) {
        if (ref == address(0)) {
            _mint(msg.sender, msg.value);
        }
        return msg.value;
    }

    // @dev getWstETHByStETH() function from WstETH
    function getPooledEthByShares(uint256 amount) public view returns (uint256) {}
}
