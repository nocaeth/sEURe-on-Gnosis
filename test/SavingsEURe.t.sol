// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {Vm} from "forge-std/Vm.sol";
import {console} from "forge-std/console.sol";
import {SetupTest} from "./Setup.t.sol";
import {MockMultisig} from "./Mocks/MockMultisig.sol";
import {ISavingsEURe} from "src/interfaces/ISavingsEURe.sol";

contract SavingsEUReTest is SetupTest {
    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    bytes32 constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    uint256 constant SECP256K1_N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;

    function testMetadata() public view {
        assertEq(address(rcv), address(rcv));
        assertEq(sEURe.name(), "Savings EURe");
        assertEq(sEURe.symbol(), "sEURe");
        assertEq(sEURe.asset(), address(eure));
    }

    /*//////////////////////////////////////////////////////////////
                        CORE LOGIC
    //////////////////////////////////////////////////////////////*/

    function testTransferShares() public {
        uint256 assets = 1e18;
        address sender = alice;
        vm.startPrank(sender);
        eure.approve(address(sEURe), assets);
        uint256 shares = sEURe.deposit(assets, sender);
        assertGe(sEURe.balanceOf(sender), shares);
        assertGt(shares, 0);
        uint256 initialBalanceA = sEURe.balanceOf(sender);
        uint256 initialBalanceB = sEURe.balanceOf(bob);

        vm.expectEmit();
        emit Transfer(sender, bob, shares);
        assertTrue(sEURe.transfer(bob, shares));

        assertEq(sEURe.balanceOf(sender), initialBalanceA - shares);
        assertEq(sEURe.balanceOf(bob), initialBalanceB + shares);
        vm.stopPrank();
    }

    function testDeposit() public {
        uint256 assets = 1e18;
        address receiver = alice;
        vm.startPrank(receiver);
        uint256 initialBalance = eure.balanceOf(receiver);
        uint256 initialShares = sEURe.balanceOf(receiver);
        eure.approve(address(sEURe), initialBalance);
        vm.expectEmit();
        emit Transfer(address(0), receiver, sEURe.previewDeposit(assets));
        uint256 shares = sEURe.deposit(assets, receiver);
        console.log("totalAssets: %e", sEURe.totalAssets());
        console.log("previewDeposit: %e", sEURe.previewDeposit(assets));
        console.log("previewRedeem: %e", sEURe.previewRedeem(sEURe.balanceOf(receiver)));
        console.log("maxWithdraw: %e", sEURe.maxWithdraw(receiver));
        assertEq(sEURe.balanceOf(receiver), shares + initialShares);
        assertGe(sEURe.totalAssets(), sEURe.maxWithdraw(receiver));
        assertEq(eure.balanceOf(receiver), initialBalance - assets);
        vm.stopPrank();
    }

    function testFuzzDeposit(uint256 assets) public {
        address receiver = alice;

        uint256 initialAssets = eure.balanceOf(receiver);
        uint256 initialShares = sEURe.balanceOf(receiver);
        vm.assume(assets <= eure.balanceOf(alice));

        vm.startPrank(alice);

        eure.approve(address(sEURe), initialAssets);
        uint256 shares = sEURe.deposit(assets, receiver);

        assertEq(sEURe.balanceOf(receiver), initialShares + shares);
        assertGe(sEURe.totalAssets(), sEURe.maxWithdraw(receiver));
        assertEq(eure.balanceOf(receiver), initialAssets - assets);

        vm.stopPrank();
    }

    function testFuzzMint(uint256 shares) public {
        address receiver = alice;

        uint256 initialAssets = eure.balanceOf(receiver);
        uint256 initialShares = sEURe.balanceOf(receiver);

        vm.assume(shares <= sEURe.convertToShares(eure.balanceOf(alice)));

        vm.startPrank(alice);
        eure.approve(address(sEURe), initialAssets);
        vm.expectEmit();
        emit Transfer(address(0), receiver, shares);
        uint256 assets = sEURe.mint(shares, receiver);

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

        vm.expectEmit();
        emit Transfer(receiver, address(0), sEURe.previewWithdraw(assets));
        uint256 shares = sEURe.withdraw(assets, receiver, owner);

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
        vm.expectEmit();
        emit Transfer(receiver, address(0), shares);
        uint256 assets = sEURe.redeem(shares, receiver, owner);
        console.log("assets: %e %e", initialAssets, assets);
        assertEq(sEURe.balanceOf(owner), initialShares - shares);
        assertGe(sEURe.totalAssets(), sEURe.maxWithdraw(receiver));
        assertEq(eure.balanceOf(receiver), initialAssets + assets);

        vm.stopPrank();
    }

    /*//////////////////////////////////////////////////////////////
                        SPECIAL STATES
    //////////////////////////////////////////////////////////////*/

    function testMintAndWithdraw(uint256 shares) public {
        uint256 initialAssets = eure.balanceOf(alice);
        vm.assume(shares < sEURe.convertToShares(initialAssets));

        vm.startPrank(alice);

        eure.approve(address(sEURe), initialAssets);
        uint256 assets = sEURe.mint(shares, alice);
        uint256 maxW = sEURe.maxWithdraw(alice);
        uint256 toWithdraw = assets > maxW ? maxW : assets;
        uint256 shares2 = sEURe.withdraw(toWithdraw, alice, alice);
        assertGe(shares2, 0);

        vm.stopPrank();
    }

    function testZeroSupplyResidualAssetsAreDilutedByVirtualOffset() public {
        uint256 residual = 1e18;
        uint256 depositAssets = 1e18;

        deal(address(eure), address(sEURe), residual);
        assertEq(sEURe.totalSupply(), 0);
        assertEq(sEURe.totalAssets(), residual);

        uint256 previewedShares = sEURe.previewDeposit(depositAssets);
        assertGt(previewedShares, 0);
        assertLt(previewedShares, depositAssets * 10 ** sEURe.decimals() / 1e18);

        vm.startPrank(bob);
        eure.approve(address(sEURe), depositAssets);
        uint256 shares = sEURe.deposit(depositAssets, bob);
        vm.stopPrank();

        uint256 immediateRedeemable = sEURe.previewRedeem(shares);
        assertEq(shares, previewedShares);
        assertLe(immediateRedeemable, depositAssets);
        assertLt(immediateRedeemable, residual + depositAssets);
    }

    // checks that all deposit functions from deposit and mint return the same shares given equivalent inputs.
    function test_CompareAllTypes_Deposits() public {
        uint256 assets = 1e18;

        vm.startPrank(alice);
        uint256 eureBalance = eure.balanceOf(alice);

        assertGe(eureBalance, assets * 2);

        eure.approve(address(sEURe), eureBalance);
        uint256 sharesErc20A = sEURe.deposit(assets, alice);
        uint256 assetsErc20A = sEURe.mint(sharesErc20A, alice);
        assertEq(assetsErc20A, assets);
        vm.stopPrank();
        vm.startPrank(bob);
        eureBalance = eure.balanceOf(bob);
        assertGe(eureBalance, assets * 2);
        eure.approve(address(sEURe), eureBalance);
        uint256 sharesErc20B = sEURe.deposit(assets, bob);
        uint256 assetsErc20B = sEURe.mint(sharesErc20B, bob);
        assertEq(assetsErc20B, assets);
        vm.stopPrank();
        assertGt(sharesErc20A, 100);
    }

    // checks that all withdraw functions from withdraw and redeem return the same shares given equivalent inputs.
    function test_CompareAllTypes_Withdrawals() public {
        uint256 assets = 1e18;

        vm.startPrank(alice);
        uint256 initialSharesA = sEURe.balanceOf(alice);
        eure.approve(address(sEURe), assets * 2);
        uint256 sharesDepositedA = sEURe.deposit(assets * 2, alice);
        uint256 sharesErc20A = sEURe.withdraw(assets, alice, alice);
        uint256 assetsErc20A = sEURe.redeem(sharesErc20A, alice, alice);
        assertEq(assetsErc20A, assets);
        vm.stopPrank();

        vm.startPrank(bob);
        eure.approve(address(sEURe), assets * 2);
        uint256 sharesDepositedB = sEURe.deposit(assets * 2, bob);
        uint256 sharesErc20B = sEURe.withdraw(assets, bob, bob);
        uint256 assetsErc20B = sEURe.redeem(sharesErc20A, bob, bob);
        assertEq(assetsErc20B, assets);
        vm.stopPrank();
        assertEq(sEURe.balanceOf(alice), initialSharesA);
        assertEq(sharesDepositedA, sharesDepositedB);
        assertEq(sharesErc20A, sharesErc20B);
        assertGt(sharesErc20A, 100);
    }

    /*//////////////////////////////////////////////////////////////
                        PERMIT LOGIC
    //////////////////////////////////////////////////////////////*/

    function testPermit() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    sEURe.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, owner, address(0xCAFE), 1e18, 0, block.timestamp))
                )
            )
        );

        sEURe.permit(owner, address(0xCAFE), 1e18, block.timestamp, v, r, s);

        assertEq(sEURe.allowance(owner, address(0xCAFE)), 1e18);
        assertEq(sEURe.nonces(owner), 1);
    }

    function testPermitEmitsSingleApproval() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);
        address spender = address(0xCAFE);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    sEURe.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, 1e18, 0, block.timestamp))
                )
            )
        );

        vm.recordLogs();
        sEURe.permit(owner, spender, 1e18, block.timestamp, v, r, s);

        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32 approvalTopic = keccak256("Approval(address,address,uint256)");
        uint256 approvalCount;
        for (uint256 i; i < entries.length; i++) {
            if (entries[i].topics[0] == approvalTopic) {
                approvalCount++;
            }
        }
        assertEq(approvalCount, 1);
    }

    function testPermitRejectsHighSSignature() public {
        uint256 privateKey = 0xBEEF;
        address owner = vm.addr(privateKey);
        address spender = address(0xCAFE);

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            privateKey,
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    sEURe.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, 1e18, 0, block.timestamp))
                )
            )
        );

        uint8 malleableV = v == 27 ? 28 : 27;
        bytes32 malleableS = bytes32(SECP256K1_N - uint256(s));

        vm.expectRevert(ISavingsEURe.InvalidPermit.selector);
        sEURe.permit(owner, spender, 1e18, block.timestamp, malleableV, r, malleableS);
    }

    function testPermitRejectsExpiredDeadline() public {
        vm.expectRevert(ISavingsEURe.PermitExpired.selector);
        sEURe.permit(alice, address(0xCAFE), 1e18, block.timestamp - 1, bytes(""));
    }

    function testPermitRejectsZeroOwner() public {
        vm.expectRevert(ISavingsEURe.InvalidOwner.selector);
        sEURe.permit(address(0), address(0xCAFE), 1e18, block.timestamp, bytes(""));
    }

    function testPermitContract() public {
        uint256 privateKey1 = 0xBEEF;
        address signer1 = vm.addr(privateKey1);
        uint256 privateKey2 = 0xBEEE;
        address signer2 = vm.addr(privateKey2);

        address mockMultisig = address(new MockMultisig(signer1, signer2));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(privateKey1),
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    sEURe.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, mockMultisig, address(0xCAFE), 1e18, 0, block.timestamp))
                )
            )
        );

        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(
            uint256(privateKey2),
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    sEURe.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, mockMultisig, address(0xCAFE), 1e18, 0, block.timestamp))
                )
            )
        );

        bytes memory signature = abi.encode(r, s, bytes32(uint256(v) << 248), r2, s2, bytes32(uint256(v2) << 248));

        sEURe.permit(mockMultisig, address(0xCAFE), 1e18, block.timestamp, signature);

        assertEq(sEURe.allowance(mockMultisig, address(0xCAFE)), 1e18);
        assertEq(sEURe.nonces(mockMultisig), 1);
    }

    function testPermitContractInvalidSignature() public {
        uint256 privateKey1 = 0xBEEF;
        address signer1 = vm.addr(privateKey1);
        uint256 privateKey2 = 0xBEEE;
        address signer2 = vm.addr(privateKey2);

        address mockMultisig = address(new MockMultisig(signer1, signer2));

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(
            uint256(privateKey1),
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    sEURe.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, mockMultisig, address(0xCAFE), 1e18, 0, block.timestamp))
                )
            )
        );

        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(
            uint256(0xCEEE),
            keccak256(
                abi.encodePacked(
                    "\x19\x01",
                    sEURe.DOMAIN_SEPARATOR(),
                    keccak256(abi.encode(PERMIT_TYPEHASH, mockMultisig, address(0xCAFE), 1e18, 0, block.timestamp))
                )
            )
        );

        bytes memory signature = abi.encode(r, s, bytes32(uint256(v) << 248), r2, s2, bytes32(uint256(v2) << 248));

        vm.expectRevert(ISavingsEURe.InvalidPermit.selector);
        sEURe.permit(mockMultisig, address(0xCAFE), 1e18, block.timestamp, signature);
    }
}
