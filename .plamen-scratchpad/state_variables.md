# State Variables

## InterestReceiver
| Variable | Type | Visibility | Mutability | Description |
|----------|------|-----------|------------|-------------|
| `MIN_EPOCH_BALANCE` | uint256 | public constant | constant | 100 ether |
| `epochLength` | uint256 | public constant | constant | 5 days |
| `eure` | IERC20 | public immutable | immutable | 0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430 |
| `sEURe` | ISavingsEURe | public immutable | immutable | set in constructor |
| `claimer` | address | public | mutable | initialized to msg.sender, transferable via setClaimer |
| `dripRate` | uint256 | public | mutable | EURe/second, set during claim epoch transitions |
| `nextClaimEpoch` | uint256 | public | mutable | timestamp when current epoch can roll over |
| `currentEpochBalance` | uint256 | public | mutable | remaining EURe in current epoch |
| `lastClaimTimestamp` | uint256 | public | mutable | timestamp of last successful claim |

## SavingsEURe
| Variable | Type | Visibility | Mutability | Description |
|----------|------|-----------|------------|-------------|
| `PERMIT_TYPEHASH` | bytes32 | public constant | constant | EIP712 permit typehash |
| (ERC4626 inherited: `_asset`, totalSupply, etc.) | | | | |

## SavingsEUReAdapter
| Variable | Type | Visibility | Mutability | Description |
|----------|------|-----------|------------|-------------|
| `interestReceiver` | IInterestReceiver | public immutable | immutable | set in constructor |
| `sEURe` | ISavingsEURe | public immutable | immutable | set in constructor |
| `eure` | IERC20 | public immutable | immutable | 0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430 |
