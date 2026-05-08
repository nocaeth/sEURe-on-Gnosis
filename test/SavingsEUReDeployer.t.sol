// SPDX-License-Identifier: GPL-2.0-only
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {SavingsEUReDeployer} from "script/SavingsEUReDeployer.s.sol";
import {InterestDispatcher} from "src/InterestDispatcher.sol";
import {SavingsEURe} from "src/SavingsEURe.sol";
import {Gnosis} from "src/constants/Gnosis.sol";
import {MockEURe} from "test/Mocks/MockEURe.sol";

/// Exercises `script/SavingsEUReDeployer.s.sol` key-resolution branches and full `run()` path.
contract SavingsEUReDeployerTest is Test {
    IERC20 internal constant EURE = IERC20(Gnosis.EURe);

    function setUp() public {
        MockEURe mock = new MockEURe();
        vm.etch(address(EURE), address(mock).code);
    }

    /// Both branches of `bytes(mnemonic).length > 30` in one test so coverage reliably records each path.
    function testRun_keyResolution_mnemonicThenPrivateKey() public {
        string memory mnemonic = "test test test test test test test test test test test junk";
        // forge-lint: disable-next-line(unsafe-cheatcode)
        uint256 mnemonicPrivateKey = vm.deriveKey(mnemonic, 0);
        // forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MNEMONIC", mnemonic);
        _assertRunSeedsSavingsEuRe(mnemonicPrivateKey);

        uint256 envPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        // forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MNEMONIC", "short");
        // forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("PRIVATE_KEY", vm.toString(envPrivateKey));
        _assertRunSeedsSavingsEuRe(envPrivateKey);
    }

    function _assertRunSeedsSavingsEuRe(uint256 deployerPrivateKey) internal {
        vm.chainId(100);
        address deployer = vm.addr(deployerPrivateKey);
        address expectedSavingsEURe = vm.computeCreateAddress(deployer, vm.getNonce(deployer) + 2);

        deal(address(EURE), deployer, 203 ether);
        new SavingsEUReDeployer().run();

        SavingsEURe savingsEURe = SavingsEURe(payable(expectedSavingsEURe));
        InterestDispatcher interestDispatcher = InterestDispatcher(savingsEURe.interestDispatcher());
        assertTrue(savingsEURe.interestClaimingEnabled());
        assertEq(savingsEURe.totalAssets(), 1 ether);
        assertEq(savingsEURe.maxWithdraw(deployer), 1 ether);
        assertGt(savingsEURe.balanceOf(deployer), 0);
        assertEq(address(interestDispatcher.vault()), address(savingsEURe));
        assertEq(interestDispatcher.owner(), deployer);
        assertGt(interestDispatcher.lastClaimTimestamp(), 0);
        assertGt(interestDispatcher.dripRate(), 0);
        assertGe(interestDispatcher.currentEpochBalance(), interestDispatcher.DRIP_PAUSE_THRESHOLD());
    }

    function testRun_revertsOffGnosis() public {
        uint256 envPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        // forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("MNEMONIC", "short");
        // forge-lint: disable-next-line(unsafe-cheatcode)
        vm.setEnv("PRIVATE_KEY", vm.toString(envPrivateKey));
        vm.chainId(1);
        assertEq(block.chainid, 1);
        deal(address(EURE), vm.addr(envPrivateKey), 102 ether);

        SavingsEUReDeployer deployer = new SavingsEUReDeployer();
        vm.expectRevert(abi.encodeWithSelector(SavingsEUReDeployer.InvalidChain.selector, 1));
        deployer.run();
    }
}
