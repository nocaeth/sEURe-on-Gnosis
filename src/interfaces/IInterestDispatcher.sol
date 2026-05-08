// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.35;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {ISavingsEURe} from "./ISavingsEURe.sol";

/// @title IInterestDispatcher
/// @notice Interface for an EURe-funded receiver that drips yield into the `SavingsEURe` ERC-4626 vault on a fixed epoch schedule.
/// @dev
/// Implementations hold EURe and release it into the vault over epochs. Anyone may call `claim`; the vault synchronizes claims
/// before ERC-4626 accounting when enabled on the vault side.
///
/// **Concrete implementations** (this repo): upgradeable via UUPS (`owner` authorizes upgrades); epoch state uses ERC-7201 namespaced storage;
/// the EURe asset reference is immutable (`Gnosis.EURe`). Lifecycle: `initialize(owner)` → fund this contract with EURe → `bootstrap(vault)` once.
/// The implementation contract constructor MUST call `_disableInitializers()` so only the proxy delegate may initialize.
interface IInterestDispatcher {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when EURe yield is transferred into the vault.
    /// @param vault Recipient vault address.
    /// @param amount Amount of EURe transferred to the vault.
    event Claimed(address indexed vault, uint256 amount);

    /// @notice Emitted when `claim` crosses the epoch boundary and a new funded epoch starts.
    /// @param newDripRate Per-second drip rate for the next epoch.
    /// @param newEpochBalance Balance allocated to the next epoch.
    /// @param nextEpoch Timestamp at which the next epoch boundary is evaluated.
    event EpochRolled(uint256 newDripRate, uint256 newEpochBalance, uint256 nextEpoch);

    /// @notice Emitted when rollover is skipped because post-claim balance is below `DRIP_PAUSE_THRESHOLD`.
    /// @param remainingBalance EURe held by the receiver immediately after the claim amount is accounted for.
    event DripPaused(uint256 remainingBalance);

    /// @notice Emitted at the end of `bootstrap` with the bootstrap epoch parameters.
    /// @param firstEpochBalance EURe balance allocated to the first epoch.
    /// @param firstDripRate EURe released per second during the first epoch.
    /// @param firstEpochEnd Timestamp at which the first epoch boundary is evaluated.
    event Bootstrapped(uint256 firstEpochBalance, uint256 firstDripRate, uint256 firstEpochEnd);

    /// @notice Emitted when ownership changes.
    /// @param previousOwner Previous owner.
    /// @param newOwner New owner.
    event OwnerUpdated(address indexed previousOwner, address indexed newOwner);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Caller tried to use a function before the receiver was initialized.
    error NotInitialized();

    /// @notice Available EURe balance is below `MIN_INITIAL_BALANCE` during `bootstrap`.
    error InsufficientInitialBalance(uint256 actual, uint256 required);

    /// @notice Address argument cannot be zero.
    error ZeroAddress();

    /// @notice Caller is not the owner.
    error NotOwner();

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice EURe balance below this value immediately after a claim that crosses the epoch boundary pauses dripping (next rate `0`) instead of opening a new epoch.
    /// @return threshold Minimum remainder in wei of EURe to continue scheduled dripping after rollover.
    function DRIP_PAUSE_THRESHOLD() external view returns (uint256);

    /// @notice Minimum EURe balance required on the dispatcher at `bootstrap` time so the initial `dripRate` is non-zero.
    /// @return minWei Minimum whole-token wei threshold enforced only during `bootstrap`.
    function MIN_INITIAL_BALANCE() external view returns (uint256);

    /// @notice Duration of each drip epoch used to derive per-second `dripRate` from the epoch budget.
    /// @return secondsLength Epoch length in seconds (constant for all epochs).
    function EPOCH_LENGTH() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                                  VIEW
    //////////////////////////////////////////////////////////////*/

    /// @notice Monerium EURe token on Gnosis Chain (`Gnosis.EURe` in this codebase).
    /// @return token IERC-20 interface for EURe.
    function eure() external view returns (IERC20);

    /// @notice Savings vault that receives dripped EURe yield.
    /// @return vaultProxy `SavingsEURe` instance wired in `bootstrap`.
    function vault() external view returns (ISavingsEURe);

    /// @notice Contract owner (upgrade authority for UUPS and sole caller of `bootstrap`).
    /// @return ownerAddress Current owner.
    function owner() external view returns (address);

    /// @notice EURe released per second during the active epoch (`currentEpochBalance / EPOCH_LENGTH` after each rollover that does not pause).
    /// @return rateWei Per-second drip in wei.
    function dripRate() external view returns (uint256);

    /// @notice Timestamp used with rollover logic: when simulated time exceeds this boundary, epoch fields may roll (see implementation).
    /// @return epochBoundary Unix timestamp for the active epoch boundary check.
    function nextClaimEpoch() external view returns (uint256);

    /// @notice Timestamp of the last successful claim state update (`claim` that touched storage).
    /// @return lastClaim Unix timestamp of last claim accounting.
    function lastClaimTimestamp() external view returns (uint256);

    /// @notice Nominal EURe amount still budgeted to drip within the current epoch schedule before wallet-level caps.
    /// @return balanceWei Epoch budget remainder in wei.
    function currentEpochBalance() external view returns (uint256);

    /// @notice Returns the instantaneous vault APY implied by the current drip rate.
    /// @dev This is not a trailing realized APY. It returns 0 before initialization, when no yield is dripping,
    /// or when the vault has no assets. Because rollover accounting uses the receiver's live EURe balance,
    /// direct EURe transfers to this receiver can affect future `dripRate` values and this APY after rollover.
    /// Integrators MUST NOT use this value as an oracle or risk input without independent validation.
    /// @return apy Annualized EURe drip divided by vault assets, scaled by 1e18.
    function vaultAPY() external view returns (uint256);

    /// @notice Returns the amount of EURe claim() would transfer into the vault at the current block.
    /// @dev Returns 0 before bootstrap, in the same block as a claim, or when no yield is claimable.
    /// @return claimable EURe that would be transferred on claim().
    function previewClaimable() external view returns (uint256);

    /*//////////////////////////////////////////////////////////////
                                  ADMIN
    //////////////////////////////////////////////////////////////*/

    /// @notice Sets the upgrade owner; initialize the proxy delegate storage.
    /// @dev Intended to be encoded as `_data` when deploying `ERC1967Proxy`.
    /// @param owner_ Initial owner (UUPS upgrade authority); must not be zero.
    function initialize(address owner_) external;

    /// @notice Wires the vault, enables interest claiming on it, and starts the first epoch from the current EURe balance.
    /// @dev Requires balance ≥ `MIN_INITIAL_BALANCE`. Callable once after `initialize`. Only `owner`.
    /// @param vault_ `SavingsEURe` vault that receives claimed yield; must not be zero.
    function bootstrap(address vault_) external;

    /*//////////////////////////////////////////////////////////////
                                MUTATIVE
    //////////////////////////////////////////////////////////////*/

    /// @notice Transfers currently claimable EURe yield into the SavingsEURe vault.
    /// @dev
    /// Permissionless keeper function. Direct vault deposits still claim first through `SavingsEURe`.
    /// Calling twice in the same block returns 0 and leaves state unchanged.
    /// If the receiver has no EURe balance, time is not advanced so future funding remains claimable.
    /// @return claimed Amount of EURe transferred into the vault.
    function claim() external returns (uint256);

    /// @notice Transfers ownership to `newOwner`.
    /// @param newOwner New owner.
    function transferOwnership(address newOwner) external;
}
