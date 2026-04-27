# Emit List

## Custom Events
- `Claimed(uint256 indexed amount)` — InterestReceiver.claim()
- `Initialized(uint256 indexed initialBalance, uint256 dripRate, uint256 nextClaimEpoch)` — InterestReceiver.initialize()
- `ClaimerUpdated(address indexed previousClaimer, address indexed newClaimer)` — InterestReceiver.setClaimer()

## Inherited Events (OZ)
- `Approval(address indexed owner, address indexed spender, uint256 value)` — SavingsEURe (ERC20._approve)
- `Transfer(address indexed from, address indexed to, uint256 value)` — SavingsEURe (ERC20 transfer/transferFrom)
- `Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares)` — SavingsEURe (ERC4626)
- `Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares)` — SavingsEURe (ERC4626)

Total: 7 events. No MISSING_EVENT flag — all state-changing functions emit events.
