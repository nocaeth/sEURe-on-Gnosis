// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "./Setup.t.sol";

contract InterestReceiverTest is SetupTest {
    /*//////////////////////////////////////////////////////////////
                        BASIC VALIDATION
    //////////////////////////////////////////////////////////////*/
    function testMetadata() public {
        assertEq(address(rcv), address(rcv));
        assertEq(address(sEURe.eure()), address(eure));
    }

    function testAlreadyInitialized() public {
        setClaimerAndInitialize();
        vm.startPrank(initializer);
        vm.expectRevert(abi.encodeWithSignature("AlreadyInitialized()"));
        rcv.initialize();
    }

    function testInitialize_anyoneAllowed() external {
        vm.startPrank(alice);
        deal(address(eure), address(rcv), 50000 ether);
        rcv.initialize();
    }

    function testInitialize_notEnoughBalance() external {
        vm.startPrank(alice);
        deal(address(eure), address(rcv), 5000 ether);
        vm.expectRevert("Fill it up first");
        rcv.initialize();
    }
    /*//////////////////////////////////////////////////////////////
                        CLAIM LOGIC
    //////////////////////////////////////////////////////////////*/

    function claimEOA() public returns (uint256 claimed) {
        vm.startPrank(bob, bob);
        claimed = rcv.claim();
        vm.stopPrank();
    }

    function testClaim__FromAdapter() public {
        setClaimerAndInitialize();
        skipTime(1 hours);
        uint256 claimable = rcv.previewClaimable();
        // Deposit via adapter using EURe (not native xDAI)
        vm.startPrank(bob, bob);
        eure.approve(address(adapter), 1 ether);
        adapter.deposit(1 ether, bob);
        vm.stopPrank();
        uint256 claimed = claimable - rcv.previewClaimable();
        assertEq(claimable, claimed);
        assertGt(claimed, 0);
    }

    function testClaim__FromContract() public {
        setClaimerAndInitialize();
        skipTime(1 hours);
        vm.expectRevert("Not valid Claimer");
        rcv.claim();
    }

    function testClaim() public {
        testTopInterestReceiver();
        setClaimerAndInitialize();
        uint256 shares = sEURe.totalSupply();
        uint256 totalWithdrawable = sEURe.previewRedeem(shares);
        skipTime(1 days);
        testTopInterestReceiver();
        uint256 sEUReBalance = eure.balanceOf(address(sEURe));
        uint256 rcvBalance = eure.balanceOf(address(rcv));
        uint256 claimed = claimEOA();
        assertLe(sEUReBalance, sEURe.totalAssets());
        assertLe(eure.balanceOf(address(rcv)), rcvBalance);
        assertEq(sEURe.totalSupply(), shares);
        assertLe(totalWithdrawable, sEURe.previewRedeem(shares));
        assertGt(claimed, 0);
        console.log("Claimed %e", claimed);
    }

    function testFuzzClaim(uint256 time) public {
        setClaimerAndInitialize();
        time = bound(time, 0, 2 days);
        require(time >= 0 && time <= 2 days);
        console.log("GlobalTime: %s | Time: %s | CurrentTime: %s", globalTime, time, block.timestamp);
        console.log(
            "nextClaimEpoch: %s | lastClaimTimestamp: %s | dripRate: %s",
            rcv.nextClaimEpoch(),
            rcv.lastClaimTimestamp(),
            rcv.dripRate()
        );

        uint256 shares = sEURe.totalSupply();
        uint256 totalWithdrawable = sEURe.previewRedeem(shares);
        testTopInterestReceiver();
        uint256 sEUReBalance = eure.balanceOf(address(sEURe));
        uint256 rcvBalance = eure.balanceOf(address(rcv));

        uint256 endEpoch = rcv.nextClaimEpoch();
        uint256 lastClaimTime = rcv.lastClaimTimestamp();
        uint256 beforeRate = rcv.dripRate();

        skipTime(time); //skip time
        uint256 claimable = rcv.previewClaimable();
        uint256 epochBalance = rcv.currentEpochBalance();
        uint256 claimed = claimEOA();

        console.log("GlobalTime: %s | Time: %s | CurrentTime: %s", globalTime, time, block.timestamp);
        console.log(
            "nextClaimEpoch: %s | lastClaimTimestamp: %s | dripRate: %s",
            rcv.nextClaimEpoch(),
            rcv.lastClaimTimestamp(),
            rcv.dripRate()
        );

        if (globalTime == lastClaimTime) {
            assertEq(claimed, 0);
            assertGe(eure.balanceOf(address(rcv)), rcvBalance);
        } else if (globalTime >= lastClaimTime + epoch) {
            assertEq(claimed, epochBalance);
            if (rcvBalance - claimable >= epoch && globalTime != endEpoch) {
                assertEq(rcv.nextClaimEpoch(), block.timestamp + epoch);
                assertGt(rcv.dripRate(), 0);
            }
            assertEq(claimable, claimed);
            assertLe(eure.balanceOf(address(rcv)), rcvBalance);
        } else if (globalTime > endEpoch) {
            if (beforeRate > 0) {
                assertGt(claimed, 0);
            }

            if (rcvBalance - claimable >= epoch) {
                assertEq(rcv.nextClaimEpoch(), block.timestamp + epoch);
                assertGt(rcv.dripRate(), 0);
            }
            assertEq(claimable, claimed);
            assertLe(eure.balanceOf(address(rcv)), rcvBalance);
        } else {
            assertEq(epochBalance - claimed, rcv.currentEpochBalance());
            assertEq(claimable, claimed);
            assertLe(eure.balanceOf(address(rcv)), rcvBalance);
        }

        assertEq(eure.balanceOf(address(rcv)), rcvBalance - claimed);
        assertEq(claimed, eure.balanceOf(address(sEURe)) - sEUReBalance);
        assertEq(sEURe.totalSupply(), shares);
        assertLe(sEUReBalance, sEURe.totalAssets());
        assertEq(sEURe.totalSupply(), shares);
        assertLe(totalWithdrawable, sEURe.previewRedeem(shares));

        vm.startPrank(bob);
        eure.transfer(address(rcv), 10e18);
        endEpoch = rcv.nextClaimEpoch();
        lastClaimTime = rcv.lastClaimTimestamp();
        beforeRate = rcv.dripRate();
        rcvBalance = eure.balanceOf(address(rcv));
        console.log("rcvBalance: %s ", rcvBalance);
        skipTime(time); //skip time
        claimable = rcv.previewClaimable();
        epochBalance = rcv.currentEpochBalance();
        claimed = claimEOA();
        console.log("GlobalTime: %s | Time: %s | CurrentTime: %s", globalTime, time, block.timestamp);
        console.log(
            "nextClaimEpoch: %s | lastClaimTimestamp: %s | dripRate: %s",
            rcv.nextClaimEpoch(),
            rcv.lastClaimTimestamp(),
            rcv.dripRate()
        );
        if (globalTime == lastClaimTime) {
            assertEq(claimed, 0);
            assertGe(eure.balanceOf(address(rcv)), rcvBalance);
        } else if (globalTime >= lastClaimTime + epoch) {
            assertEq(claimed, epochBalance);
            if (rcvBalance - claimable >= epoch && globalTime != endEpoch) {
                assertEq(rcv.nextClaimEpoch(), block.timestamp + epoch);
                assertGt(rcv.dripRate(), 0);
            }
            assertEq(claimable, claimed);
            assertLe(eure.balanceOf(address(rcv)), rcvBalance);
        } else if (globalTime > endEpoch) {
            if (beforeRate > 0) {
                assertGt(claimed, 0);
            }

            if (rcvBalance - claimable >= epoch) {
                assertEq(rcv.nextClaimEpoch(), block.timestamp + epoch);
                assertGt(rcv.dripRate(), 0);
            }
            assertEq(claimable, claimed);
            assertLe(eure.balanceOf(address(rcv)), rcvBalance);
        } else {
            assertEq(epochBalance - claimed, rcv.currentEpochBalance());
            assertEq(claimable, claimed);
            assertLe(eure.balanceOf(address(rcv)), rcvBalance);
        }
    }

    function skipFirstEpoch() public {
        skipTime(rcv.nextClaimEpoch() + 1);
        claimEOA();
    }

    /*//////////////////////////////////////////////////////////////
                        CONDITIONAL CHECKS
    //////////////////////////////////////////////////////////////*/

    function testClaim_ifNotInitialized() external {
        vm.expectRevert("Not Initialized");
        claimEOA();
    }

    function testClaim_IncreasedFromZeroBalance() external {
        setClaimerAndInitialize();
        donateReceiverEURe();
        skipFirstEpoch();
        skipTime(1 hours);
        assertEq(rcv.dripRate(), rcv.currentEpochBalance() / epoch);
        assertEq(rcv.nextClaimEpoch(), rcv.lastClaimTimestamp() + epoch);
        uint256 claimed = claimEOA();
        assertEq(claimed, rcv.dripRate() * 1 hours);
    }

    function testClaim_endOfEpochMinus1() external {
        setClaimerAndInitialize();
        donateReceiverEURe();
        skipFirstEpoch();
        skipTime(epoch - 1);
        uint256 rate = rcv.dripRate();
        assertEq(rate, rcv.currentEpochBalance() / epoch);
        assertEq(rcv.nextClaimEpoch(), rcv.lastClaimTimestamp() + epoch);
        uint256 claimed = claimEOA();
        assertEq(claimed, rcv.dripRate() * (epoch - 1));
        assertEq(rcv.dripRate(), rate);
        assertEq(rcv.nextClaimEpoch(), block.timestamp + 1);
    }

    function testClaim_endOfEpoch() external {
        setClaimerAndInitialize();
        donateReceiverEURe();
        skipFirstEpoch();
        skipTime(epoch);
        uint256 rate = rcv.dripRate();
        assertEq(rate, rcv.currentEpochBalance() / epoch);
        assertEq(rcv.nextClaimEpoch(), rcv.lastClaimTimestamp() + epoch);
        uint256 claimed = claimEOA();
        assertApproxEqAbs(claimed, rcv.dripRate() * epoch, 500000);
        assertEq(claimed, rcv.currentEpochBalance());
        assertEq(rcv.dripRate(), rate);
        assertEq(rcv.nextClaimEpoch(), block.timestamp);
    }

    function testClaim_endOfEpochPlus1ButNoDeposits() external {
        setClaimerAndInitialize();
        donateReceiverEURe();
        skipFirstEpoch();
        skipTime(epoch + 1);
        uint256 rate = rcv.dripRate();
        assertEq(rate, rcv.currentEpochBalance() / epoch);
        assertEq(rcv.nextClaimEpoch(), rcv.lastClaimTimestamp() + epoch);
        uint256 claimed = claimEOA();
        assertEq(claimed, rcv.currentEpochBalance());
        assertEq(rcv.dripRate(), 0);
        assertEq(rcv.nextClaimEpoch(), block.timestamp - 1);
    }

    function testClaim_endOfEpochWithNewDeposits() external {
        setClaimerAndInitialize();
        donateReceiverEURe();
        skipFirstEpoch();
        skipTime(epoch / 2);
        donateReceiverEURe();
        skipTime(epoch / 2);
        uint256 rate = rcv.dripRate();
        assertEq(rate, rcv.currentEpochBalance() / epoch);
        assertEq(rcv.nextClaimEpoch(), rcv.lastClaimTimestamp() + epoch);
        uint256 claimed = claimEOA();
        assertApproxEqAbs(claimed, rcv.dripRate() * epoch, 500000);
        assertEq(claimed, rcv.currentEpochBalance());
        assertEq(rcv.dripRate(), rate);
        assertEq(rcv.nextClaimEpoch(), block.timestamp);
    }

    function testClaim_pastEndOfEpochWithNewDeposits() external {
        setClaimerAndInitialize();
        donateReceiverEURe();
        skipFirstEpoch();
        skipTime(epoch / 2);
        donateReceiverEURe();
        donateReceiverEURe();
        uint256 rate = rcv.dripRate();
        uint256 balance = rcv.currentEpochBalance();
        assertEq(rate, balance / epoch);
        assertEq(rcv.nextClaimEpoch(), rcv.lastClaimTimestamp() + epoch);
        uint256 claimed = claimEOA();
        assertApproxEqAbs(claimed, rcv.dripRate() * (epoch / 2), 500000);
        skipTime(epoch);
        uint256 balance1 = rcv.currentEpochBalance();
        uint256 claimed1 = claimEOA();
        assertEq(claimed1, balance1);
        assertEq(claimed1, balance - claimed);
        assertEq(rcv.dripRate(), rcv.currentEpochBalance() / epoch);
        assertEq(rcv.nextClaimEpoch(), block.timestamp + epoch);
    }

    /*//////////////////////////////////////////////////////////////
                        BOT E2E TEST
    //////////////////////////////////////////////////////////////*/

    function testBotDepositE2E() external {
        setClaimerAndInitialize();

        // Alice deposits EURe into vault via adapter
        vm.startPrank(alice, alice);
        eure.approve(address(adapter), 50e18);
        adapter.deposit(50e18, alice);
        vm.stopPrank();

        uint256 initialSharePrice = sEURe.convertToAssets(1e18);

        // Skip first epoch
        skipFirstEpoch();

        // Bot deposits yield (simulating Monerium bot)
        deal(address(eure), address(this), 5000e18);
        eure.transfer(address(rcv), 5000e18);

        // Skip into new epoch so yield gets incorporated
        skipTime(epoch + 1);

        // User interaction triggers claim
        vm.startPrank(bob, bob);
        eure.approve(address(adapter), 1e18);
        adapter.deposit(1e18, bob);
        vm.stopPrank();

        uint256 newSharePrice = sEURe.convertToAssets(1e18);
        assertGt(newSharePrice, initialSharePrice);
    }
}
