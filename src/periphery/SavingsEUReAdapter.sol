// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {IInterestReceiver} from "../interfaces/IInterestReceiver.sol";
import {ISavingsEUReAdapter} from "../interfaces/ISavingsEUReAdapter.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ISavingsEURe} from "../interfaces/ISavingsEURe.sol";

contract SavingsEUReAdapter is ISavingsEUReAdapter {
    using SafeERC20 for IERC20;

    /// @inheritdoc ISavingsEUReAdapter
    IInterestReceiver public immutable override interestReceiver;

    /// @inheritdoc ISavingsEUReAdapter
    ISavingsEURe public immutable override sEURe;

    /// @inheritdoc ISavingsEUReAdapter
    IERC20 public immutable override eure = IERC20(0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430);

    constructor(address interestReceiver_, address payable savingsEuRe_) {
        interestReceiver = IInterestReceiver(interestReceiver_);
        sEURe = ISavingsEURe(savingsEuRe_);
        eure.approve(savingsEuRe_, type(uint256).max);
    }

    // only EOAs are able to claim interest.
    modifier claim() {
        _claimHook();
        _;
    }

    function _claimHook() internal {
        if (msg.sender == tx.origin) {
            try interestReceiver.claim() {}
            catch (bytes memory reason) {
                emit ClaimFailed(reason);
            }
        }
    }

    /// @inheritdoc ISavingsEUReAdapter
    function deposit(uint256 assets, address receiver) public override claim returns (uint256) {
        eure.safeTransferFrom(msg.sender, address(this), assets);
        uint256 shares = sEURe.deposit(assets, receiver);
        return shares;
    }

    /// @inheritdoc ISavingsEUReAdapter
    function mint(uint256 shares, address receiver) public override claim returns (uint256) {
        eure.safeTransferFrom(msg.sender, address(this), sEURe.previewMint(shares));
        uint256 assets = sEURe.mint(shares, receiver);
        return assets;
    }

    /// @inheritdoc ISavingsEUReAdapter
    function withdraw(uint256 assets, address receiver) public override claim returns (uint256) {
        uint256 maxAssets = sEURe.maxWithdraw(msg.sender);
        assets = (assets > maxAssets) ? maxAssets : assets;
        return sEURe.withdraw(assets, receiver, msg.sender);
    }

    /// @inheritdoc ISavingsEUReAdapter
    function redeem(uint256 shares, address receiver) public override claim returns (uint256) {
        uint256 maxShares = sEURe.maxRedeem(msg.sender);
        shares = (shares > maxShares) ? maxShares : shares;
        return sEURe.redeem(shares, receiver, msg.sender);
    }

    /// @inheritdoc ISavingsEUReAdapter
    function redeemAll(address receiver) public override claim returns (uint256) {
        uint256 shares = sEURe.balanceOf(msg.sender);
        return sEURe.redeem(shares, receiver, msg.sender);
    }

    /// @inheritdoc ISavingsEUReAdapter
    function vaultAPY() external view override returns (uint256) {
        return interestReceiver.vaultAPY();
    }
}
