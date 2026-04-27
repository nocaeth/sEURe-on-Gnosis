# External Interfaces

## IERC20 (EURe — 0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430)
- `balanceOf(address)` — used by InterestReceiver._balance()
- `transfer(address,uint256)` — used in constructor (adapter approval)
- `approve(address,uint256)` — adapter max-approves vault
- `transferFrom(address,address,uint256)` — adapter pulls EURe from users (via SafeERC20)

## ISavingsEURe (ERC4626 vault)
- `deposit(uint256,address) → uint256` — deposit assets, mint shares
- `mint(uint256,address) → uint256` — mint exact shares
- `withdraw(uint256,address,address) → uint256` — withdraw assets
- `redeem(uint256,address,address) → uint256` — redeem shares
- `previewMint(uint256) → uint256` — ceiling-rounded assets needed
- `maxWithdraw(address) → uint256` — max withdrawable for owner
- `maxRedeem(address) → uint256` — max redeemable for owner
- `balanceOf(address) → uint256` — share balance
- `totalAssets() → uint256` — total EURe in vault

## IInterestReceiver
- `claim() → uint256` — claim pending yield
- `vaultAPY() → uint256` — current APY
