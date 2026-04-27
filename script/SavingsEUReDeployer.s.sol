// SPDX-License-Identifier: GPL-2.0-only
pragma solidity ^0.8.20;

import {Script} from "forge-std/Script.sol";
import {console} from "forge-std/console.sol";
import {SavingsEURe} from "src/SavingsEURe.sol";
import {InterestReceiver} from "src/InterestReceiver.sol";
import {SavingsEUReAdapter} from "src/periphery/SavingsEUReAdapter.sol";

contract SavingsEUReDeployer is Script {
    function run() external {
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

        SavingsEURe savingsEURe = new SavingsEURe();
        console.log("Deployed sEURe: %s", address(savingsEURe));

        InterestReceiver interestReceiver = new InterestReceiver(address(savingsEURe));
        console.log("Deployed InterestReceiver: %s", address(interestReceiver));

        SavingsEUReAdapter adapter = new SavingsEUReAdapter(address(interestReceiver), payable(address(savingsEURe)));
        console.log("Deployed SavingsEUReAdapter on Gnosis: %s", address(adapter));

        interestReceiver.setClaimer(address(adapter));
        console.log("Configured Claimer on receiver");

        vm.stopBroadcast();
    }
}
