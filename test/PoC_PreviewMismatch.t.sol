// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {console} from "forge-std/console.sol";
import {SavingsEURe} from "src/SavingsEURe.sol";
import {InterestDispatcher} from "src/InterestDispatcher.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import {MockEURe} from "./Mocks/MockEURe.sol";

contract PoCPreviewMismatch is Test {
    address public deployer = address(1);
    address public alice = address(2);

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
        deal(address(eure), alice, 100 ether);
    }

    function test_PreviewMatchesExecutionAfterYieldAccrues() public {
        // Skip time so claimable yield accrues
        vm.warp(block.timestamp + epoch / 2);

        // Alice checks previewDeposit (now includes pending claimable yield via totalAssets override)
        uint256 previewShares = sEURe.previewDeposit(10 ether);
        console.log("Preview shares for 10 EURe:", previewShares);

        // Alice deposits — deposit calls _claimInterest first (adds yield to vault)
        vm.startPrank(alice);
        eure.approve(address(sEURe), 10 ether);
        uint256 actualShares = sEURe.deposit(10 ether, alice);
        vm.stopPrank();
        console.log("Actual shares for 10 EURe:", actualShares);

        // Preview now matches execution
        assertEq(actualShares, previewShares);
    }
}
