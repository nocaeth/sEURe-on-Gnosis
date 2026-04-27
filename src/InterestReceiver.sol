// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {Initializable} from "openzeppelin/proxy/utils/Initializable.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {IInterestReceiver} from "./interfaces/IInterestReceiver.sol";
import {ISavingsEURe} from "./interfaces/ISavingsEURe.sol";

contract InterestReceiver is Initializable, IInterestReceiver {
    using SafeERC20 for IERC20;

    /// @inheritdoc IInterestReceiver
    uint256 public constant override MIN_EPOCH_BALANCE = 100 ether;

    /// @inheritdoc IInterestReceiver
    uint256 public constant override epochLength = 5 days;

    /// @inheritdoc IInterestReceiver
    IERC20 public immutable override eure = IERC20(0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430);

    /// @inheritdoc IInterestReceiver
    ISavingsEURe public immutable override sEURe;

    /// @inheritdoc IInterestReceiver
    address public override claimer;

    /// @inheritdoc IInterestReceiver
    uint256 public override dripRate;

    /// @inheritdoc IInterestReceiver
    uint256 public override nextClaimEpoch;

    /// @inheritdoc IInterestReceiver
    uint256 public override currentEpochBalance;

    /// @inheritdoc IInterestReceiver
    uint256 public override lastClaimTimestamp;

    constructor(address _vault) {
        sEURe = ISavingsEURe(_vault);
        claimer = msg.sender;
    }

    modifier isInitialized() {
        _requireInitialized();
        _;
    }

    modifier isClaimer() {
        _requireClaimer();
        _;
    }

    function _requireInitialized() internal view {
        if (_getInitializedVersion() == 0) revert NotInitialized();
    }

    function _requireClaimer() internal view {
        if (tx.origin != msg.sender && msg.sender != claimer) revert NotValidClaimer();
    }

    /// @inheritdoc IInterestReceiver
    function initialize() public override initializer {
        if (msg.sender != claimer) revert NotClaimer();
        currentEpochBalance = _balance();
        if (currentEpochBalance <= MIN_EPOCH_BALANCE) revert InsufficientInitialBalance();
        lastClaimTimestamp = block.timestamp;
        nextClaimEpoch = block.timestamp + epochLength;
        dripRate = currentEpochBalance / epochLength;

        emit Initialized(currentEpochBalance, dripRate, nextClaimEpoch);
    }

    /// @inheritdoc IInterestReceiver
    function claim() public override isInitialized isClaimer returns (uint256 claimed) {
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

    /// @inheritdoc IInterestReceiver
    function vaultAPY() external view override returns (uint256) {
        if (_getInitializedVersion() == 0 || dripRate == 0) return 0;

        uint256 deposits = sEURe.totalAssets();
        if (deposits == 0) return 0;

        uint256 annualYield = (dripRate * 365 days);
        return (1 ether * annualYield) / deposits;
    }

    /// @inheritdoc IInterestReceiver
    function setClaimer(address newClaimer) external override {
        if (claimer != msg.sender) revert NotClaimer();
        if (newClaimer == address(0)) revert ZeroAddress();

        address previousClaimer = claimer;
        claimer = newClaimer;

        emit ClaimerUpdated(previousClaimer, newClaimer);
    }
}
