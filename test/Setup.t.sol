// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {SavingsEURe} from "src/SavingsEURe.sol";
import {InterestDispatcher} from "src/InterestDispatcher.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import {MockEURe} from "./Mocks/MockEURe.sol";

contract SetupTest is Test {
    address public initializer = address(18);
    address public alice = address(16);
    address public bob = address(17);
    InterestDispatcher public rcv;
    InterestDispatcher public rcvImplementation;
    SavingsEURe public sEURe;
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

        rcvImplementation = new InterestDispatcher();
        rcv = InterestDispatcher(address(new ERC1967Proxy(address(rcvImplementation), "")));
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
        epoch = rcv.epochLength();
    }

    /*//////////////////////////////////////////////////////////////
                        INITIALIZER
    //////////////////////////////////////////////////////////////*/

    function testInitialize() public {
        vm.startPrank(initializer);
        if (eure.balanceOf(address(rcv)) >= rcv.MIN_EPOCH_BALANCE()) {
            rcv.initialize(address(sEURe), initializer);
        } else {
            vm.expectRevert(bytes4(keccak256("InsufficientInitialBalance()")));
            rcv.initialize(address(sEURe), initializer);
        }
        vm.stopPrank();
    }

    function testTransferOwnership() public {
        deal(address(eure), address(rcv), 10001 ether);
        vm.startPrank(initializer);
        rcv.initialize(address(sEURe), initializer);
        rcv.transferOwnership(alice);
        console.log("Upgrade owner configured: %s", alice);
        vm.stopPrank();
        assertEq(rcv.owner(), alice);
        vm.startPrank(initializer);
        vm.expectRevert(bytes4(keccak256("NotOwner()")));
        rcv.transferOwnership(bob);
        vm.stopPrank();
    }

    function initializeReceiver() public {
        vm.startPrank(initializer);
        deal(address(eure), address(rcv), 10001 ether);
        rcv.initialize(address(sEURe), initializer);
        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        BASIC TRANSFERS
    //////////////////////////////////////////////////////////////*/
    function testDonateEURe() public {
        uint256 initialPreview = sEURe.previewRedeem(10000);
        // Bob does a donation
        vm.startPrank(bob);
        assertTrue(eure.transfer(address(sEURe), 10e18));
        assertTrue(eure.transfer(address(rcv), 100e18));

        vm.stopPrank();
        assertEq(eure.balanceOf(address(sEURe)), sEURe.totalAssets());
        assertGe(sEURe.previewRedeem(10000), initialPreview);
    }

    function donateReceiverEure() public {
        vm.startPrank(bob);
        assertTrue(eure.transfer(address(rcv), 3000e18));
        vm.stopPrank();
    }

    function testTopInterestDispatcher() public {
        uint256 initialDripRate = rcv.dripRate();
        uint256 initialNextClaimEpoch = rcv.nextClaimEpoch();
        uint256 initialCurrentEpochBalance = rcv.currentEpochBalance();
        uint256 initialLastClaimTimestamp = rcv.lastClaimTimestamp();
        // Bob does a donation
        vm.startPrank(bob);
        assertTrue(eure.transfer(address(rcv), 1000e18));

        vm.stopPrank();
        assertEq(rcv.dripRate(), initialDripRate);
        assertEq(rcv.nextClaimEpoch(), initialNextClaimEpoch);
        assertEq(rcv.currentEpochBalance(), initialCurrentEpochBalance);
        assertEq(rcv.lastClaimTimestamp(), initialLastClaimTimestamp);
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
