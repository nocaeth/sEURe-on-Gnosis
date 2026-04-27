// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {ISavingsEURe} from "./ISavingsEURe.sol";

/// @title IInterestReceiver
/// @notice Drips externally funded EURe yield into the SavingsEURe ERC4626 vault.
/// @dev
/// The receiver is funded externally with EURe and releases that balance into the vault over epochs.
/// EOAs may trigger claims directly. Contract callers are restricted to `claimer`, which is expected to be
/// the adapter after deployment so user interactions can opportunistically pull yield without letting
/// arbitrary contracts manipulate claim timing.
interface IInterestReceiver {
    /// @notice Caller tried to use a function before the receiver was initialized.
    error NotInitialized();

    /// @notice Caller is not the configured claimer.
    error NotClaimer();

    /// @notice Caller is neither an EOA nor the configured claimer contract.
    error NotValidClaimer();

    /// @notice Available EURe balance is below `MIN_EPOCH_BALANCE`.
    error InsufficientInitialBalance();

    /// @notice Address argument cannot be zero.
    error ZeroAddress();

    /// @notice Emitted when EURe yield is transferred into the vault.
    /// @param amount Amount of EURe transferred to the vault.
    event Claimed(uint256 indexed amount);

    /// @notice Emitted when the initial drip epoch is configured.
    /// @param initialBalance EURe balance used to seed the initial epoch.
    /// @param dripRate EURe released per second during the initial epoch.
    /// @param nextClaimEpoch Timestamp at which the initial epoch can roll over.
    event Initialized(uint256 indexed initialBalance, uint256 dripRate, uint256 nextClaimEpoch);

    /// @notice Emitted when the contract claimer changes.
    /// @param previousClaimer Previous claimer address.
    /// @param newClaimer New claimer address.
    event ClaimerUpdated(address indexed previousClaimer, address indexed newClaimer);

    /// @notice Initializes the first drip epoch.
    /// @dev Requires enough EURe to avoid a zero `dripRate`. Can only be called once by the current claimer.
    function initialize() external;

    /// @notice Transfers currently claimable EURe yield into the SavingsEURe vault.
    /// @dev
    /// EOAs may call this directly. Contract callers must be `claimer`.
    /// Calling twice in the same block returns 0 and leaves state unchanged.
    /// If the receiver has no EURe balance, time is not advanced so future funding remains claimable.
    /// @return claimed Amount of EURe transferred into the vault.
    function claim() external returns (uint256);

    /// @notice Returns the instantaneous vault APY implied by the current drip rate.
    /// @dev This is not a trailing realized APY. It returns 0 before initialization, when no yield is dripping,
    /// or when the vault has no assets. Because rollover accounting uses the receiver's live EURe balance,
    /// direct EURe transfers to this receiver can affect future `dripRate` values and this APY after rollover.
    /// Integrators MUST NOT use this value as an oracle or risk input without independent validation.
    /// @return apy Annualized EURe drip divided by vault assets, scaled by 1e18.
    function vaultAPY() external view returns (uint256);

    /// @notice Updates the contract caller allowed to trigger `claim`.
    /// @dev
    /// This is intentionally one-step because the claimer is expected to become the adapter contract,
    /// which cannot accept a two-step handoff. EOAs can still call `claim` directly regardless of this value.
    /// @param newClaimer New contract claimer address.
    function setClaimer(address newClaimer) external;

    /// @notice Minimum EURe balance required to initialize or start a drip epoch.
    function MIN_EPOCH_BALANCE() external view returns (uint256);

    /// @notice Length of every drip epoch.
    function epochLength() external view returns (uint256);

    /// @notice EURe token on Gnosis Chain.
    function eure() external view returns (IERC20);

    /// @notice Savings vault that receives dripped EURe yield.
    function sEURe() external view returns (ISavingsEURe);

    /// @notice Contract allowed to call `claim` in addition to EOAs.
    function claimer() external view returns (address);

    /// @notice EURe released per second during the active epoch.
    function dripRate() external view returns (uint256);

    /// @notice Timestamp at which the current epoch can roll into a new one.
    function nextClaimEpoch() external view returns (uint256);

    /// @notice Timestamp of the last successful claim state update.
    function lastClaimTimestamp() external view returns (uint256);

    /// @notice Remaining EURe scheduled to drip during the active epoch.
    function currentEpochBalance() external view returns (uint256);
}
