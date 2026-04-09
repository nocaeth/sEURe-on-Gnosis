// SPDX-License-Identifier: gpl-2.0
pragma solidity ^0.8.19;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import "src/SavingsEURe.sol";
import "src/InterestReceiver.sol";
import "src/periphery/SavingsEUReAdapter.sol";

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

        SavingsEURe sEURe = new SavingsEURe("Savings EURe", "sEURe");
        console.log("Deployed sEURe: %s", address(sEURe));

        InterestReceiver interestReceiver = new InterestReceiver(address(sEURe));
        console.log("Deployed InterestReceiver: %s", address(interestReceiver));

        SavingsEUReAdapter adapter = new SavingsEUReAdapter(address(interestReceiver), payable(address(sEURe)));
        console.log("Deployed SavingsEUReAdapter on Gnosis: %s", address(adapter));

        interestReceiver.setClaimer(address(adapter));
        console.log("Configured Claimer on receiver");

        vm.stopBroadcast();
    }
}
