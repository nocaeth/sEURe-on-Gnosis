// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.35;

import {SetupTestBase} from "./Setup.t.sol";
import {InterestDispatcherV2} from "./Mocks/InterestDispatcherV2.sol";

/// @notice Same fixture as {SetupTestBase}, then bootstrap the dispatcher and UUPS-upgrade it to {InterestDispatcherV2}.
/// @dev Use for tests that must run against the proxy **after** an implementation upgrade. Typed view: {dispatcherV2}.
abstract contract InterestDispatcherPostUpgradeSetup is SetupTestBase {
    /// @dev Proxy at `address(rcv)`, typed as the upgraded implementation.
    InterestDispatcherV2 public dispatcherV2;

    function setUp() public virtual override {
        super.setUp();
        _bootstrapReceiverAndUpgradeDispatcher();
        dispatcherV2 = InterestDispatcherV2(address(rcv));
    }

    /// @dev Funds the proxy, `bootstrap`s, then `upgradeToAndCall` to V2 (owner prank).
    function _bootstrapReceiverAndUpgradeDispatcher() internal {
        vm.startPrank(initializer);
        deal(address(eure), address(rcv), 10001 ether);
        rcv.bootstrap(address(sEURe));
        InterestDispatcherV2 impl = new InterestDispatcherV2();
        rcv.upgradeToAndCall(address(impl), "");
        vm.stopPrank();
    }
}
