// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {SavingsEURe} from "src/SavingsEURe.sol";
import {InterestDispatcher} from "src/InterestDispatcher.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import {MockEURe} from "./Mocks/MockEURe.sol";

contract PoCStaleEpoch is Test {
    address public deployer = address(1);
    address public alice = address(2);
    address public bob = address(3);

    InterestDispatcher public rcvImpl;
    InterestDispatcher public rcv;
    SavingsEURe public sEURe;
    IERC20 public eure = IERC20(0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430);
    uint256 public epoch;

    function setUp() public {
        MockEURe mockEure = new MockEURe();
        vm.etch(address(eure), address(mockEure).code);

        vm.startPrank(deployer);
        rcvImpl = new InterestDispatcher();
        rcv = InterestDispatcher(address(new ERC1967Proxy(address(rcvImpl), "")));
        sEURe = new SavingsEURe(address(rcv));

        deal(address(eure), deployer, 1 ether);
        eure.approve(address(sEURe), 1 ether);
        sEURe.deposit(1 ether, deployer);

        deal(address(eure), deployer, 200 ether);
        assertTrue(eure.transfer(address(rcv), 200 ether));
        rcv.initialize(address(sEURe), deployer);
        vm.stopPrank();

        epoch = rcv.epochLength();
        deal(address(eure), alice, 1000 ether);
        deal(address(eure), bob, 1000 ether);
    }

    function test_PoC_StaleEpochAfterDrain() public {
        // Claim some yield to advance state
        vm.warp(block.timestamp + epoch / 4);
        uint256 claimed1 = rcv.claim();
        assertGt(claimed1, 0);
        console.log("Claimed (t=epoch/4):", claimed1);

        uint256 afterClaim1Epoch = rcv.currentEpochBalance();
        uint256 afterClaim1Drip = rcv.dripRate();
        console.log("After claim epoch balance:", afterClaim1Epoch);

        // Drain receiver EURe (simulating admin/external action)
        uint256 rcvBalance = eure.balanceOf(address(rcv));
        vm.prank(address(rcv));
        assertTrue(eure.transfer(alice, rcvBalance));

        // Skip past full epoch
        vm.warp(block.timestamp + epoch);

        // Claim with zero balance — state should NOT advance
        uint256 lastClaimBefore = rcv.lastClaimTimestamp();
        uint256 claimed2 = rcv.claim();
        assertEq(claimed2, 0);
        assertEq(rcv.lastClaimTimestamp(), lastClaimBefore);

        // State is stale
        assertEq(rcv.currentEpochBalance(), afterClaim1Epoch);
        assertEq(rcv.dripRate(), afterClaim1Drip);
        console.log("Stale epoch balance (not advanced):", rcv.currentEpochBalance());

        // Refuel receiver
        vm.prank(bob);
        assertTrue(eure.transfer(address(rcv), 200 ether));

        // Claim after refuel — stale epoch balance claimed from refueled amount
        vm.warp(block.timestamp + epoch);
        uint256 claimed3 = rcv.claim();
        assertGt(claimed3, 0);
        console.log("Claimed after refuel:", claimed3);
        // After rollover, state recalibrates to actual balance
        console.log("Post-rollover epoch balance:", rcv.currentEpochBalance());
    }
}
