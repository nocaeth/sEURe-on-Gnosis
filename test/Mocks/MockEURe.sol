// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.19;

import "openzeppelin/token/ERC20/ERC20.sol";

contract MockEURe is ERC20 {
    constructor() ERC20("Monerium EUR emoney", "EURE") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}
