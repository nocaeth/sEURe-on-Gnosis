// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.10;

interface ISavingsEUReAdapter {
    function deposit(uint256 assets, address receiver) external returns (uint256);
    function interestReceiver() external view returns (address);
    function mint(uint256 shares, address receiver) external returns (uint256);
    function redeem(uint256 shares, address receiver) external returns (uint256);
    function redeemAll(address receiver) external returns (uint256);
    function sEURe() external view returns (address);
    function vaultAPY() external view returns (uint256);
    function withdraw(uint256 assets, address receiver) external returns (uint256);
    function eure() external view returns (address);
}
