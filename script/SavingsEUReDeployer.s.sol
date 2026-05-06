// SPDX-License-Identifier: GPL-2.0-only
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SafeERC20} from "openzeppelin/token/ERC20/utils/SafeERC20.sol";
import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import {SavingsEURe} from "src/SavingsEURe.sol";
import {InterestDispatcher} from "src/InterestDispatcher.sol";

contract SavingsEUReDeployer is Script {
    using SafeERC20 for IERC20;

    uint256 internal constant GNOSIS_CHAIN_ID = 100;

    error InvalidChain(uint256 chainId);

    function run() external {
        if (block.chainid != GNOSIS_CHAIN_ID) revert InvalidChain(block.chainid);

        /*//////////////////////////////////////////////////////////////
                                KEY MANAGEMENT
        //////////////////////////////////////////////////////////////*/

        uint256 deployerPrivateKey = 0;
        string memory mnemonic = vm.envString("MNEMONIC");

        if (bytes(mnemonic).length > 30) {
            deployerPrivateKey = vm.deriveKey(mnemonic, 0);
        } else {
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
        ERC1967Proxy proxy = new ERC1967Proxy(address(interestDispatcherImplementation), "");
        InterestDispatcher interestDispatcher = InterestDispatcher(address(proxy));
        console.log("Deployed InterestDispatcher proxy: %s", address(interestDispatcher));

        SavingsEURe savingsEURe = new SavingsEURe(address(interestDispatcher));
        console.log("Deployed sEURe: %s", address(savingsEURe));

        // Fund and initialize the receiver in the same broadcast to prevent
        // front-running the public initializer (C-01).
        uint256 receiverFunding = 101 ether;
        eure.forceApprove(address(interestDispatcher), receiverFunding);
        eure.safeTransfer(address(interestDispatcher), receiverFunding);
        interestDispatcher.initialize(address(savingsEURe), deployer);
        console.log("Initialized InterestDispatcher with %s EURe", receiverFunding);

        uint256 initialDeposit = 1 ether;
        eure.forceApprove(address(savingsEURe), initialDeposit);
        savingsEURe.deposit(initialDeposit, deployer);
        console.log("Seeded sEURe with 1 EURe");

        vm.stopBroadcast();
    }
}
