// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.35;

import {Initializable} from "openzeppelin/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {Gnosis} from "./constants/Gnosis.sol";
import {IInterestDispatcher} from "./interfaces/IInterestDispatcher.sol";
import {ISavingsEURe} from "./interfaces/ISavingsEURe.sol";

/// @title InterestDispatcher
/// @notice EURe drip receiver wired to `SavingsEURe` (`IInterestDispatcher`).
/// @dev Behavioral contract: see `IInterestDispatcher` (epochs, UUPS, ERC-7201 storage, lifecycle).
contract InterestDispatcher is Initializable, UUPSUpgradeable, IInterestDispatcher {
    using SafeERC20 for IERC20;

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IInterestDispatcher
    uint256 public constant override DRIP_PAUSE_THRESHOLD = 100 ether;

    /// @inheritdoc IInterestDispatcher
    uint256 public constant override MIN_INITIAL_BALANCE = 1 ether;

    /// @inheritdoc IInterestDispatcher
    uint256 public constant override EPOCH_LENGTH = 5 days;

    /*//////////////////////////////////////////////////////////////
                         ERC-7201 NAMESPACED STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev Module storage per ERC-7201 (namespaced struct slot).
    /// @custom:storage-location erc7201:noca.savings_eure.interest_dispatcher
    struct InterestDispatcherStorage {
        ISavingsEURe vault;
        address owner;
        uint256 dripRate;
        uint256 nextClaimEpoch;
        uint256 currentEpochBalance;
        uint256 lastClaimTimestamp;
    }

    /*//////////////////////////////////////////////////////////////
                          INTERNAL VALUE TYPES
    //////////////////////////////////////////////////////////////*/

    /// @dev Memory snapshot passed to `_simulateClaim`. Bundles block state and epoch parameters to keep `_simulateClaim` pure-friendly for tooling (e.g. coverage).
    struct ClaimContext {
        uint256 timestamp;
        uint256 balance;
        uint256 lastClaimTimestamp;
        uint256 currentEpochBalance;
        uint256 dripRate;
        uint256 nextClaimEpoch;
        uint256 epochLength;
        uint256 pauseThreshold;
    }

    /// @dev Result of `_simulateClaim`: claim amount plus post-claim storage fields and rollover flags (`rolled`, `paused`).
    struct ClaimResult {
        uint256 claimable;
        uint256 nextEpochBalance;
        uint256 nextDripRate;
        uint256 nextNextClaimEpoch;
        uint256 remainingAfterClaim;
        bool rolled;
        bool paused;
    }

    // keccak256(abi.encode(uint256(keccak256("noca.savings_eure.interest_dispatcher")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 private constant INTEREST_DISPATCHER_STORAGE_LOCATION =
        0x9164f8c205381b64e458ee01bc88d5de773af3a65d86bd29c05ea24ac702cd00;

    /// @return $ ERC-7201 namespaced storage struct for this module.
    function _getInterestDispatcherStorage() private pure returns (InterestDispatcherStorage storage $) {
        assembly {
            $.slot := INTEREST_DISPATCHER_STORAGE_LOCATION
        }
    }

    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    IERC20 private immutable EURE;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @dev Disables initializers on the implementation and binds `EURE` to `Gnosis.EURe`; see `IInterestDispatcher` lifecycle.
    constructor() {
        _disableInitializers();
        EURE = IERC20(Gnosis.EURe);
    }

    /*//////////////////////////////////////////////////////////////
                                  ADMIN
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IInterestDispatcher
    function initialize(address owner_) external override initializer {
        if (owner_ == address(0)) revert ZeroAddress();
        _getInterestDispatcherStorage().owner = owner_;
    }

    /// @inheritdoc IInterestDispatcher
    function bootstrap(address vault_) external override reinitializer(2) {
        InterestDispatcherStorage storage $ = _getInterestDispatcherStorage();
        if (msg.sender != $.owner) revert NotOwner();
        if (vault_ == address(0)) revert ZeroAddress();

        $.vault = ISavingsEURe(vault_);
        $.vault.enableInterestClaiming();

        uint256 currentEpochBalance_ = _balance();
        if (currentEpochBalance_ < MIN_INITIAL_BALANCE) {
            revert InsufficientInitialBalance(currentEpochBalance_, MIN_INITIAL_BALANCE);
        }
        $.lastClaimTimestamp = block.timestamp;
        $.nextClaimEpoch = block.timestamp + EPOCH_LENGTH;
        $.dripRate = currentEpochBalance_ / EPOCH_LENGTH;
        $.currentEpochBalance = currentEpochBalance_;

        emit Bootstrapped($.currentEpochBalance, $.dripRate, $.nextClaimEpoch);
    }

    /*//////////////////////////////////////////////////////////////
                                MUTATIVE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IInterestDispatcher
    function claim() external override returns (uint256 claimed) {
        InterestDispatcherStorage storage $ = _getInterestDispatcherStorage();
        if (!_isRuntimeInitialized($)) revert NotInitialized();

        uint256 lastTs = $.lastClaimTimestamp;
        if (lastTs == block.timestamp) {
            return 0;
        }

        uint256 balance = _balance();
        if (balance > 0) {
            ClaimResult memory res = _simulateClaim(_loadContext($, balance, lastTs));
            claimed = res.claimable;

            $.currentEpochBalance = res.nextEpochBalance;
            $.dripRate = res.nextDripRate;
            $.nextClaimEpoch = res.nextNextClaimEpoch;
            $.lastClaimTimestamp = block.timestamp;

            EURE.safeTransfer(address($.vault), claimed);
            emit Claimed(address($.vault), claimed);

            if (res.rolled) {
                if (res.paused) {
                    emit DripPaused(res.remainingAfterClaim);
                } else {
                    emit EpochRolled(res.nextDripRate, res.nextEpochBalance, res.nextNextClaimEpoch);
                }
            }
        }
        return claimed;
    }

    /// @inheritdoc IInterestDispatcher
    function transferOwnership(address newOwner) external override {
        InterestDispatcherStorage storage $ = _getInterestDispatcherStorage();
        if (msg.sender != $.owner) revert NotOwner();
        if (newOwner == address(0)) revert ZeroAddress();

        address previousOwner = $.owner;
        $.owner = newOwner;
        emit OwnerUpdated(previousOwner, newOwner);
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEW
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IInterestDispatcher
    function vault() external view override returns (ISavingsEURe) {
        return _getInterestDispatcherStorage().vault;
    }

    /// @inheritdoc IInterestDispatcher
    function owner() external view override returns (address) {
        return _getInterestDispatcherStorage().owner;
    }

    /// @inheritdoc IInterestDispatcher
    function dripRate() external view override returns (uint256) {
        return _getInterestDispatcherStorage().dripRate;
    }

    /// @inheritdoc IInterestDispatcher
    function nextClaimEpoch() external view override returns (uint256) {
        return _getInterestDispatcherStorage().nextClaimEpoch;
    }

    /// @inheritdoc IInterestDispatcher
    function currentEpochBalance() external view override returns (uint256) {
        return _getInterestDispatcherStorage().currentEpochBalance;
    }

    /// @inheritdoc IInterestDispatcher
    function lastClaimTimestamp() external view override returns (uint256) {
        return _getInterestDispatcherStorage().lastClaimTimestamp;
    }

    /// @inheritdoc IInterestDispatcher
    function eure() external view override returns (IERC20) {
        return EURE;
    }

    /// @inheritdoc IInterestDispatcher
    function vaultAPY() external view override returns (uint256) {
        InterestDispatcherStorage storage $ = _getInterestDispatcherStorage();
        if (!_isRuntimeInitialized($) || $.dripRate == 0 || $.currentEpochBalance == 0) return 0;

        uint256 deposits = $.vault.totalAssets();
        if (deposits == 0) return 0;

        uint256 annualYield = ($.dripRate * 365 days);
        return (1 ether * annualYield) / deposits;
    }

    /// @inheritdoc IInterestDispatcher
    function previewClaimable() external view override returns (uint256) {
        InterestDispatcherStorage storage $ = _getInterestDispatcherStorage();
        if (!_isRuntimeInitialized($) || $.lastClaimTimestamp == block.timestamp) return 0;
        uint256 balance = _balance();
        if (balance == 0) return 0;
        return _simulateClaim(_loadContext($, balance, $.lastClaimTimestamp)).claimable;
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @param $ Storage bundle read for this module.
    /// @return True if both `vault` and `owner` are non-zero (post-`initialize` and typically post-`bootstrap` for claim paths).
    function _isRuntimeInitialized(InterestDispatcherStorage storage $) private view returns (bool) {
        return address($.vault) != address(0) && $.owner != address(0);
    }

    /// @dev Computes linear drip accrual capped by the epoch budget and `epochLength`; does not cap by wallet balance (caller uses `_simulateClaim` for that).
    /// @param unclaimedTime Seconds elapsed since the claim baseline timestamp.
    /// @param _currentEpochBalance Nominal EURe remaining for the current epoch schedule before this slice.
    /// @param _dripRate EURe per second released during the epoch.
    /// @param _epochLength Epoch duration in seconds.
    /// @return claimable EURe attributed to `unclaimedTime` subject to epoch caps.
    /// @return intraEpochBalanceAfter Epoch-scheduled balance remaining after `claimable`.
    function _computeClaimable(
        uint256 unclaimedTime,
        uint256 _currentEpochBalance,
        uint256 _dripRate,
        uint256 _epochLength
    ) internal pure returns (uint256 claimable, uint256 intraEpochBalanceAfter) {
        if (unclaimedTime >= _epochLength) {
            return (_currentEpochBalance, 0);
        }
        claimable = unclaimedTime * _dripRate;
        if (_currentEpochBalance < claimable) {
            return (_currentEpochBalance, 0);
        }
        return (claimable, _currentEpochBalance - claimable);
    }

    /// @dev Copies storage epoch fields and live EURe balance into a single memory context for `_simulateClaim`.
    /// @param $ Storage for vault-linked epoch state.
    /// @param balance Current EURe balance of this contract (`EURE.balanceOf(address(this))`).
    /// @param lastClaimTimestamp_ Timestamp used as the accrual start for this simulation (matches stored `lastClaimTimestamp` in normal calls).
    /// @return ctx Packed inputs for `_simulateClaim`.
    function _loadContext(InterestDispatcherStorage storage $, uint256 balance, uint256 lastClaimTimestamp_)
        private
        view
        returns (ClaimContext memory ctx)
    {
        ctx.timestamp = block.timestamp;
        ctx.balance = balance;
        ctx.lastClaimTimestamp = lastClaimTimestamp_;
        ctx.currentEpochBalance = $.currentEpochBalance;
        ctx.dripRate = $.dripRate;
        ctx.nextClaimEpoch = $.nextClaimEpoch;
        ctx.epochLength = EPOCH_LENGTH;
        ctx.pauseThreshold = DRIP_PAUSE_THRESHOLD;
    }

    /// @dev If simulated time is past `ctx.nextClaimEpoch`, sets rollover outputs from post-claim remainder; may pause dripping below `ctx.pauseThreshold`.
    /// @param ctx Snapshot including timestamps, balances, and epoch parameters.
    /// @param res Mutated in place: must already contain `claimable` from `_simulateClaim`.
    function _applyRollover(ClaimContext memory ctx, ClaimResult memory res) private pure {
        res.remainingAfterClaim = ctx.balance - res.claimable;
        if (ctx.timestamp > ctx.nextClaimEpoch) {
            res.rolled = true;
            if (res.remainingAfterClaim < ctx.pauseThreshold) {
                res.nextDripRate = 0;
                res.nextEpochBalance = 0;
                res.paused = true;
            } else {
                res.nextDripRate = res.remainingAfterClaim / ctx.epochLength;
                res.nextEpochBalance = res.remainingAfterClaim;
                res.nextNextClaimEpoch = ctx.timestamp + ctx.epochLength;
            }
        }
    }

    /// @dev Pure simulation of one claim step: accrual within epoch, wallet cap, then optional rollover / pause. Must match `claim` and `previewClaimable` semantics.
    /// @param ctx Inputs assembled by `_loadContext`.
    /// @return res Claim amount and updated epoch fields plus rollover flags.
    function _simulateClaim(ClaimContext memory ctx) internal pure returns (ClaimResult memory res) {
        res.nextDripRate = ctx.dripRate;
        res.nextNextClaimEpoch = ctx.nextClaimEpoch;

        (res.claimable, res.nextEpochBalance) = _computeClaimable(
            ctx.timestamp - ctx.lastClaimTimestamp, ctx.currentEpochBalance, ctx.dripRate, ctx.epochLength
        );

        if (res.claimable > ctx.balance) {
            res.claimable = ctx.balance;
        }

        _applyRollover(ctx, res);
    }

    /// @return EURe balance held by this contract.
    function _balance() internal view returns (uint256) {
        return EURE.balanceOf(address(this));
    }

    /// @inheritdoc UUPSUpgradeable
    function _authorizeUpgrade(address) internal view override {
        if (msg.sender != _getInterestDispatcherStorage().owner) revert NotOwner();
    }
}
