# Semantic Invariants — Pass 1

## Main Table
| Variable | Contract | Semantic Invariant | Write Sites | Value-Changing Functions | Potential Gaps |
|----------|----------|-------------------|-------------|------------------------|----------------|
| claimer | InterestReceiver | The address authorized to call claim() from contracts | constructor (init), setClaimer() | setClaimer() | None |
| dripRate | InterestReceiver | EURe per second to release during current epoch | initialize(), claim() (via _calculateClaim) | initialize(), claim() epoch rollover | None — only updated atomically with epoch state |
| nextClaimEpoch | InterestReceiver | Timestamp when current epoch can roll to new epoch | initialize(), claim() (via _calculateClaim) | initialize(), claim() epoch rollover | None |
| currentEpochBalance | InterestReceiver | Remaining EURe scheduled to drip in current epoch | initialize(), claim() (via _calculateClaim) | initialize(), claim() (partial/full epoch) | Tracked [TR-1]: can desync from actual balance |
| lastClaimTimestamp | InterestReceiver | Block timestamp of last successful claim state update | initialize(), claim() | claim() | Same-block guard prevents double-claim |
| PERMIT_TYPEHASH | SavingsEURe | EIP712 type hash for permit — immutable | N/A (constant) | N/A | None |
| _decimalsOffset | SavingsEURe | Virtual share multiplier for inflation protection — immutable | N/A (pure) | N/A | None |

## Mirror Variable Pairs
| Variable A | Variable B | Same Concept | Functions Writing A Only | Functions Writing B Only | Sync Gaps |
|-----------|-----------|-------------|-------------------------|-------------------------|-----------|
| currentEpochBalance | eure.balanceOf(receiver) | EURe available for dripping | claim() (sets to remaining), initialize() | External transfers (donations, burns) | YES — external transfers change B but not A. A tracks epoch allocation, B is actual balance. [TR-1] |

## Time-Weighted Accumulators
| Accumulator | Formula Pattern | Controllable Input | Time Source | Unbounded Delta? | Exposure |
|------------|----------------|-------------------|-------------|-----------------|----------|
| claimable (partial epoch) | unclaimedTime * dripRate | dripRate (set from balance), unclaimedTime (time since last claim) | block.timestamp - lastClaimTimestamp | NO — capped at epochLength (5 days) via full-epoch branch | LOW |

## Semantic Clusters
| Cluster Name | Variables | Lifecycle Functions | Full-Write Functions | Partial-Write Functions |
|-------------|-----------|-------------------|---------------------|----------------------|
| Epoch State | dripRate, currentEpochBalance, nextClaimEpoch, lastClaimTimestamp | initialize() (creates epoch), claim() (advances/transitions epoch) | initialize(), claim() epoch rollover | None — all epoch state updated atomically in claim() |
| Access Control | claimer | constructor, setClaimer() | setClaimer() | None |

## Cluster Coverage Gaps
None — all epoch state variables are updated atomically in _calculateClaim. No partial-write functions exist for the Epoch State cluster.

Return: 'DONE: 7 variables, 1 gaps, 0 conditional, 1 sync_gaps, 1 accumulation, 2 clusters'
