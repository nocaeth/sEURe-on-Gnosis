// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {Initializable} from "openzeppelin/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "openzeppelin/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IInterestDispatcher} from "./interfaces/IInterestDispatcher.sol";
import {ISavingsEURe} from "./interfaces/ISavingsEURe.sol";

contract InterestDispatcher is Initializable, UUPSUpgradeable, IInterestDispatcher {
    using SafeERC20 for IERC20;

    /// @inheritdoc IInterestDispatcher
    uint256 public constant override MIN_EPOCH_BALANCE = 100 ether;

    /// @inheritdoc IInterestDispatcher
    uint256 public constant override epochLength = 5 days;

    /// @inheritdoc IInterestDispatcher
    IERC20 public immutable override eure = IERC20(0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430);

    /// @inheritdoc IInterestDispatcher
    ISavingsEURe public override sEURe;

    /// @inheritdoc IInterestDispatcher
    address public override owner;

    /// @inheritdoc IInterestDispatcher
    uint256 public override dripRate;

    /// @inheritdoc IInterestDispatcher
    uint256 public override nextClaimEpoch;

    /// @inheritdoc IInterestDispatcher
    uint256 public override currentEpochBalance;

    /// @inheritdoc IInterestDispatcher
    uint256 public override lastClaimTimestamp;

    constructor() {
        _disableInitializers();
    }

    modifier isInitialized() {
        _requireInitialized();
        _;
    }

    function _isRuntimeInitialized() internal view returns (bool) {
        return address(sEURe) != address(0) && owner != address(0);
    }

    function _requireInitialized() internal view {
        if (!_isRuntimeInitialized()) revert NotInitialized();
    }

    /// @inheritdoc IInterestDispatcher
    function initialize(address vault, address owner_) public override initializer {
        if (vault == address(0) || owner_ == address(0)) revert ZeroAddress();

        sEURe = ISavingsEURe(vault);
        owner = owner_;
        sEURe.enableInterestClaiming();
        currentEpochBalance = _balance();
        if (currentEpochBalance < MIN_EPOCH_BALANCE) revert InsufficientInitialBalance();
        lastClaimTimestamp = block.timestamp;
        nextClaimEpoch = block.timestamp + epochLength;
        dripRate = currentEpochBalance / epochLength;

        emit Initialized(currentEpochBalance, dripRate, nextClaimEpoch);
    }

    /// @inheritdoc IInterestDispatcher
    function claim() public override isInitialized returns (uint256 claimed) {
        if (lastClaimTimestamp == block.timestamp) {
            return 0;
        }

        uint256 balance = _balance();
        if (balance > 0) {
            uint256 nextEpochBalance;
            uint256 nextDripRate;
            uint256 nextEpochTimestamp;
            (claimed, nextEpochBalance, nextDripRate, nextEpochTimestamp) = _calculateClaim(balance);

            currentEpochBalance = nextEpochBalance;
            dripRate = nextDripRate;
            nextClaimEpoch = nextEpochTimestamp;
            lastClaimTimestamp = block.timestamp;

            eure.safeTransfer(address(sEURe), claimed);
            emit Claimed(claimed);
        }
        return claimed;
    }

    function _calculateClaim(uint256 balance)
        internal
        view
        returns (uint256 claimable, uint256 nextEpochBalance_, uint256 nextDripRate_, uint256 nextClaimEpoch_)
    {
        uint256 unclaimedTime = block.timestamp - lastClaimTimestamp;
        nextEpochBalance_ = currentEpochBalance;
        nextDripRate_ = dripRate;
        nextClaimEpoch_ = nextClaimEpoch;

        if (unclaimedTime >= epochLength) {
            claimable = currentEpochBalance;
            nextEpochBalance_ = 0;
        } else {
            claimable = unclaimedTime * dripRate;

            if (nextEpochBalance_ < claimable) {
                claimable = currentEpochBalance;
                nextEpochBalance_ = 0;
            } else {
                nextEpochBalance_ -= claimable;
            }
        }

        if (claimable > balance) {
            claimable = balance;
        }

        if (block.timestamp > nextClaimEpoch) {
            uint256 remaining = balance - claimable;
            if (remaining < MIN_EPOCH_BALANCE) {
                nextDripRate_ = 0;
                nextEpochBalance_ = 0;
            } else {
                nextDripRate_ = remaining / epochLength;
                nextEpochBalance_ = remaining;
                nextClaimEpoch_ = block.timestamp + epochLength;
            }
        }
    }

    // Returns the current EURe balance held by this receiver.
    function _balance() internal view returns (uint256) {
        return eure.balanceOf(address(this));
    }

    /// @inheritdoc IInterestDispatcher
    function vaultAPY() external view override returns (uint256) {
        if (!_isRuntimeInitialized() || dripRate == 0 || currentEpochBalance == 0) return 0;

        uint256 deposits = sEURe.totalAssets();
        if (deposits == 0) return 0;

        uint256 annualYield = (dripRate * 365 days);
        return (1 ether * annualYield) / deposits;
    }

    /// @inheritdoc IInterestDispatcher
    function previewClaimable() external view override returns (uint256) {
        if (!_isRuntimeInitialized() || lastClaimTimestamp == block.timestamp) return 0;
        uint256 balance = _balance();
        if (balance == 0) return 0;
        (uint256 claimable,,,) = _calculateClaim(balance);
        return claimable;
    }

    /// @inheritdoc IInterestDispatcher
    function transferOwnership(address newOwner) external override {
        if (msg.sender != owner) revert NotOwner();
        if (newOwner == address(0)) revert ZeroAddress();

        address previousOwner = owner;
        owner = newOwner;
        emit OwnerUpdated(previousOwner, newOwner);
    }

    function _authorizeUpgrade(address) internal view override {
        if (msg.sender != owner) revert NotOwner();
    }

    uint256[50] private __gap;
}
