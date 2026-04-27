# Chain Analysis

## Enabler Enumeration

For TR-1 (balance < claimable underflow):

| # | Path to State S (balance < currentEpochBalance) | Actor Category | Existing Finding Covers It? | New Finding? |
|---|-------------------------------------------------|----------------|-----------------------------|-------------|
| 1 | EURe issuer exercises burn/seize on receiver balance | External event (trusted actor) | YES — TR-1 | N/A |
| 2 | EURe blocklist prevents transfer but doesn't reduce balance | External event | NO — blocklist causes revert not underflow | Not a new finding (no underflow) |
| 3 | A reentrancy in safeTransfer somehow reduces balance | External attacker | NO — EURe is ERC20, no hooks | Not reachable |
| 4 | A bug in EURe's balanceOf reporting | External event | NO — assumes broken token | Not a new finding (assumes broken token) |
| 5 | Donation followed by claim + re-donation in complex sequence | User action sequence | NO — donations increase balance, not decrease | Not a new finding |

**Conclusion**: TR-1 is only reachable via Path 1 (trusted actor). All other paths are not reachable. With [ASSUMPTION-DEP: TRUSTED-ACTOR] tag, severity is effectively INFO for practical purposes.

## Chain Summary
No chain combinations identified — only one non-trivial finding (TR-1) and it has no enabler findings that could chain with it.

## Convergence
All findings analyzed. No additional iterations needed.
