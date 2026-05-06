// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {console} from "forge-std/console.sol";
import {ERC1967Proxy} from "openzeppelin/proxy/ERC1967/ERC1967Proxy.sol";
import {InterestDispatcher} from "src/InterestDispatcher.sol";
import {SetupTest} from "./Setup.t.sol";
import {MockEURe} from "./Mocks/MockEURe.sol";

contract InterestDispatcherV2 is InterestDispatcher {
    function version() external pure returns (uint256) {
        return 2;
    }
}

contract InterestDispatcherTest is SetupTest {
    event Initialized(uint256 indexed initialBalance, uint256 dripRate, uint256 nextClaimEpoch);
    event OwnerUpdated(address indexed previousOwner, address indexed newOwner);

    /*//////////////////////////////////////////////////////////////
                        BASIC VALIDATION
    //////////////////////////////////////////////////////////////*/
    function testMetadata() public view {
        assertEq(address(rcv), address(rcv));
        assertEq(sEURe.name(), "Savings EURe");
        assertEq(sEURe.symbol(), "sEURe");
        assertEq(sEURe.asset(), address(eure));
    }

    function testAlreadyInitialized() public {
        initializeReceiver();
        vm.startPrank(initializer);
        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        rcv.initialize(address(sEURe), initializer);
    }

    function testInitialize_rejectsZeroVault() external {
        deal(address(eure), address(rcv), 50000 ether);
        vm.startPrank(initializer);
        vm.expectRevert(bytes4(keccak256("ZeroAddress()")));
        rcv.initialize(address(0), initializer);
        vm.stopPrank();
    }

    function testInitialize_rejectsZeroOwner() external {
        deal(address(eure), address(rcv), 50000 ether);
        vm.startPrank(initializer);
        vm.expectRevert(bytes4(keccak256("ZeroAddress()")));
        rcv.initialize(address(sEURe), address(0));
        vm.stopPrank();
    }

    function testInitialize_notEnoughBalance() external {
        vm.startPrank(initializer);
        deal(address(eure), address(rcv), rcv.MIN_EPOCH_BALANCE() - 1);
        vm.expectRevert(bytes4(keccak256("InsufficientInitialBalance()")));
        rcv.initialize(address(sEURe), initializer);
    }

    function testInitializeEmitsInitialized() external {
        uint256 initialBalance = 50000 ether;
        deal(address(eure), address(rcv), initialBalance);

        vm.startPrank(initializer);
        vm.expectEmit(true, true, true, true);
        emit Initialized(initialBalance, initialBalance / rcv.epochLength(), block.timestamp + rcv.epochLength());
        rcv.initialize(address(sEURe), initializer);
        vm.stopPrank();
    }

    function testInitializeEnablesVaultInterestClaiming() external {
        uint256 initialBalance = 50000 ether;
        deal(address(eure), address(rcv), initialBalance);

        (bool beforeSuccess, bytes memory beforeData) =
            address(sEURe).call(abi.encodeWithSignature("interestClaimingEnabled()"));
        assertTrue(beforeSuccess);
        assertFalse(abi.decode(beforeData, (bool)));

        vm.startPrank(initializer);
        rcv.initialize(address(sEURe), initializer);
        vm.stopPrank();

        (bool afterSuccess, bytes memory afterData) =
            address(sEURe).call(abi.encodeWithSignature("interestClaimingEnabled()"));
        assertTrue(afterSuccess);
        assertTrue(abi.decode(afterData, (bool)));
    }

    function testImplementationInitializationDisabled() external {
        InterestDispatcher implementation = new InterestDispatcher();
        deal(address(eure), address(implementation), 50000 ether);

        vm.expectRevert(abi.encodeWithSignature("InvalidInitialization()"));
        implementation.initialize(address(sEURe), initializer);
    }

    function testImplementationClaimRevertsAfterInitializersDisabled() external {
        InterestDispatcher implementation = new InterestDispatcher();
        deal(address(eure), address(implementation), 50000 ether);

        vm.startPrank(bob, bob);
        vm.expectRevert(bytes4(keccak256("NotInitialized()")));
        implementation.claim();
        vm.stopPrank();
    }

    function testUpgradeToAndCallRejectsUnauthorizedCaller() external {
        initializeReceiver();
        InterestDispatcherV2 newImplementation = new InterestDispatcherV2();

        vm.startPrank(alice);
        vm.expectRevert(bytes4(keccak256("NotOwner()")));
        rcv.upgradeToAndCall(address(newImplementation), "");
        vm.stopPrank();
    }

    function testUpgradeToAndCallAllowsOwner() external {
        initializeReceiver();
        InterestDispatcherV2 newImplementation = new InterestDispatcherV2();

        vm.startPrank(initializer);
        rcv.upgradeToAndCall(address(newImplementation), "");
        vm.stopPrank();

        assertEq(InterestDispatcherV2(address(rcv)).version(), 2);
        assertEq(address(rcv.sEURe()), address(sEURe));
        assertEq(rcv.owner(), initializer);
    }

    /*//////////////////////////////////////////////////////////////
                        CLAIM LOGIC
    //////////////////////////////////////////////////////////////*/

    function claimEoa() public returns (uint256 claimed) {
        vm.startPrank(bob, bob);
        claimed = rcv.claim();
        vm.stopPrank();
    }

    function testClaim__FromVaultDeposit() public {
        initializeReceiver();
        skipTime(1 hours);
        uint256 expectedClaim = rcv.dripRate() * 1 hours;
        uint256 rcvBalance = eure.balanceOf(address(rcv));

        vm.startPrank(bob, bob);
        eure.approve(address(sEURe), 1 ether);
        sEURe.deposit(1 ether, bob);
        vm.stopPrank();

        uint256 claimed = rcvBalance - eure.balanceOf(address(rcv));
        assertEq(claimed, expectedClaim);
        assertGt(claimed, 0);
    }

    function testClaim__FromContractAllowed() public {
        initializeReceiver();
        skipTime(1 hours);
        uint256 expectedClaim = rcv.dripRate() * 1 hours;
        uint256 rcvBalance = eure.balanceOf(address(rcv));

        uint256 claimed = rcv.claim();

        assertEq(claimed, expectedClaim);
        assertEq(rcvBalance - eure.balanceOf(address(rcv)), expectedClaim);
    }

    function testClaim_transferRevertRollsBackEpochState() public {
        initializeReceiver();
        skipTime(1 hours);

        uint256 beforeCurrentEpochBalance = rcv.currentEpochBalance();
        uint256 beforeDripRate = rcv.dripRate();
        uint256 beforeNextClaimEpoch = rcv.nextClaimEpoch();
        uint256 beforeLastClaimTimestamp = rcv.lastClaimTimestamp();
        uint256 beforeReceiverBalance = eure.balanceOf(address(rcv));
        uint256 beforeVaultBalance = eure.balanceOf(address(sEURe));

        MockEURe(address(eure)).setRevertingSender(address(rcv), true);

        vm.startPrank(bob, bob);
        vm.expectRevert();
        rcv.claim();
        vm.stopPrank();

        assertEq(rcv.currentEpochBalance(), beforeCurrentEpochBalance);
        assertEq(rcv.dripRate(), beforeDripRate);
        assertEq(rcv.nextClaimEpoch(), beforeNextClaimEpoch);
        assertEq(rcv.lastClaimTimestamp(), beforeLastClaimTimestamp);
        assertEq(eure.balanceOf(address(rcv)), beforeReceiverBalance);
        assertEq(eure.balanceOf(address(sEURe)), beforeVaultBalance);
    }

    function testClaim() public {
        testTopInterestDispatcher();
        initializeReceiver();
        uint256 shares = sEURe.totalSupply();
        uint256 totalWithdrawable = sEURe.previewRedeem(shares);
        skipTime(1 days);
        testTopInterestDispatcher();
        uint256 sEuReBalance = eure.balanceOf(address(sEURe));
        uint256 rcvBalance = eure.balanceOf(address(rcv));
        uint256 claimed = claimEoa();
        assertLe(sEuReBalance, sEURe.totalAssets());
        assertLe(eure.balanceOf(address(rcv)), rcvBalance);
        assertEq(sEURe.totalSupply(), shares);
        assertLe(totalWithdrawable, sEURe.previewRedeem(shares));
        assertGt(claimed, 0);
        console.log("Claimed %e", claimed);
    }

    function testFuzzClaim(uint256 time) public {
        initializeReceiver();
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
        testTopInterestDispatcher();
        uint256 sEuReBalance = eure.balanceOf(address(sEURe));
        uint256 rcvBalance = eure.balanceOf(address(rcv));

        uint256 endEpoch = rcv.nextClaimEpoch();
        uint256 lastClaimTime = rcv.lastClaimTimestamp();
        uint256 beforeRate = rcv.dripRate();

        skipTime(time); //skip time
        uint256 epochBalance = rcv.currentEpochBalance();
        uint256 claimed = claimEoa();

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
            if (rcvBalance - claimed >= epoch && globalTime != endEpoch) {
                assertEq(rcv.nextClaimEpoch(), block.timestamp + epoch);
                assertGt(rcv.dripRate(), 0);
            }
            assertLe(eure.balanceOf(address(rcv)), rcvBalance);
        } else if (globalTime > endEpoch) {
            if (beforeRate > 0) {
                assertGt(claimed, 0);
            }

            if (rcvBalance - claimed >= epoch) {
                assertEq(rcv.nextClaimEpoch(), block.timestamp + epoch);
                assertGt(rcv.dripRate(), 0);
            }
            assertLe(eure.balanceOf(address(rcv)), rcvBalance);
        } else {
            assertEq(epochBalance - claimed, rcv.currentEpochBalance());
            assertLe(eure.balanceOf(address(rcv)), rcvBalance);
        }

        assertEq(eure.balanceOf(address(rcv)), rcvBalance - claimed);
        assertEq(claimed, eure.balanceOf(address(sEURe)) - sEuReBalance);
        assertEq(sEURe.totalSupply(), shares);
        assertLe(sEuReBalance, sEURe.totalAssets());
        assertEq(sEURe.totalSupply(), shares);
        assertLe(totalWithdrawable, sEURe.previewRedeem(shares));

        vm.startPrank(bob);
        assertTrue(eure.transfer(address(rcv), 10e18));
        endEpoch = rcv.nextClaimEpoch();
        lastClaimTime = rcv.lastClaimTimestamp();
        beforeRate = rcv.dripRate();
        rcvBalance = eure.balanceOf(address(rcv));
        console.log("rcvBalance: %s ", rcvBalance);
        skipTime(time); //skip time
        epochBalance = rcv.currentEpochBalance();
        claimed = claimEoa();
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
            if (rcvBalance - claimed >= epoch && globalTime != endEpoch) {
                assertEq(rcv.nextClaimEpoch(), block.timestamp + epoch);
                assertGt(rcv.dripRate(), 0);
            }
            assertLe(eure.balanceOf(address(rcv)), rcvBalance);
        } else if (globalTime > endEpoch) {
            if (beforeRate > 0) {
                assertGt(claimed, 0);
            }

            if (rcvBalance - claimed >= epoch) {
                assertEq(rcv.nextClaimEpoch(), block.timestamp + epoch);
                assertGt(rcv.dripRate(), 0);
            }
            assertLe(eure.balanceOf(address(rcv)), rcvBalance);
        } else {
            assertEq(epochBalance - claimed, rcv.currentEpochBalance());
            assertLe(eure.balanceOf(address(rcv)), rcvBalance);
        }
    }

    function skipFirstEpoch() public {
        skipTime(rcv.nextClaimEpoch() + 1);
        claimEoa();
    }

    /*//////////////////////////////////////////////////////////////
                        CONDITIONAL CHECKS
    //////////////////////////////////////////////////////////////*/

    function testClaim_ifNotInitialized() external {
        vm.expectRevert(bytes4(keccak256("NotInitialized()")));
        claimEoa();
    }

    function testTransferOwnershipEmitsOwnerUpdated() external {
        initializeReceiver();
        vm.startPrank(initializer);
        vm.expectEmit(true, true, true, true);
        emit OwnerUpdated(initializer, alice);
        rcv.transferOwnership(alice);
        vm.stopPrank();

        assertEq(rcv.owner(), alice);
    }

    function testTransferOwnershipRejectsZeroAddress() external {
        initializeReceiver();
        vm.startPrank(initializer);
        vm.expectRevert(bytes4(keccak256("ZeroAddress()")));
        rcv.transferOwnership(address(0));
        vm.stopPrank();
    }

    function testTransferOwnershipRejectsUnauthorizedCaller() external {
        initializeReceiver();
        vm.startPrank(alice);
        vm.expectRevert(bytes4(keccak256("NotOwner()")));
        rcv.transferOwnership(bob);
        vm.stopPrank();
    }

    function testClaim_IncreasedFromZeroBalance() external {
        initializeReceiver();
        donateReceiverEure();
        skipFirstEpoch();
        skipTime(1 hours);
        assertEq(rcv.dripRate(), rcv.currentEpochBalance() / epoch);
        assertEq(rcv.nextClaimEpoch(), rcv.lastClaimTimestamp() + epoch);
        uint256 claimed = claimEoa();
        assertEq(claimed, rcv.dripRate() * 1 hours);
    }

    function testClaim_endOfEpochMinus1() external {
        initializeReceiver();
        donateReceiverEure();
        skipFirstEpoch();
        skipTime(epoch - 1);
        uint256 rate = rcv.dripRate();
        assertEq(rate, rcv.currentEpochBalance() / epoch);
        assertEq(rcv.nextClaimEpoch(), rcv.lastClaimTimestamp() + epoch);
        uint256 claimed = claimEoa();
        assertEq(claimed, rcv.dripRate() * (epoch - 1));
        assertEq(rcv.dripRate(), rate);
        assertEq(rcv.nextClaimEpoch(), block.timestamp + 1);
    }

    function testClaim_endOfEpoch() external {
        initializeReceiver();
        donateReceiverEure();
        skipFirstEpoch();
        skipTime(epoch);
        uint256 rate = rcv.dripRate();
        uint256 epochBal = rcv.currentEpochBalance();
        assertEq(rate, epochBal / epoch);
        assertEq(rcv.nextClaimEpoch(), rcv.lastClaimTimestamp() + epoch);
        uint256 claimed = claimEoa();
        assertApproxEqAbs(claimed, rate * epoch, 500000);
        assertEq(claimed, epochBal);
        assertEq(rcv.currentEpochBalance(), 0);
        assertEq(rcv.dripRate(), rate);
        assertEq(rcv.nextClaimEpoch(), block.timestamp);
    }

    function testClaim_endOfEpochPlus1ButNoDeposits() external {
        initializeReceiver();
        donateReceiverEure();
        skipFirstEpoch();
        skipTime(epoch + 1);
        uint256 rate = rcv.dripRate();
        uint256 epochBal = rcv.currentEpochBalance();
        assertEq(rate, epochBal / epoch);
        assertEq(rcv.nextClaimEpoch(), rcv.lastClaimTimestamp() + epoch);
        uint256 claimed = claimEoa();
        assertEq(claimed, epochBal);
        assertEq(rcv.dripRate(), 0);
        assertEq(rcv.currentEpochBalance(), 0);
        assertEq(rcv.nextClaimEpoch(), block.timestamp - 1);
    }

    function testClaim_endOfEpochWithNewDeposits() external {
        initializeReceiver();
        donateReceiverEure();
        skipFirstEpoch();
        skipTime(epoch / 2);
        donateReceiverEure();
        skipTime(epoch / 2);
        uint256 rate = rcv.dripRate();
        uint256 epochBal = rcv.currentEpochBalance();
        assertEq(rate, epochBal / epoch);
        assertEq(rcv.nextClaimEpoch(), rcv.lastClaimTimestamp() + epoch);
        uint256 claimed = claimEoa();
        assertApproxEqAbs(claimed, rate * epoch, 500000);
        assertEq(claimed, epochBal);
        assertEq(rcv.currentEpochBalance(), 0);
        assertEq(rcv.dripRate(), rate);
        assertEq(rcv.nextClaimEpoch(), block.timestamp);
    }

    function testClaim_pastEndOfEpochWithNewDeposits() external {
        initializeReceiver();
        donateReceiverEure();
        skipFirstEpoch();
        skipTime(epoch / 2);
        donateReceiverEure();
        donateReceiverEure();
        uint256 rate = rcv.dripRate();
        uint256 balance = rcv.currentEpochBalance();
        assertEq(rate, balance / epoch);
        assertEq(rcv.nextClaimEpoch(), rcv.lastClaimTimestamp() + epoch);
        uint256 claimed = claimEoa();
        assertApproxEqAbs(claimed, rcv.dripRate() * (epoch / 2), 500000);
        skipTime(epoch);
        uint256 balance1 = rcv.currentEpochBalance();
        uint256 claimed1 = claimEoa();
        assertEq(claimed1, balance1);
        assertEq(claimed1, balance - claimed);
        assertEq(rcv.dripRate(), rcv.currentEpochBalance() / epoch);
        assertEq(rcv.nextClaimEpoch(), block.timestamp + epoch);
    }

    /*//////////////////////////////////////////////////////////////
                        BOT E2E TEST
    //////////////////////////////////////////////////////////////*/

    function testBotDepositE2E() external {
        initializeReceiver();

        // Alice deposits EURe into the vault directly.
        vm.startPrank(alice, alice);
        eure.approve(address(sEURe), 50e18);
        sEURe.deposit(50e18, alice);
        vm.stopPrank();

        uint256 initialSharePrice = sEURe.convertToAssets(1e18);

        // Skip first epoch
        skipFirstEpoch();

        // Bot deposits yield (simulating Monerium bot)
        deal(address(eure), address(this), 5000e18);
        assertTrue(eure.transfer(address(rcv), 5000e18));

        // Skip into new epoch so yield gets incorporated
        skipTime(epoch + 1);

        // First interaction after drain sets up new epoch (claims 0, but configures dripRate)
        vm.startPrank(bob, bob);
        eure.approve(address(sEURe), 2e18);
        sEURe.deposit(1e18, bob);
        vm.stopPrank();

        // dripRate should now be set for the new epoch
        assertGt(rcv.dripRate(), 0);
        assertEq(rcv.currentEpochBalance(), 5000e18);

        // Skip some time so yield drips
        skipTime(1 hours);

        // Second interaction triggers actual yield drip to vault
        vm.startPrank(bob, bob);
        sEURe.deposit(1e18, bob);
        vm.stopPrank();

        uint256 newSharePrice = sEURe.convertToAssets(1e18);
        assertGt(newSharePrice, initialSharePrice);
    }

    /*//////////////////////////////////////////////////////////////
                        VAULT APY & EDGE COVERAGE
    //////////////////////////////////////////////////////////////*/

    function testVaultAPY_notInitialized() public {
        InterestDispatcher freshImplementation = new InterestDispatcher();
        InterestDispatcher fresh = InterestDispatcher(address(new ERC1967Proxy(address(freshImplementation), "")));
        assertEq(fresh.vaultAPY(), 0);
    }

    function testVaultAPY_zeroDripRate() public {
        initializeReceiver();
        donateReceiverEure();
        skipFirstEpoch();
        skipTime(rcv.epochLength() + 1);
        vm.startPrank(bob, bob);
        rcv.claim();
        vm.stopPrank();
        assertEq(rcv.dripRate(), 0);
        assertEq(rcv.vaultAPY(), 0);
    }

    function testVaultAPY_zeroDeposits() public {
        initializeReceiver();
        assertEq(sEURe.totalAssets(), 0);
        assertEq(rcv.vaultAPY(), 0);
    }

    function testVaultAPY_happyPath() public {
        initializeReceiver();
        vm.startPrank(alice);
        eure.approve(address(sEURe), 50e18);
        sEURe.deposit(50e18, alice);
        vm.stopPrank();
        uint256 deposits = sEURe.totalAssets();
        assertGt(deposits, 0);
        uint256 drip = rcv.dripRate();
        uint256 expected = (1 ether * (drip * 365 days)) / deposits;
        assertEq(rcv.vaultAPY(), expected);
    }

    function testVaultAPY_receiverDonationOnlyAffectsNextEpochAndAccruesToHolders() public {
        initializeReceiver();

        vm.startPrank(alice);
        eure.approve(address(sEURe), 10e18);
        sEURe.deposit(10e18, alice);
        vm.stopPrank();

        vm.startPrank(bob);
        eure.approve(address(sEURe), 10e18);
        sEURe.deposit(10e18, bob);
        vm.stopPrank();

        uint256 aliceShares = sEURe.balanceOf(alice);
        uint256 bobShares = sEURe.balanceOf(bob);
        uint256 aliceAssetsBefore = sEURe.previewRedeem(aliceShares);
        uint256 bobAssetsBefore = sEURe.previewRedeem(bobShares);
        uint256 apyBeforeDonation = rcv.vaultAPY();

        vm.startPrank(bob);
        assertTrue(eure.transfer(address(rcv), 3000e18));
        vm.stopPrank();

        assertEq(rcv.vaultAPY(), apyBeforeDonation);

        teleport(rcv.nextClaimEpoch() + 1);
        claimEoa();

        assertGt(rcv.vaultAPY(), 0);
        assertEq(rcv.currentEpochBalance(), 3000e18);
        assertGt(sEURe.previewRedeem(aliceShares), aliceAssetsBefore);
        assertGt(sEURe.previewRedeem(bobShares), bobAssetsBefore);
        assertEq(sEURe.balanceOf(alice), aliceShares);
        assertEq(sEURe.balanceOf(bob), bobShares);
    }

    function testClaim_sameBlockSecondCallReturnsZero() public {
        initializeReceiver();
        skipTime(1 hours);
        vm.startPrank(bob, bob);
        uint256 c1 = rcv.claim();
        assertGt(c1, 0);
        assertEq(rcv.claim(), 0);
        vm.stopPrank();
    }

    function testClaim_zeroReceiverBalance() public {
        initializeReceiver();
        deal(address(eure), address(rcv), 0);
        vm.startPrank(bob, bob);
        assertEq(rcv.claim(), 0);
        vm.stopPrank();
    }

    /// Drip accrual can exceed book `currentEpochBalance` within an epoch when the book was
    /// drained by a prior partial claim but `dripRate` is unchanged — exercise the cap branch.
    function testClaim_calculateClaim_capsWhenLinearAccrualExceedsBook() public {
        vm.startPrank(initializer);
        uint256 el = rcv.epochLength();
        deal(address(eure), address(rcv), el * 1 ether);
        rcv.initialize(address(sEURe), initializer);
        vm.stopPrank();

        skipTime(el - 1);
        vm.startPrank(bob, bob);
        uint256 c1 = rcv.claim();
        assertEq(c1, (el - 1) * 1 ether);
        vm.stopPrank();

        skipTime(2);
        vm.startPrank(bob, bob);
        uint256 c2 = rcv.claim();
        assertEq(c2, 1 ether);
        vm.stopPrank();
    }

    function testPreviewClaimable_notInitialized() public {
        InterestDispatcher freshImpl = new InterestDispatcher();
        InterestDispatcher fresh = InterestDispatcher(address(new ERC1967Proxy(address(freshImpl), "")));
        assertEq(fresh.previewClaimable(), 0);
    }

    function testPreviewClaimable_sameBlockReturnsZero() public {
        initializeReceiver();
        claimEoa();
        assertEq(rcv.previewClaimable(), 0);
    }

    function testPreviewClaimable_zeroBalance() public {
        initializeReceiver();
        deal(address(eure), address(rcv), 0);
        skipTime(1 hours);
        assertEq(rcv.previewClaimable(), 0);
    }

    function testPreviewClaimable_happyPath() public {
        initializeReceiver();
        skipTime(1 hours);
        uint256 expected = rcv.dripRate() * 1 hours;
        uint256 claimable = rcv.previewClaimable();
        assertEq(claimable, expected);
        assertGt(claimable, 0);
    }

    function testClaim_capsClaimableToActualBalanceWhenDrainedMidEpoch() public {
        initializeReceiver();
        skipTime(1 days);
        // Drain most EURe from the receiver so claimable > actual balance
        uint256 rcvBal = eure.balanceOf(address(rcv));
        vm.startPrank(address(rcv));
        bool success = eure.transfer(alice, rcvBal - 1 ether);
        require(success);
        vm.stopPrank();
        assertLt(eure.balanceOf(address(rcv)), rcv.dripRate() * 1 days);
        uint256 claimed = claimEoa();
        assertEq(claimed, 1 ether);
    }
}
