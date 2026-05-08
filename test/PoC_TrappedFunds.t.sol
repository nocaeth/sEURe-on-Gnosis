// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {SavingsEURe} from "src/SavingsEURe.sol";
import {InterestDispatcher} from "src/InterestDispatcher.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import {Gnosis} from "src/constants/Gnosis.sol";
import {MockEURe} from "./Mocks/MockEURe.sol";

contract PoCTrappedFunds is Test {
    address public deployer = address(1);
    address public alice = address(2);
    address public funder = address(3);

    InterestDispatcher public rcvImpl;
    InterestDispatcher public rcv;
    SavingsEURe public sEURe;
    IERC20 public eure = IERC20(Gnosis.EURe);
    uint256 public epoch;

    function setUp() public {
        MockEURe mockEure = new MockEURe();
        vm.etch(address(eure), address(mockEure).code);

        vm.startPrank(deployer);
        rcvImpl = new InterestDispatcher();
        bytes memory initData = abi.encodeCall(InterestDispatcher.initialize, (deployer));
        rcv = InterestDispatcher(address(new ERC1967Proxy(address(rcvImpl), initData)));
        sEURe = new SavingsEURe(address(rcv));

        deal(address(eure), deployer, 1 ether);
        eure.approve(address(sEURe), 1 ether);
        sEURe.deposit(1 ether, deployer);

        deal(address(eure), deployer, 200 ether);
        assertTrue(eure.transfer(address(rcv), 200 ether));
        rcv.bootstrap(address(sEURe));
        vm.stopPrank();

        epoch = rcv.EPOCH_LENGTH();
        deal(address(eure), alice, 1000 ether);
        deal(address(eure), funder, 1000 ether);
    }

    function test_PoC_EUReTrappedBelowMinEpoch() public {
        // Phase 1: Claim some yield, leaving ~150 EURe in stale epoch balance
        vm.warp(block.timestamp + epoch / 4);
        rcv.claim();
        uint256 staleEpochBal = rcv.currentEpochBalance();
        console.log("Stale epoch balance:", staleEpochBal);

        // Phase 2: Drain receiver
        uint256 rcvBal = eure.balanceOf(address(rcv));
        vm.prank(address(rcv));
        assertTrue(eure.transfer(alice, rcvBal));

        vm.warp(block.timestamp + epoch);
        rcv.claim(); // returns 0, state not advanced

        // Phase 3: Refuel with amount where remaining < DRIP_PAUSE_THRESHOLD
        // Stale epoch claims staleEpochBal, leaving refuel - staleEpochBal as remaining
        // We want remaining < 100 ether but > 0
        // So refuel = staleEpochBal + 50 ether
        uint256 refuelAmount = staleEpochBal + 50 ether;
        vm.prank(funder);
        assertTrue(eure.transfer(address(rcv), refuelAmount));
        console.log("Refueled:", refuelAmount);

        vm.warp(block.timestamp + epoch);
        uint256 claimed = rcv.claim();
        console.log("Claimed:", claimed);

        // HARM: dripRate = 0 because remaining = 50 < DRIP_PAUSE_THRESHOLD
        uint256 remaining = eure.balanceOf(address(rcv));
        console.log("Remaining EURe in receiver:", remaining);
        console.log("dripRate:", rcv.dripRate());
        console.log("currentEpochBalance:", rcv.currentEpochBalance());

        assertGt(remaining, 0);
        assertEq(rcv.dripRate(), 0);
        assertEq(rcv.currentEpochBalance(), 0);

        // Verify: future claims can't drip the trapped EURe
        vm.warp(block.timestamp + 10 * epoch);
        uint256 futureClaim = rcv.claim();
        console.log("Future claim (10 epochs later):", futureClaim);
        assertEq(futureClaim, 0);
        assertEq(eure.balanceOf(address(rcv)), remaining); // EURe still trapped
    }
}
