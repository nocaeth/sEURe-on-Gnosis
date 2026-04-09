// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "./Setup.t.sol";

contract SavingsEUReAdapterTest is SetupTest {
    event Transfer(address indexed from, address indexed to, uint256 value);

    function testMetadata() public {
        assertEq(address(rcv), address(rcv));
        assertEq(address(sEURe.eure()), address(eure));
    }

    /*//////////////////////////////////////////////////////////////
                        CORE LOGIC
    //////////////////////////////////////////////////////////////*/

    function testNoClaimDeposit() public {
        uint256 assets = 1e18;
        address receiver = alice;
        vm.startPrank(receiver);
        eure.approve(address(sEURe), assets);
        uint256 shares = sEURe.deposit(assets, receiver);
        vm.stopPrank();
        assertEq(sEURe.previewDeposit(assets), shares);
    }

    function testDeposit() public {
        donateReceiverEURe();
        setClaimerAndInitialize();
        skipTime(1 hours);
        uint256 assets = 1e18;
        address receiver = alice;
        vm.startPrank(receiver);
        uint256 initialBalance = eure.balanceOf(receiver);
        eure.approve(address(adapter), initialBalance);

        uint256 shares = adapter.deposit(assets, receiver);
        console.log("totalAssets: %e", sEURe.totalAssets());
        console.log("previewDeposit: %e", sEURe.previewDeposit(assets));
        console.log("previewRedeem: %e", sEURe.previewRedeem(sEURe.balanceOf(receiver)));
        console.log("maxWithdraw: %e", sEURe.maxWithdraw(receiver));
        assertEq(sEURe.balanceOf(receiver), shares);
        assertGe(sEURe.totalAssets(), sEURe.maxWithdraw(receiver));
        assertEq(eure.balanceOf(receiver), initialBalance - assets);
        adapter.deposit(assets, address(24));
        vm.stopPrank();
    }

    function testFuzzDeposit(uint256 assets) public {
        setClaimerAndInitialize();
        address receiver = alice;

        uint256 initialAssets = eure.balanceOf(receiver);
        uint256 initialShares = sEURe.balanceOf(receiver);
        vm.assume(assets <= eure.balanceOf(alice));

        vm.startPrank(alice);

        eure.approve(address(adapter), initialAssets);
        uint256 shares = adapter.deposit(assets, receiver);

        assertEq(sEURe.balanceOf(receiver), initialShares + shares);
        assertGe(sEURe.totalAssets(), sEURe.maxWithdraw(receiver));
        assertEq(eure.balanceOf(receiver), initialAssets - assets);

        vm.stopPrank();
    }

    function testFuzzMint(uint256 shares) public {
        setClaimerAndInitialize();
        address receiver = alice;

        uint256 initialAssets = eure.balanceOf(receiver);
        uint256 initialShares = sEURe.balanceOf(receiver);

        vm.assume(shares <= sEURe.convertToShares(eure.balanceOf(alice)));

        vm.startPrank(alice);
        eure.approve(address(adapter), initialAssets);

        uint256 assets = adapter.mint(shares, receiver);

        assertEq(sEURe.balanceOf(receiver), initialShares + shares);
        assertGe(sEURe.totalAssets(), sEURe.maxWithdraw(receiver));
        assertEq(eure.balanceOf(receiver), initialAssets - assets);

        vm.stopPrank();
    }

    function testFuzzWithdraw(uint256 assets) public {
        address receiver = alice;
        address owner = alice;

        testDeposit();

        vm.startPrank(alice);

        vm.assume(assets <= sEURe.maxWithdraw(receiver));

        uint256 initialAssets = eure.balanceOf(receiver);
        uint256 initialShares = sEURe.balanceOf(owner);

        sEURe.approve(address(adapter), initialShares);
        uint256 shares = adapter.withdraw(assets, receiver);

        assertEq(sEURe.balanceOf(owner), initialShares - shares);
        assertGe(sEURe.totalAssets(), sEURe.maxWithdraw(receiver));
        assertEq(eure.balanceOf(receiver), initialAssets + assets);

        vm.stopPrank();
    }

    function testFuzzRedeem(uint256 shares) public {
        address receiver = alice;
        address owner = alice;

        testDeposit();

        uint256 initialAssets = eure.balanceOf(receiver);
        uint256 initialShares = sEURe.balanceOf(owner);

        vm.assume(shares <= initialShares);

        vm.startPrank(alice);
        sEURe.approve(address(adapter), shares);

        uint256 assets = adapter.redeem(shares, receiver);

        assertEq(sEURe.balanceOf(owner), initialShares - shares);
        assertGe(sEURe.totalAssets(), sEURe.maxWithdraw(receiver));
        assertEq(eure.balanceOf(receiver), initialAssets + assets);

        vm.stopPrank();
    }

    function testRedeemAll() public {
        address receiver = alice;
        address owner = alice;

        testDeposit();

        uint256 initialShares = sEURe.balanceOf(owner);
        uint256 initialEURe = eure.balanceOf(receiver);
        vm.startPrank(alice);
        sEURe.approve(address(adapter), initialShares);
        uint256 maxWithdraw = sEURe.maxWithdraw(owner);
        uint256 shares = adapter.redeemAll(receiver);
        vm.stopPrank();
        assertEq(sEURe.balanceOf(owner), 0);
        assertGe(sEURe.totalAssets(), sEURe.maxWithdraw(owner));
        assertEq(0, sEURe.maxWithdraw(owner));
        assertEq(eure.balanceOf(receiver), initialEURe + maxWithdraw);
        if (shares > 0 && eure.balanceOf(address(sEURe)) == 0) {
            revert();
        }
    }

    /*//////////////////////////////////////////////////////////////
                        SPECIAL STATES
    //////////////////////////////////////////////////////////////*/

    function testMintAndWithdraw(uint256 shares) public {
        setClaimerAndInitialize();
        uint256 initialAssets = eure.balanceOf(alice);
        vm.assume(shares < sEURe.convertToShares(initialAssets));

        vm.startPrank(alice);

        eure.approve(address(adapter), initialAssets);
        uint256 assets = adapter.mint(shares, alice);
        sEURe.approve(address(adapter), sEURe.balanceOf(alice));
        uint256 maxW = sEURe.maxWithdraw(alice);
        uint256 toWithdraw = assets > maxW ? maxW : assets;
        uint256 shares2 = adapter.withdraw(toWithdraw, alice);
        assertGe(shares2, 0);

        vm.stopPrank();
    }

    // checks that deposit and mint return the same shares given equivalent inputs.
    function test_CompareAllTypes_Deposits() public {
        setClaimerAndInitialize();
        uint256 assets = 1e18;

        vm.startPrank(alice);
        uint256 eureBalance = eure.balanceOf(alice);

        assertGe(eureBalance, assets * 2);

        eure.approve(address(adapter), eureBalance);
        uint256 sharesERC20_a = adapter.deposit(assets, alice);
        uint256 assetsERC20_a = adapter.mint(sharesERC20_a, alice);
        assertEq(assetsERC20_a, assets);
        vm.stopPrank();
        vm.startPrank(bob);
        eureBalance = eure.balanceOf(bob);
        assertGe(eureBalance, assets * 2);
        eure.approve(address(adapter), eureBalance);
        uint256 sharesERC20_b = adapter.deposit(assets, bob);
        uint256 assetsERC20_b = adapter.mint(sharesERC20_b, bob);
        assertEq(assetsERC20_b, assets);
        vm.stopPrank();
        assertGt(sharesERC20_a, 100);
    }

    // checks that withdraw and redeem return the same shares given equivalent inputs.
    function test_CompareAllTypes_Withdrawals() public {
        setClaimerAndInitialize();
        uint256 assets = 1e18;
        vm.startPrank(alice, alice);
        rcv.claim();
        vm.stopPrank();
        vm.startPrank(alice);
        uint256 initialShares_a = sEURe.balanceOf(alice);
        sEURe.approve(address(adapter), sEURe.convertToShares(assets * 2));

        // Deposit, withdraw, deposit again, redeem
        eure.approve(address(adapter), assets * 2);
        uint256 sharesDeposited_a = adapter.deposit(assets, alice);
        uint256 sharesERC20_a = adapter.withdraw(assets, alice);
        uint256 sharesDeposited_a1 = adapter.deposit(assets, alice);
        uint256 assetsERC20_a = adapter.redeem(sharesERC20_a, alice);
        assertGe(assetsERC20_a, assets);
        assertEq(sharesDeposited_a, sharesDeposited_a1);
        vm.stopPrank();

        vm.startPrank(bob);
        sEURe.approve(address(adapter), sEURe.convertToShares(assets * 2));
        eure.approve(address(adapter), assets * 2);
        uint256 sharesDeposited_b = adapter.deposit(assets, bob);
        uint256 sharesERC20_b = adapter.withdraw(assets, bob);
        uint256 sharesDeposited_b1 = adapter.deposit(assets, bob);
        uint256 assetsERC20_b = adapter.redeem(sharesERC20_b, bob);
        assertGe(assetsERC20_b, assets);
        assertEq(sharesDeposited_b, sharesDeposited_b1);
        vm.stopPrank();
        assertEq(sEURe.balanceOf(alice), initialShares_a);
        assertEq(sharesDeposited_a, sharesDeposited_b);
        assertEq(sharesERC20_a, sharesERC20_b);
        assertGt(sharesERC20_a, 100);
    }
}
