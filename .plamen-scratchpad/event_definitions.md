# Event Definitions

## IInterestReceiver
- `event Claimed(uint256 indexed amount)` — emitted when EURe yield transferred to vault
- `event Initialized(uint256 indexed initialBalance, uint256 dripRate, uint256 nextClaimEpoch)` — emitted on first epoch setup
- `event ClaimerUpdated(address indexed previousClaimer, address indexed newClaimer)` — emitted on claimer transfer

## SavingsEURe (inherited from OZ ERC20/ERC4626)
- `event Approval(address indexed owner, address indexed spender, uint256 value)` — from ERC20
- `event Transfer(address indexed from, address indexed to, uint256 value)` — from ERC20
- `event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares)` — from ERC4626
- `event Withdraw(address indexed sender, address indexed receiver, address indexed owner, uint256 assets, uint256 shares)` — from ERC4626

Total events: 7 (3 custom + 4 inherited)
