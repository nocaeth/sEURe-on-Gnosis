// SPDX-License-Identifier: agpl-3
pragma solidity ^0.8.19;

import "openzeppelin/interfaces/IERC4626.sol";
import "openzeppelin/proxy/utils/Initializable.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {SavingsEURe} from "./SavingsEURe.sol";

contract InterestReceiver is Initializable {
    using SafeERC20 for IERC20;

    IERC20 public immutable eure = IERC20(0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430);
    address public vault;
    SavingsEURe private sEURe;
    address public claimer;

    uint256 public dripRate;
    uint256 public nextClaimEpoch;
    uint256 public currentEpochBalance;
    uint256 public lastClaimTimestamp;
    uint256 public epochLength = 3 days;

    event Claimed(uint256 indexed amount);

    constructor(address _vault) {
        vault = _vault;
        sEURe = SavingsEURe(payable(_vault));
        claimer = msg.sender;
    }

    modifier isInitialized() {
        require(_getInitializedVersion() > 0, "Not Initialized");
        _;
    }

    modifier isClaimer() {
        require(tx.origin == msg.sender || msg.sender == claimer, "Not valid Claimer");
        _;
    }

    /**
     * @dev Initialize receiver, require minimum balance to not set a dripRate of 0
     */
    function initialize() public initializer {
        currentEpochBalance = _aggregateBalance();
        require(currentEpochBalance > 10000 ether, "Fill it up first");
        lastClaimTimestamp = block.timestamp;
        // Set custom first epoch balance or length
        uint256 firstClaimLength = 6 days;
        nextClaimEpoch = block.timestamp + firstClaimLength;
        dripRate = currentEpochBalance / firstClaimLength;
    }

    function claim() public isInitialized isClaimer returns (uint256 claimed) {
        // if already claimed in this block, skip it
        if (lastClaimTimestamp == block.timestamp) {
            return 0;
        }
        uint256 balance = _aggregateBalance();
        if (balance > 0) {
            (claimed) = _calcClaimable(balance);
            lastClaimTimestamp = block.timestamp;

            eure.safeTransfer(vault, claimed);
            emit Claimed(claimed);
        }
        return claimed;
    }

    function _calcClaimable(uint256 balance) internal returns (uint256 claimable) {
        uint256 unclaimedTime = block.timestamp - lastClaimTimestamp;

        // If a full epoch has passed since last claim, claim the full balance
        if (unclaimedTime >= epochLength) {
            claimable = currentEpochBalance;
        } else {
            // otherwise release the amount dripped during that time
            claimable = unclaimedTime * dripRate;
            // update how much has already been claimed this epoch
            if (currentEpochBalance < claimable) {
                claimable = currentEpochBalance;
                currentEpochBalance = 0;
            } else {
                currentEpochBalance -= claimable;
            }
        }
        // If current time is past next epoch starting time update dripRate
        if (block.timestamp > nextClaimEpoch) {
            // If post-claim balance too low wait for more deposits and set rate to 0
            if ((balance - claimable) < 1000 ether) {
                dripRate = 0;
            } else {
                // If post-claim balance is significant set new dripRate and start a new Epoch
                dripRate = (balance - claimable) / epochLength;
                currentEpochBalance = balance - claimable;
                nextClaimEpoch = block.timestamp + epochLength;
            }
        }
        return claimable;
    }

    /**
     * @dev Return the EURe balance of this contract
     */
    function _aggregateBalance() internal view returns (uint256 balance) {
        return eure.balanceOf(address(this));
    }

    /**
     * @dev Emulates how much would be claimable given receiver address
     */
    function previewClaimable() external view returns (uint256 claimable) {
        uint256 unclaimedTime = block.timestamp - lastClaimTimestamp;
        // If a full epoch has passed since last claim, claim the full amount
        if (unclaimedTime >= epochLength) {
            claimable = currentEpochBalance;
        } else {
            // otherwise release the amount dripped during that time
            claimable = unclaimedTime * dripRate;
            // update how much has already been claimed this epoch
            if (currentEpochBalance < claimable) {
                claimable = currentEpochBalance;
            }
        }
        return claimable;
    }

    /**
     * @dev Informs about approximate sEURe vault APY based on incoming interest and vault deposits
     * @return amount of interest collected per year divided by amount of current deposits in vault
     */
    function vaultAPY() external view returns (uint256) {
        uint256 deposits = sEURe.totalAssets();
        uint256 annualYield = (dripRate * 365 days);
        return (1 ether * annualYield) / deposits;
    }

    function setClaimer(address newClaimer) external {
        require(claimer == msg.sender, "Not Claimer");
        claimer = newClaimer;
    }
}
