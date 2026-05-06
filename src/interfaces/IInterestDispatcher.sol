// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {ISavingsEURe} from "./ISavingsEURe.sol";

/// @title IInterestDispatcher
/// @notice Drips externally funded EURe yield into the SavingsEURe ERC4626 vault.
/// @dev
/// The receiver is funded externally with EURe and releases that balance into the vault over epochs.
/// Anyone may trigger claims; the vault synchronizes claims before ERC4626 accounting changes.
interface IInterestDispatcher {
    /// @notice Caller tried to use a function before the receiver was initialized.
    error NotInitialized();

    /// @notice Available EURe balance is below `MIN_EPOCH_BALANCE`.
    error InsufficientInitialBalance();

    /// @notice Address argument cannot be zero.
    error ZeroAddress();

    /// @notice Caller is not the owner.
    error NotOwner();

    /// @notice Emitted when EURe yield is transferred into the vault.
    /// @param amount Amount of EURe transferred to the vault.
    event Claimed(uint256 indexed amount);

    /// @notice Emitted when the initial drip epoch is configured.
    /// @param initialBalance EURe balance used to seed the initial epoch.
    /// @param dripRate EURe released per second during the initial epoch.
    /// @param nextClaimEpoch Timestamp at which the initial epoch can roll over.
    event Initialized(uint256 indexed initialBalance, uint256 dripRate, uint256 nextClaimEpoch);

    /// @notice Emitted when ownership changes.
    /// @param previousOwner Previous owner.
    /// @param newOwner New owner.
    event OwnerUpdated(address indexed previousOwner, address indexed newOwner);

    /// @notice Initializes the first drip epoch.
    /// @dev Requires enough EURe to avoid a zero `dripRate`. Can only be called once through the proxy.
    /// @param vault SavingsEURe vault that receives claimed yield.
    /// @param owner_ Initial owner of the receiver.
    function initialize(address vault, address owner_) external;

    /// @notice Transfers currently claimable EURe yield into the SavingsEURe vault.
    /// @dev
    /// Permissionless keeper function. Direct vault deposits still claim first through `SavingsEURe`.
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

    /// @notice Returns the amount of EURe claim() would transfer into the vault at the current block.
    /// @dev Returns 0 before initialization, in the same block as a claim, or when no yield is claimable.
    /// @return claimable EURe that would be transferred on claim().
    function previewClaimable() external view returns (uint256);

    /// @notice Transfers ownership to `newOwner`.
    /// @param newOwner New owner.
    function transferOwnership(address newOwner) external;

    /// @notice Minimum EURe balance required to initialize or start a drip epoch.
    function MIN_EPOCH_BALANCE() external view returns (uint256);

    /// @notice Length of every drip epoch.
    function epochLength() external view returns (uint256);

    /// @notice EURe token on Gnosis Chain.
    function eure() external view returns (IERC20);

    /// @notice Savings vault that receives dripped EURe yield.
    function sEURe() external view returns (ISavingsEURe);

    /// @notice Contract owner.
    function owner() external view returns (address);

    /// @notice EURe released per second during the active epoch.
    function dripRate() external view returns (uint256);

    /// @notice Timestamp at which the current epoch can roll into a new one.
    function nextClaimEpoch() external view returns (uint256);

    /// @notice Timestamp of the last successful claim state update.
    function lastClaimTimestamp() external view returns (uint256);

    /// @notice Remaining EURe scheduled to drip during the active epoch.
    function currentEpochBalance() external view returns (uint256);
}
