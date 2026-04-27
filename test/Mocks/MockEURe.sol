// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";

contract MockEURe is ERC20 {
    error TransferReverted(address from, address to, uint256 value);

    mapping(address => bool) public revertingSender;

    constructor() ERC20("Monerium EUR emoney", "EURE") {}

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    function setRevertingSender(address sender, bool shouldRevert) external {
        revertingSender[sender] = shouldRevert;
    }

    function _update(address from, address to, uint256 value) internal override {
        if (revertingSender[from]) revert TransferReverted(from, to, value);
        super._update(from, to, value);
    }
}
