// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import "./Setup.t.sol";

contract PoCTR1 is SetupTest {
    // Simulates TR-1: balance reduction after epoch start should claim only available EURe.
    function test_TR1_balanceReductionCapsEpochRolloverClaim() public {
        setClaimerAndInitialize();

        uint256 initialBalance = eure.balanceOf(address(rcv));
        assertGt(initialBalance, 0);

        // Skip past epoch end
        skipTime(epoch + 1);

        // Simulate balance reduction by forcibly setting EURe balance lower
        // (in production: Monerium burn/seize mechanism)
        uint256 claimable = rcv.currentEpochBalance();
        uint256 reducedBalance = claimable / 2;
        deal(address(eure), address(rcv), reducedBalance);

        // Claim should degrade gracefully to the available receiver balance.
        vm.prank(bob, bob);
        uint256 claimed = rcv.claim();

        assertEq(claimed, reducedBalance);
        assertEq(eure.balanceOf(address(rcv)), 0);
        assertEq(eure.balanceOf(address(sEURe)), reducedBalance);
        assertEq(rcv.currentEpochBalance(), 0);
        assertEq(rcv.dripRate(), 0);
    }

    // Balance reduction can also make accrued mid-epoch claimable exceed live balance.
    function test_TR1_balanceReductionCapsMidEpochClaim() public {
        setClaimerAndInitialize();

        skipTime(epoch / 2);

        uint256 accruedClaim = rcv.dripRate() * (epoch / 2);
        uint256 reducedBalance = accruedClaim / 2;
        deal(address(eure), address(rcv), reducedBalance);

        vm.prank(bob, bob);
        uint256 claimed = rcv.claim();

        assertEq(claimed, reducedBalance);
        assertEq(eure.balanceOf(address(rcv)), 0);
        assertEq(eure.balanceOf(address(sEURe)), reducedBalance);
    }

    // Verify the safe path: no underflow when balance >= claimable
    function test_TR1_noUnderflowWhenBalanceSufficient() public {
        setClaimerAndInitialize();

        // Skip past epoch end
        skipTime(epoch + 1);

        // Normal claim — balance hasn't changed, should succeed
        uint256 preClaimBalance = eure.balanceOf(address(rcv));
        assertGe(preClaimBalance, rcv.currentEpochBalance());

        vm.prank(bob, bob);
        uint256 claimed = rcv.claim();
        assertGt(claimed, 0);
    }

    // Verify adapter try/catch handles the revert gracefully
    // Tests that even if InterestReceiver.claim() reverts due to TR-1 underflow,
    // adapter operations (deposit/withdraw) continue to work
    function test_TR1_adapterDepositGraceful() public {
        setClaimerAndInitialize();

        // Skip past epoch end
        skipTime(epoch + 1);

        // Reduce receiver balance below claimable to trigger TR-1 underflow
        uint256 claimable = rcv.currentEpochBalance();
        deal(address(eure), address(rcv), claimable / 2);

        // Bob deposits via adapter — claim hook silently catches the underflow revert
        vm.startPrank(bob, bob);
        eure.approve(address(adapter), type(uint256).max);
        uint256 shares = adapter.deposit(10e18, bob);
        vm.stopPrank();

        assertGt(shares, 0);
        assertEq(sEURe.balanceOf(bob), shares);
    }

    // Verify epoch boundary edge case (claiming exactly at nextClaimEpoch)
    function test_edge_epochBoundaryExactTimestamp() public {
        setClaimerAndInitialize();

        // Warp to exactly nextClaimEpoch
        teleport(rcv.nextClaimEpoch());

        vm.prank(bob, bob);
        uint256 claimed = rcv.claim();

        // Should claim approximately currentEpochBalance (partial-epoch path with full time)
        uint256 expectedClaim = rcv.epochLength() * rcv.dripRate();
        // Allow for integer division rounding
        assertApproxEqAbs(claimed, expectedClaim, 1 ether);
    }
}
