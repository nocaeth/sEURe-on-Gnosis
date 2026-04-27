// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {console} from "forge-std/console.sol";
import {SetupTest} from "./Setup.t.sol";
import {MockEURe} from "./Mocks/MockEURe.sol";
import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {ISavingsEUReAdapter} from "src/interfaces/ISavingsEUReAdapter.sol";

contract AdapterCaller {
    function deposit(address adapter, address eure, uint256 assets, address receiver) external returns (uint256) {
        IERC20(eure).approve(adapter, assets);
        return ISavingsEUReAdapter(adapter).deposit(assets, receiver);
    }
}

contract SavingsEUReAdapterTest is SetupTest {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event ClaimFailed(bytes reason);

    function testMetadata() public view {
        assertEq(address(rcv), address(rcv));
        assertEq(sEURe.name(), "Savings EURe");
        assertEq(sEURe.symbol(), "sEURe");
        assertEq(sEURe.asset(), address(eure));
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
        donateReceiverEure();
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
        uint256 initialEuRe = eure.balanceOf(receiver);
        vm.startPrank(alice);
        sEURe.approve(address(adapter), initialShares);
        uint256 maxWithdraw = sEURe.maxWithdraw(owner);
        uint256 shares = adapter.redeemAll(receiver);
        vm.stopPrank();
        assertEq(sEURe.balanceOf(owner), 0);
        assertGe(sEURe.totalAssets(), sEURe.maxWithdraw(owner));
        assertEq(0, sEURe.maxWithdraw(owner));
        assertEq(eure.balanceOf(receiver), initialEuRe + maxWithdraw);
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
        uint256 sharesErc20A = adapter.deposit(assets, alice);
        uint256 assetsErc20A = adapter.mint(sharesErc20A, alice);
        assertEq(assetsErc20A, assets);
        vm.stopPrank();
        vm.startPrank(bob);
        eureBalance = eure.balanceOf(bob);
        assertGe(eureBalance, assets * 2);
        eure.approve(address(adapter), eureBalance);
        uint256 sharesErc20B = adapter.deposit(assets, bob);
        uint256 assetsErc20B = adapter.mint(sharesErc20B, bob);
        assertEq(assetsErc20B, assets);
        vm.stopPrank();
        assertGt(sharesErc20A, 100);
    }

    // checks that withdraw and redeem return the same shares given equivalent inputs.
    function test_CompareAllTypes_Withdrawals() public {
        setClaimerAndInitialize();
        uint256 assets = 1e18;
        vm.startPrank(alice, alice);
        rcv.claim();
        vm.stopPrank();
        vm.startPrank(alice);
        uint256 initialSharesA = sEURe.balanceOf(alice);
        sEURe.approve(address(adapter), sEURe.convertToShares(assets * 2));

        // Deposit, withdraw, deposit again, redeem
        eure.approve(address(adapter), assets * 2);
        uint256 sharesDepositedA = adapter.deposit(assets, alice);
        uint256 sharesErc20A = adapter.withdraw(assets, alice);
        uint256 sharesDepositedA1 = adapter.deposit(assets, alice);
        uint256 assetsErc20A = adapter.redeem(sharesErc20A, alice);
        assertGe(assetsErc20A, assets);
        assertEq(sharesDepositedA, sharesDepositedA1);
        vm.stopPrank();

        vm.startPrank(bob);
        sEURe.approve(address(adapter), sEURe.convertToShares(assets * 2));
        eure.approve(address(adapter), assets * 2);
        uint256 sharesDepositedB = adapter.deposit(assets, bob);
        uint256 sharesErc20B = adapter.withdraw(assets, bob);
        uint256 sharesDepositedB1 = adapter.deposit(assets, bob);
        uint256 assetsErc20B = adapter.redeem(sharesErc20B, bob);
        assertGe(assetsErc20B, assets);
        assertEq(sharesDepositedB, sharesDepositedB1);
        vm.stopPrank();
        assertEq(sEURe.balanceOf(alice), initialSharesA);
        assertEq(sharesDepositedA, sharesDepositedB);
        assertEq(sharesErc20A, sharesErc20B);
        assertGt(sharesErc20A, 100);
    }

    function testVaultAPY_matchesReceiver() public {
        setClaimerAndInitialize();
        vm.startPrank(alice);
        eure.approve(address(adapter), 20e18);
        adapter.deposit(10e18, alice);
        vm.stopPrank();
        assertEq(adapter.vaultAPY(), rcv.vaultAPY());
    }

    function testWithdraw_clampsToMaxWithdraw() public {
        setClaimerAndInitialize();
        vm.startPrank(alice, alice);
        eure.approve(address(adapter), 5e18);
        adapter.deposit(5e18, alice);
        vm.stopPrank();
        uint256 maxW = sEURe.maxWithdraw(alice);
        vm.startPrank(alice);
        sEURe.approve(address(adapter), type(uint256).max);
        uint256 shares = adapter.withdraw(type(uint256).max, alice);
        vm.stopPrank();
        assertEq(shares, sEURe.previewWithdraw(maxW));
        assertEq(eure.balanceOf(alice), 100e18 - 5e18 + maxW);
    }

    function testRedeem_clampsToMaxRedeem() public {
        setClaimerAndInitialize();
        vm.startPrank(alice, alice);
        eure.approve(address(adapter), 5e18);
        adapter.deposit(5e18, alice);
        vm.stopPrank();
        uint256 maxS = sEURe.maxRedeem(alice);
        vm.startPrank(alice);
        sEURe.approve(address(adapter), type(uint256).max);
        uint256 assets = adapter.redeem(type(uint256).max, alice);
        vm.stopPrank();
        assertEq(assets, sEURe.previewRedeem(maxS));
        assertEq(sEURe.balanceOf(alice), 0);
    }

    /// EOA path: `msg.sender == tx.origin` runs `_claimHook` / `interestReceiver.claim()`.
    function testDeposit_EoaPrankInvokesClaimHook() public {
        setClaimerAndInitialize();
        skipTime(1 hours);
        uint256 expectedClaim = rcv.dripRate() * 1 hours;
        uint256 rcvBefore = eure.balanceOf(address(rcv));
        vm.startPrank(alice, alice);
        eure.approve(address(adapter), 2e18);
        adapter.deposit(1e18, alice);
        vm.stopPrank();
        assertEq(rcvBefore - eure.balanceOf(address(rcv)), expectedClaim);
    }

    function testDeposit_ContractCallerSkipsClaimHook() public {
        setClaimerAndInitialize();
        skipTime(1 hours);

        AdapterCaller caller = new AdapterCaller();
        deal(address(eure), address(caller), 1e18);

        uint256 rcvBefore = eure.balanceOf(address(rcv));
        uint256 shares = caller.deposit(address(adapter), address(eure), 1e18, bob);

        assertGt(shares, 0);
        assertEq(sEURe.balanceOf(bob), shares);
        assertEq(eure.balanceOf(address(rcv)), rcvBefore);
    }

    function testDeposit_claimRevertLeavesReceiverStateUnchangedAndDeposits() public {
        setClaimerAndInitialize();
        skipTime(1 hours);

        uint256 beforeCurrentEpochBalance = rcv.currentEpochBalance();
        uint256 beforeDripRate = rcv.dripRate();
        uint256 beforeNextClaimEpoch = rcv.nextClaimEpoch();
        uint256 beforeLastClaimTimestamp = rcv.lastClaimTimestamp();
        uint256 beforeReceiverBalance = eure.balanceOf(address(rcv));
        uint256 beforeVaultBalance = eure.balanceOf(address(sEURe));
        uint256 beforeAliceBalance = eure.balanceOf(alice);

        MockEURe(address(eure)).setRevertingSender(address(rcv), true);

        vm.startPrank(alice, alice);
        eure.approve(address(adapter), 1e18);
        vm.expectEmit(false, false, false, false, address(adapter));
        emit ClaimFailed("");
        uint256 shares = adapter.deposit(1e18, alice);
        vm.stopPrank();

        assertGt(shares, 0);
        assertEq(sEURe.balanceOf(alice), shares);
        assertEq(eure.balanceOf(alice), beforeAliceBalance - 1e18);
        assertEq(eure.balanceOf(address(sEURe)), beforeVaultBalance + 1e18);
        assertEq(rcv.currentEpochBalance(), beforeCurrentEpochBalance);
        assertEq(rcv.dripRate(), beforeDripRate);
        assertEq(rcv.nextClaimEpoch(), beforeNextClaimEpoch);
        assertEq(rcv.lastClaimTimestamp(), beforeLastClaimTimestamp);
        assertEq(eure.balanceOf(address(rcv)), beforeReceiverBalance);
    }
}
