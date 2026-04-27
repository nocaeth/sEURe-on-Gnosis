// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {IInterestReceiver} from "./IInterestReceiver.sol";
import {ISavingsEURe} from "./ISavingsEURe.sol";

/// @title ISavingsEUReAdapter
/// @notice Adapter that wraps SavingsEURe ERC4626 interactions with opportunistic interest claims.
interface ISavingsEUReAdapter {
    /// @notice Emitted when the opportunistic claim hook catches a failed claim.
    /// @param reason Raw revert data returned by `interestReceiver.claim()`.
    event ClaimFailed(bytes reason);

    /// @notice Deposits EURe into SavingsEURe and mints shares to `receiver`.
    /// @param assets Amount of EURe assets to deposit.
    /// @param receiver Address receiving minted SavingsEURe shares.
    /// @return shares Amount of SavingsEURe shares minted.
    function deposit(uint256 assets, address receiver) external returns (uint256);

    /// @notice Interest receiver claimed before user-facing vault actions.
    function interestReceiver() external view returns (IInterestReceiver);

    /// @notice Mints exactly `shares` SavingsEURe shares to `receiver`.
    /// @param shares Amount of SavingsEURe shares to mint.
    /// @param receiver Address receiving minted SavingsEURe shares.
    /// @return assets Amount of EURe assets deposited.
    function mint(uint256 shares, address receiver) external returns (uint256);

    /// @notice Withdraws up to `assets` EURe from the caller's SavingsEURe position.
    /// @param assets Requested amount of EURe assets to withdraw.
    /// @param receiver Address receiving withdrawn EURe assets.
    /// @return shares Amount of SavingsEURe shares burned.
    function withdraw(uint256 assets, address receiver) external returns (uint256);

    /// @notice Redeems up to `shares` SavingsEURe shares from the caller's position.
    /// @param shares Requested amount of SavingsEURe shares to redeem.
    /// @param receiver Address receiving withdrawn EURe assets.
    /// @return assets Amount of EURe assets withdrawn.
    function redeem(uint256 shares, address receiver) external returns (uint256);

    /// @notice Redeems the caller's full SavingsEURe share balance.
    /// @param receiver Address receiving withdrawn EURe assets.
    /// @return assets Amount of EURe assets withdrawn.
    function redeemAll(address receiver) external returns (uint256);

    /// @notice SavingsEURe vault operated by the adapter.
    function sEURe() external view returns (ISavingsEURe);

    /// @notice Returns the instantaneous vault APY reported by the interest receiver.
    /// @return apy Annualized EURe drip divided by vault assets, scaled by 1e18.
    function vaultAPY() external view returns (uint256);

    /// @notice EURe token deposited into the SavingsEURe vault.
    function eure() external view returns (IERC20);
}
