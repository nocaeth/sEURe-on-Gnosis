# Constraint Variables

| Variable | Contract | Type | Constraint | Enforcement |
|----------|----------|------|-----------|-------------|
| MIN_EPOCH_BALANCE | InterestReceiver | constant | 100 ether | Used in initialize() and epoch renewal |
| epochLength | InterestReceiver | constant | 5 days | Used in drip calculation and epoch rollover |
| dripRate | InterestReceiver | mutable | set = balance / epochLength | No upper bound — depends on funded balance |
| currentEpochBalance | InterestReceiver | mutable | decremented per claim | Can reach 0 (full drain) |
| nextClaimEpoch | InterestReceiver | mutable | set = block.timestamp + epochLength | No staleness guard |
| lastClaimTimestamp | InterestReceiver | mutable | updated on claim | Same-block guard (returns 0) |
| claimer | InterestReceiver | mutable | non-zero check on set | One-step transfer, no pending state |
| _decimalsOffset | SavingsEURe | constant | 3 | Virtual share multiplier for inflation protection |
| EURe address | All contracts | hardcoded | 0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430 | Immutable in all 3 contracts |
