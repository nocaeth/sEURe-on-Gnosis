// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.35;

import {InterestDispatcherV2} from "./Mocks/InterestDispatcherV2.sol";
import {InterestDispatcherPostUpgradeSetup} from "./SetupInterestDispatcherPostUpgrade.t.sol";

/// @notice Dispatcher behaviour after UUPS upgrade (see {InterestDispatcherPostUpgradeSetup}).
contract InterestDispatcherPostUpgradeTest is InterestDispatcherPostUpgradeSetup {
    function testPostUpgrade_reportsV2Version() public view {
        assertEq(dispatcherV2.version(), 2);
        assertEq(address(dispatcherV2), address(rcv));
    }

    function testPostUpgrade_preservesVaultOwnerAndEpochState() public view {
        assertEq(address(rcv.vault()), address(sEURe));
        assertEq(rcv.owner(), initializer);
        assertTrue(sEURe.interestClaimingEnabled());
        assertGt(rcv.dripRate(), 0);
        assertGe(rcv.currentEpochBalance(), rcv.MIN_INITIAL_BALANCE());
    }

    function testPostUpgrade_claimStillAccrues() public {
        uint256 rate = rcv.dripRate();
        skipTime(1 hours);
        vm.prank(bob, bob);
        uint256 claimed = rcv.claim();
        assertEq(claimed, rate * 1 hours);
        assertGt(claimed, 0);
    }

    function testPostUpgrade_nonOwnerCannotUpgradeAgain() public {
        InterestDispatcherV2 another = new InterestDispatcherV2();
        vm.prank(alice);
        vm.expectRevert(bytes4(keccak256("NotOwner()")));
        rcv.upgradeToAndCall(address(another), "");
    }
}
