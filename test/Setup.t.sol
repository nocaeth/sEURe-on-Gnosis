// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {SavingsEURe} from "src/SavingsEURe.sol";
import {InterestReceiver} from "src/InterestReceiver.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import "src/periphery/SavingsEUReAdapter.sol";
import "./Mocks/MockEURe.sol";

contract SetupTest is Test {
    address public initializer = address(18);
    address public alice = address(16);
    address public bob = address(17);
    InterestReceiver public rcv;
    SavingsEURe public sEURe;
    SavingsEUReAdapter public adapter;
    IERC20 public eure = IERC20(0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430);
    uint256 public globalTime;
    uint256 public epoch;

    function setUp() public {
        // Deploy mock ERC-20 bytecode at the EURe address for local testing
        MockEURe mockEure = new MockEURe();
        vm.etch(address(eure), address(mockEure).code);

        vm.startPrank(initializer);

        /*//////////////////////////////////////////////////////////////
                                DEPLOYMENTS
        //////////////////////////////////////////////////////////////*/

        sEURe = new SavingsEURe("Savings EURe", "sEURe");
        console.log("Deployed sEURe on Gnosis: %s", address(sEURe));

        rcv = new InterestReceiver(address(sEURe));
        console.log("Deployed InterestReceiver: %s", address(rcv));

        adapter = new SavingsEUReAdapter(address(rcv), payable(address(sEURe)));
        console.log("Deployed SavingsEUReAdapter on Gnosis: %s", address(adapter));
        vm.stopPrank();

        deal(address(eure), initializer, 100e18);
        assertEq(eure.balanceOf(initializer), 100e18);

        deal(address(eure), alice, 100e18);
        assertEq(eure.balanceOf(alice), 100e18);

        deal(address(eure), bob, 10000e18);
        assertEq(eure.balanceOf(bob), 10000e18);
        globalTime = block.timestamp;
        epoch = rcv.epochLength();
    }

    /*//////////////////////////////////////////////////////////////
                        INITIALIZER
    //////////////////////////////////////////////////////////////*/

    function testInitialize() public {
        vm.startPrank(initializer);
        if (eure.balanceOf(address(rcv)) > 10000 ether) {
            rcv.initialize();
        } else {
            vm.expectRevert("Fill it up first");
            rcv.initialize();
        }
        vm.stopPrank();
    }

    function testSetClaimer() public {
        assertEq(rcv.claimer(), initializer);
        vm.startPrank(initializer);
        rcv.setClaimer(address(adapter));
        console.log("Claimer configured: %s", address(adapter));
        vm.stopPrank();
        assertEq(rcv.claimer(), address(adapter));
        vm.startPrank(initializer);
        vm.expectRevert("Not Claimer");
        rcv.setClaimer(bob);
        vm.stopPrank();
    }

    function setClaimerAndInitialize() public {
        vm.startPrank(initializer);
        deal(address(eure), address(rcv), 10001 ether);
        rcv.initialize();
        rcv.setClaimer(address(adapter));
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        BASIC TRANSFERS
    //////////////////////////////////////////////////////////////*/
    function testDonateEURe() public {
        uint256 initialPreview = sEURe.previewRedeem(10000);
        // Bob does a donation
        vm.startPrank(bob);
        eure.transfer(address(sEURe), 10e18);
        eure.transfer(address(rcv), 100e18);

        vm.stopPrank();
        assertEq(eure.balanceOf(address(sEURe)), sEURe.totalAssets());
        assertGe(sEURe.previewRedeem(10000), initialPreview);
    }

    function donateReceiverEURe() public {
        vm.startPrank(bob);
        eure.transfer(address(rcv), 3000e18);
        vm.stopPrank();
    }

    function testTopInterestReceiver() public {
        uint256 initialPreview = rcv.previewClaimable();
        // Bob does a donation
        vm.startPrank(bob);
        eure.transfer(address(rcv), 1000e18);

        vm.stopPrank();
        assertEq(rcv.previewClaimable(), initialPreview);
    }

    /*//////////////////////////////////////////////////////////////
                        UTILS
    //////////////////////////////////////////////////////////////*/

    function teleport(uint256 _timestamp) public {
        globalTime = _timestamp;
        vm.warp(globalTime);
    }

    function skipTime(uint256 secs) public {
        globalTime += secs;
        vm.warp(globalTime);
    }
}
