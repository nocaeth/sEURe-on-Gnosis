// SPDX-License-Identifier: GPL-2.0-only
pragma solidity 0.8.35;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import {SavingsEURe} from "src/SavingsEURe.sol";
import {InterestDispatcher} from "src/InterestDispatcher.sol";

/// @title SavingsEUReDeployer
/// @notice Forge script: deploys `InterestDispatcher` behind `ERC1967Proxy`, deploys `SavingsEURe`, funds the dispatcher, bootstraps, and seeds a small vault deposit.
/// @dev Expects `MNEMONIC` (BIP-39, length check > 30 chars) or `PRIVATE_KEY` and runs only when `block.chainid == 100` (Gnosis).
contract SavingsEUReDeployer is Script {
    using SafeERC20 for IERC20;

    uint256 internal constant GNOSIS_CHAIN_ID = 100;

    error InvalidChain(uint256 chainId);

    /// @notice Runs the full deployment sequence on Gnosis (`chainId` 100).
    /// @custom:reverts InvalidChain when `block.chainid` is not `100`.
    function run() external {
        if (block.chainid != GNOSIS_CHAIN_ID) revert InvalidChain(block.chainid);

        /*//////////////////////////////////////////////////////////////
                                KEY MANAGEMENT
        //////////////////////////////////////////////////////////////*/

        // forge-lint: disable-next-line(unsafe-cheatcode)
        string memory mnemonic = vm.envString("MNEMONIC");
        uint256 deployerPrivateKey;
        if (bytes(mnemonic).length > 30) {
            // forge-lint: disable-next-line(unsafe-cheatcode)
            deployerPrivateKey = vm.deriveKey(mnemonic, 0);
        } else {
            // forge-lint: disable-next-line(unsafe-cheatcode)
            deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        }

        vm.startBroadcast(deployerPrivateKey);
        address deployer = vm.rememberKey(deployerPrivateKey);
        console.log("Deployer: %s", deployer);

        /*//////////////////////////////////////////////////////////////
                                DEPLOYMENTS
        //////////////////////////////////////////////////////////////*/

        InterestDispatcher interestDispatcherImplementation = new InterestDispatcher();
        console.log("Deployed InterestDispatcher implementation: %s", address(interestDispatcherImplementation));

        IERC20 eure = interestDispatcherImplementation.eure();
        bytes memory initData = abi.encodeCall(InterestDispatcher.initialize, (deployer));
        ERC1967Proxy proxy = new ERC1967Proxy(address(interestDispatcherImplementation), initData);
        InterestDispatcher interestDispatcher = InterestDispatcher(address(proxy));
        console.log("Deployed InterestDispatcher proxy: %s", address(interestDispatcher));

        SavingsEURe savingsEURe = new SavingsEURe(address(interestDispatcher));
        console.log("Deployed sEURe: %s", address(savingsEURe));

        // Owner is set atomically in the proxy constructor (OZ v5.6+). Fund then bootstrap in the same broadcast.
        uint256 receiverFunding = 101 ether;
        eure.forceApprove(address(interestDispatcher), receiverFunding);
        eure.safeTransfer(address(interestDispatcher), receiverFunding);
        interestDispatcher.bootstrap(address(savingsEURe));
        console.log("Bootstrapped InterestDispatcher with %s EURe", receiverFunding);

        uint256 initialDeposit = 1 ether;
        eure.forceApprove(address(savingsEURe), initialDeposit);
        savingsEURe.deposit(initialDeposit, deployer);
        console.log("Seeded sEURe with 1 EURe");

        vm.stopBroadcast();
    }
}
