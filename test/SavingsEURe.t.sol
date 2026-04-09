// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "./Setup.t.sol";
import "./Mocks/MockMultisig.sol";

contract SavingsEUReTest is SetupTest {
    event Transfer(address indexed from, address indexed to, uint256 value);

    bytes32 constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function testMetadata() public {
        assertEq(address(rcv), address(rcv));
        assertEq(address(sEURe.eure()), address(eure));
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
        uint256 initialBalance_a = sEURe.balanceOf(sender);
        uint256 initialBalance_b = sEURe.balanceOf(bob);

        vm.expectEmit();
        emit Transfer(sender, bob, shares);
        sEURe.transfer(bob, shares);

        assertEq(sEURe.balanceOf(sender), initialBalance_a - shares);
        assertEq(sEURe.balanceOf(bob), initialBalance_b + shares);
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

    // checks that all deposit functions from deposit and mint return the same shares given equivalent inputs.
    function test_CompareAllTypes_Deposits() public {
        uint256 assets = 1e18;

        vm.startPrank(alice);
        uint256 eureBalance = eure.balanceOf(alice);

        assertGe(eureBalance, assets * 2);

        eure.approve(address(sEURe), eureBalance);
        uint256 sharesERC20_a = sEURe.deposit(assets, alice);
        uint256 assetsERC20_a = sEURe.mint(sharesERC20_a, alice);
        assertEq(assetsERC20_a, assets);
        vm.stopPrank();
        vm.startPrank(bob);
        eureBalance = eure.balanceOf(bob);
        assertGe(eureBalance, assets * 2);
        eure.approve(address(sEURe), eureBalance);
        uint256 sharesERC20_b = sEURe.deposit(assets, bob);
        uint256 assetsERC20_b = sEURe.mint(sharesERC20_b, bob);
        assertEq(assetsERC20_b, assets);
        vm.stopPrank();
        assertGt(sharesERC20_a, 100);
    }

    // checks that all withdraw functions from withdraw and redeem return the same shares given equivalent inputs.
    function test_CompareAllTypes_Withdrawals() public {
        uint256 assets = 1e18;

        vm.startPrank(alice);
        uint256 initialShares_a = sEURe.balanceOf(alice);
        eure.approve(address(sEURe), assets * 2);
        uint256 sharesDeposited_a = sEURe.deposit(assets * 2, alice);
        uint256 sharesERC20_a = sEURe.withdraw(assets, alice, alice);
        uint256 assetsERC20_a = sEURe.redeem(sharesERC20_a, alice, alice);
        assertEq(assetsERC20_a, assets);
        vm.stopPrank();

        vm.startPrank(bob);
        eure.approve(address(sEURe), assets * 2);
        uint256 sharesDeposited_b = sEURe.deposit(assets * 2, bob);
        uint256 sharesERC20_b = sEURe.withdraw(assets, bob, bob);
        uint256 assetsERC20_b = sEURe.redeem(sharesERC20_a, bob, bob);
        assertEq(assetsERC20_b, assets);
        vm.stopPrank();
        assertEq(sEURe.balanceOf(alice), initialShares_a);
        assertEq(sharesDeposited_a, sharesDeposited_b);
        assertEq(sharesERC20_a, sharesERC20_b);
        assertGt(sharesERC20_a, 100);
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

        vm.expectRevert("SavingsEURe/invalid-permit");
        sEURe.permit(mockMultisig, address(0xCAFE), 1e18, block.timestamp, signature);
    }
}
