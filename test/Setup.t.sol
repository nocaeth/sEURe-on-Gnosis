// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {SavingsEURe} from "src/SavingsEURe.sol";
import {InterestDispatcher} from "src/InterestDispatcher.sol";
import {IInterestDispatcher} from "src/interfaces/IInterestDispatcher.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import {Gnosis} from "src/constants/Gnosis.sol";
import {MockEURe} from "./Mocks/MockEURe.sol";

/// @dev Shared fixture: mock EURe, dispatcher proxy, vault, actors. No `test*` entries — use {SetupTest} or a specialized harness.
abstract contract SetupTestBase is Test {
    address public initializer = address(18);
    address public alice = address(16);
    address public bob = address(17);
    InterestDispatcher public rcv;
    SavingsEURe public sEURe;
    IERC20 public eure = IERC20(Gnosis.EURe);
    uint256 public globalTime;
    uint256 public epoch;

    function setUp() public virtual {
        MockEURe mockEure = new MockEURe();
        vm.etch(address(eure), address(mockEure).code);

        vm.startPrank(initializer);

        InterestDispatcher implementation = new InterestDispatcher();
        bytes memory initData = abi.encodeCall(InterestDispatcher.initialize, (initializer));
        rcv = InterestDispatcher(address(new ERC1967Proxy(address(implementation), initData)));
        console.log("Deployed InterestDispatcher proxy on Gnosis: %s", address(rcv));

        sEURe = new SavingsEURe(address(rcv));
        console.log("Deployed sEURe on Gnosis: %s", address(sEURe));
        vm.stopPrank();

        deal(address(eure), initializer, 100e18);
        assertEq(eure.balanceOf(initializer), 100e18);

        deal(address(eure), alice, 100e18);
        assertEq(eure.balanceOf(alice), 100e18);

        deal(address(eure), bob, 10000e18);
        assertEq(eure.balanceOf(bob), 10000e18);
        globalTime = block.timestamp;
        epoch = rcv.EPOCH_LENGTH();
    }

    function initializeReceiver() public virtual {
        vm.startPrank(initializer);
        deal(address(eure), address(rcv), 10001 ether);
        rcv.bootstrap(address(sEURe));
        vm.stopPrank();
    }

    function donateReceiverEure() public {
        vm.startPrank(bob);
        assertTrue(eure.transfer(address(rcv), 3000e18));
        vm.stopPrank();
    }

    function teleport(uint256 _timestamp) public {
        globalTime = _timestamp;
        vm.warp(globalTime);
    }

    function skipTime(uint256 secs) public {
        globalTime += secs;
        vm.warp(globalTime);
    }

    /// @dev EURe sent to the receiver must not alter drip schedule / epoch bookkeeping (regression helper).
    function assertReceiverTopUpIsAccountingOnly() internal {
        uint256 initialDripRate = rcv.dripRate();
        uint256 initialNextClaimEpoch = rcv.nextClaimEpoch();
        uint256 initialCurrentEpochBalance = rcv.currentEpochBalance();
        uint256 initialLastClaimTimestamp = rcv.lastClaimTimestamp();
        vm.startPrank(bob);
        assertTrue(eure.transfer(address(rcv), 1000e18));
        vm.stopPrank();
        assertEq(rcv.dripRate(), initialDripRate);
        assertEq(rcv.nextClaimEpoch(), initialNextClaimEpoch);
        assertEq(rcv.currentEpochBalance(), initialCurrentEpochBalance);
        assertEq(rcv.lastClaimTimestamp(), initialLastClaimTimestamp);
    }
}

/// @notice Default fixture plus smoke tests (`testBootstrap`, transfers, etc.).
contract SetupTest is SetupTestBase {
    function testBootstrap() public {
        vm.startPrank(initializer);
        vm.expectRevert(
            abi.encodeWithSelector(
                IInterestDispatcher.InsufficientInitialBalance.selector,
                eure.balanceOf(address(rcv)),
                rcv.MIN_INITIAL_BALANCE()
            )
        );
        rcv.bootstrap(address(sEURe));
        vm.stopPrank();
    }

    function testTransferOwnership() public {
        initializeReceiver();
        vm.startPrank(initializer);
        rcv.transferOwnership(alice);
        console.log("Upgrade owner configured: %s", alice);
        vm.stopPrank();
        assertEq(rcv.owner(), alice);
        vm.startPrank(initializer);
        vm.expectRevert(bytes4(keccak256("NotOwner()")));
        rcv.transferOwnership(bob);
        vm.stopPrank();
    }

    function testDonateEURe() public {
        uint256 initialPreview = sEURe.previewRedeem(10000);
        vm.startPrank(bob);
        assertTrue(eure.transfer(address(sEURe), 10e18));
        assertTrue(eure.transfer(address(rcv), 100e18));

        vm.stopPrank();
        assertEq(eure.balanceOf(address(sEURe)), sEURe.totalAssets());
        assertGe(sEURe.previewRedeem(10000), initialPreview);
    }

    function testTopInterestDispatcher() public {
        assertReceiverTopUpIsAccountingOnly();
    }
}
