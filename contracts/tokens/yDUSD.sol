// SPDX-License-Identifier: GPL-3.0-only
pragma solidity 0.8.25;

import {U256} from "contracts/libraries/PRBMathHelper.sol";

import {IDiamond} from "interfaces/IDiamond.sol";
import {IAsset} from "interfaces/IAsset.sol";

import {ERC4626, ERC20} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Errors} from "contracts/libraries/Errors.sol";
import {C} from "contracts/libraries/Constants.sol";
import {console} from "contracts/libraries/console.sol";

contract yDUSD is ERC4626 {
    using U256 for uint256;

    address private immutable dusd;
    address private immutable diamond;

    struct WithdrawStruct {
        uint40 timeProposed;
        uint104 amountProposed;
    }

    mapping(address account => WithdrawStruct) withdrawals;

    constructor(string memory name, string memory symbol, IERC20 dusdAddress, address _diamond)
        ERC4626(dusdAddress)
        ERC20(name, symbol)
    {
        dusd = address(dusdAddress);
        diamond = _diamond;
    }

    function checkDiscountWindow() internal {
        //Note: Will upgrade contract to diamond in the future
        bool WithinDiscountWindow = IDiamond(payable(diamond)).getTimeSinceDiscounted(dusd) < C.DISCOUNT_WAIT_TIME;
        bool isDiscounted = IDiamond(payable(diamond)).getInitialDiscountTime(dusd) > 1 seconds;
        if (isDiscounted || WithinDiscountWindow) revert Errors.ERC4626CannotWithdrawBeforeDiscountWindowExpires();
    }

    function proposeWithdraw(uint104 amountProposed) public {
        if (amountProposed <= 1) revert Errors.ERC4626AmountProposedTooLow();
        WithdrawStruct storage withdrawal = withdrawals[msg.sender];

        if (withdrawal.timeProposed > 0) revert Errors.ERC4626ExistingWithdrawalProposal();

        if (amountProposed > maxWithdraw(msg.sender)) revert Errors.ERC4626WithdrawMoreThanMax();

        checkDiscountWindow();

        withdrawal.timeProposed = uint40(block.timestamp);
        withdrawal.amountProposed = amountProposed;
    }

    function cancelWithdrawProposal() public {
        WithdrawStruct storage withdrawal = withdrawals[msg.sender];

        if (withdrawal.timeProposed == 0 && withdrawal.amountProposed <= 1) revert Errors.ERC4626ProposeWithdrawFirst();

        delete withdrawal.timeProposed;
        withdrawal.amountProposed = 1;
    }

    function deposit(uint256 assets, address receiver) public override returns (uint256) {
        if (assets > maxDeposit(receiver)) revert Errors.ERC4626DepositMoreThanMax();

        uint256 shares = previewDeposit(assets);

        uint256 oldBalance = balanceOf(receiver);
        _deposit(_msgSender(), receiver, assets, shares);
        uint256 newBalance = balanceOf(receiver);

        // @dev Slippage is likely irrelevant for this. Merely for preventative purposes
        uint256 slippage = 0.01 ether;
        if (newBalance < slippage.mul(shares) + oldBalance) revert Errors.ERC4626DepositSlippageExceeded();

        return shares;
    }

    // @dev User can ONLY withdraw if they propose a withdraw ahead of time
    // @dev The assets parameter is unused
    function withdraw(uint256 assets, address receiver, address owner) public override returns (uint256) {
        WithdrawStruct storage withdrawal = withdrawals[msg.sender];
        uint256 amountProposed = withdrawal.amountProposed;
        uint256 timeProposed = withdrawal.timeProposed;

        if (timeProposed == 0 && amountProposed <= 1) revert Errors.ERC4626ProposeWithdrawFirst();

        if (timeProposed + C.WITHDRAW_WAIT_TIME > uint40(block.timestamp)) revert Errors.ERC4626WaitLongerBeforeWithdrawing();

        // @dev After 7 days from proposing, a user has 45 days to withdraw
        // @dev User will need to cancelWithdrawProposal() and proposeWithdraw() again
        if (timeProposed + C.WITHDRAW_WAIT_TIME + C.MAX_WITHDRAW_TIME <= uint40(block.timestamp)) {
            revert Errors.ERC4626MaxWithdrawTimeHasElapsed();
        }

        if (amountProposed > maxWithdraw(owner)) revert Errors.ERC4626WithdrawMoreThanMax();

        checkDiscountWindow();

        uint256 shares = previewWithdraw(amountProposed);

        IAsset _dusd = IAsset(dusd);
        uint256 oldBalance = _dusd.balanceOf(receiver);
        _withdraw(_msgSender(), receiver, owner, amountProposed, shares);
        uint256 newBalance = _dusd.balanceOf(receiver);

        // @dev Slippage is likely irrelevant for this. Merely for preventative purposes
        uint256 slippage = 0.01 ether;
        if (newBalance < slippage.mul(amountProposed) + oldBalance) revert Errors.ERC4626WithdrawSlippageExceeded();

        delete withdrawal.timeProposed;
        //reset withdrawal (1 to keep slot warm)
        withdrawal.amountProposed = 1;

        return shares;
    }

    /////Getters/////

    function getTimeProposed(address account) external view returns (uint40) {
        return withdrawals[account].timeProposed;
    }

    function getAmountProposed(address account) external view returns (uint104) {
        return withdrawals[account].amountProposed;
    }

    /////Locked Functions/////
    function mint(uint256 shares, address receiver) public override returns (uint256) {
        revert Errors.ERC4626CannotMint();
    }

    function redeem(uint256 shares, address receiver, address owner) public override returns (uint256) {
        revert Errors.ERC4626CannotRedeem();
    }
}
