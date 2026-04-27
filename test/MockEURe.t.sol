// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {Test} from "forge-std/Test.sol";
import {MockEURe} from "test/Mocks/MockEURe.sol";

contract MockEUReTest is Test {
    function testMintIncreasesBalance() public {
        MockEURe t = new MockEURe();
        address u = address(0xBEEF);
        t.mint(u, 1e18);
        assertEq(t.balanceOf(u), 1e18);
    }
}
