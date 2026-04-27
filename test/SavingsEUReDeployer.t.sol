// SPDX-License-Identifier: GPL-2.0-only
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SavingsEUReDeployer} from "script/SavingsEUReDeployer.s.sol";
import {MockEURe} from "test/Mocks/MockEURe.sol";

/// Exercises `script/SavingsEUReDeployer.s.sol` key-resolution branches and full `run()` path.
contract SavingsEUReDeployerTest is Test {
    IERC20 internal constant EURE = IERC20(0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430);

    function setUp() public {
        MockEURe mock = new MockEURe();
        vm.etch(address(EURE), address(mock).code);
    }

    /// Both branches of `bytes(mnemonic).length > 30` in one test so coverage reliably records each path.
    function testRun_keyResolution_mnemonicThenPrivateKey() public {
        vm.setEnv("MNEMONIC", "test test test test test test test test test test test junk");
        new SavingsEUReDeployer().run();

        vm.setEnv("MNEMONIC", "short");
        vm.setEnv(
            "PRIVATE_KEY", vm.toString(uint256(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80))
        );
        new SavingsEUReDeployer().run();
    }
}
