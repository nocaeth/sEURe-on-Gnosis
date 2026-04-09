// SPDX-License-Identifier: agpl-3
pragma solidity ^0.8.19;

import "../interfaces/IInterestReceiver.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SavingsEURe} from "../SavingsEURe.sol";

contract SavingsEUReAdapter {
    IInterestReceiver public immutable interestReceiver;
    SavingsEURe public immutable sEURe;
    IERC20 public immutable eure = IERC20(0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430);

    constructor(address interestReceiver_, address payable sEURe_) {
        interestReceiver = IInterestReceiver(interestReceiver_);
        sEURe = SavingsEURe(sEURe_);
        eure.approve(sEURe_, type(uint256).max);
    }

    // only EOAs are able to claim interest.
    modifier claim() {
        if (msg.sender == tx.origin) {
            interestReceiver.claim();
        }
        _;
    }

    function deposit(uint256 assets, address receiver) public claim() returns (uint256) {
        eure.transferFrom(msg.sender, address(this), assets);
        uint256 shares = sEURe.deposit(assets, receiver);
        return shares;
    }

    function mint(uint256 shares, address receiver) public claim() returns (uint256) {
        eure.transferFrom(msg.sender, address(this), sEURe.convertToAssets(shares));
        uint256 assets = sEURe.mint(shares, receiver);
        return assets;
    }

    function withdraw(uint256 assets, address receiver) public claim() returns (uint256) {
        uint256 maxAssets = sEURe.maxWithdraw(msg.sender);
        assets = (assets > maxAssets) ? maxAssets : assets;
        return sEURe.withdraw(assets, receiver, msg.sender);
    }

    function redeem(uint256 shares, address receiver) public claim() returns (uint256) {
        uint256 maxShares = sEURe.maxRedeem(msg.sender);
        shares = (shares > maxShares) ? maxShares : shares;
        return sEURe.redeem(shares, receiver, msg.sender);
    }

    function redeemAll(address receiver) public claim() returns (uint256) {
        uint256 shares = sEURe.balanceOf(msg.sender);
        return sEURe.redeem(shares, receiver, msg.sender);
    }

    function vaultAPY() external view returns (uint256) {
        return interestReceiver.vaultAPY();
    }
}
