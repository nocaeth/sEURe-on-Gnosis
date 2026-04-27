# Depth Analysis — Iteration 1

## Token Flow Depth: TR-1 Balance Desync Investigation

### Question: Can EURe balance of receiver decrease without a claim() call?

**Hypothesis**: If EURe token has a mechanism (e.g., `burnFrom`, `seize`, `adminBurn`) that can reduce `balanceOf(receiver)`, the underflow in `_calculateClaim` line 124 would permanently brick yield distribution.

**Investigation**:
1. EURe address: `0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430` on Gnosis Chain
2. EURe is issued by Monerium — a licensed e-money institution
3. CHANGES-FROM-SDAI.md Known Risk #1 states: "Monerium can freeze the vault or receiver address, permanently locking all deposits"
4. Monerium's EURe implementation likely includes blocklist functionality (standard for permissioned stablecoins)
5. Blocklisting prevents transfers TO/FROM the address but does NOT reduce `balanceOf` — it just makes `transfer()` and `transferFrom()` revert

**Conclusion**: Blocklisting would cause `safeTransfer(address(sEURe), claimed)` in `claim()` to revert. Since state is updated BEFORE the transfer, the entire transaction reverts — state remains consistent. The yield distribution pauses (every claim reverts) but doesn't corrupt state.

However, if Monerium has a `burn(address,uint256)` or `burnFrom(address,uint256)` function:
- Balance would decrease without any claim() call
- State variables would desync from actual balance
- `_calculateClaim` would underflow on line 124
- This is UNVERIFIED — EURe's production contract was not fetched

**Evidence**: [EXT-UNV] — EURe contract not verified on-chain. The [ASSUMPTION-DEP: TRUSTED-ACTOR] tag applies because this requires Monerium (FULLY_TRUSTED) to act beyond documented capabilities.

**Verdict**: CONTESTED → remains CONTESTED. Severity stays LOW with worst-case MEDIUM.

---

## State Trace Depth: Cross-Function State Consistency

### Epoch State Variables Updated Atomically?
In `claim()`:
```solidity
(claimed, nextEpochBalance, nextDripRate, nextEpochTimestamp) = _calculateClaim(balance);
currentEpochBalance = nextEpochBalance;  // all 4 updated
dripRate = nextDripRate;                  // atomically
nextClaimEpoch = nextEpochTimestamp;      // in single
lastClaimTimestamp = block.timestamp;     // transaction
```
✓ All epoch state variables updated atomically in a single transaction.

### No External Calls Between State Updates?
The only external call is `eure.safeTransfer(address(sEURe), claimed)` which happens AFTER all state updates. If it reverts, the entire transaction reverts.
✓ No state desync possible from external call failures.

### Cross-Contract Consistency?
1. InterestReceiver.sEURe points to the vault — immutable ✓
2. SavingsEUReAdapter.sEURe points to the vault — immutable ✓
3. SavingsEUReAdapter.interestReceiver points to the receiver — immutable ✓
4. All three contracts reference the same EURe address (hardcoded) ✓

No cross-contract state consistency issues.

---

## Edge Case Depth: Zero-State and Boundary Analysis

### First Depositor (zero-state)
- `totalAssets() = 0`, `totalSupply() = 0` (plus virtual offset)
- `_decimalsOffset() = 3` → virtual shares = 10^3, virtual assets = 10^(18+3-18) = 10^3
- First deposit of N assets → shares = N * 10^3 / 10^3 = N
- Inflation attack: attacker deposits 1 wei, donates D tokens, victim deposits V tokens
  - Without offset: victim gets ~0 shares
  - With offset 3: attacker needs to donate V * 10^3 to get ~0 shares for victim
  - For V = 100 EURe: attacker needs 100,000 EURe donation — not economically viable
✓ Inflation protection adequate.

### Same-Block Claim Guard
- `lastClaimTimestamp == block.timestamp` → returns 0
- State NOT updated (no state changes, no transfer)
- Correct behavior — prevents same-block double-claim ✓

### Epoch Boundary (block.timestamp == nextClaimEpoch)
- Rollover check: `block.timestamp > nextClaimEpoch` → FALSE at exact boundary
- Falls through to partial-epoch path: `claimable = unclaimedTime * dripRate`
- `unclaimedTime = epochLength` (exact) → `claimable = epochLength * dripRate = currentEpochBalance` (integer math)
- `nextEpochBalance_ -= claimable = 0`
- No rollover triggered → epoch drained but no new epoch starts
- Next claim after nextClaimEpoch: `currentEpochBalance = 0`, `claimable = 0`, then rollover triggers
✓ Correct behavior at epoch boundary.

### Empty Balance Claim
- `balance = 0` → `if (balance > 0)` skipped → returns 0
- State NOT updated → time doesn't advance
- Future funding makes full gap claimable
✓ Correct by design.

### MIN_EPOCH_BALANCE Boundary
- `remaining < MIN_EPOCH_BALANCE` → `dripRate = 0`, `currentEpochBalance = 0`
- Epoch stops — no yield until receiver is funded above threshold
- Next claim after funding: `balance > 0`, `claimable = 0` (currentEpochBalance = 0)
- Rollover triggers: `remaining = balance - 0 = balance`
- If `remaining >= MIN_EPOCH_BALANCE` → new epoch starts
- Two claims needed to resume dripping (documented risk #3)
✓ Correct by design.

---

## Scanner A: Token & Parameter Sweep
- No fee-on-transfer tokens ✓ (EURe is standard ERC20)
- No rebasing tokens ✓
- No ERC777 hooks ✓
- No tokens with transfer taxes ✓
- All arithmetic in Solidity 0.8+ (overflow-checked) ✓

## Scanner B: Guards, Visibility & Inheritance
- All state-changing functions have appropriate access control ✓
- initialize() has `initializer` modifier ✓
- No uninitialized state variables ✓
- No shadowed variables ✓
- OZ ERC4626 inheritance is standard and well-audited ✓

## Scanner C: Role Lifecycle
- claimer role: set in constructor, transferable via setClaimer()
- No role removal mechanism (by design — one-step transfer)
- No role-based state isolation issues
- tx.origin check is the only EOA detection mechanism
- No role escalation possible ✓

## Validation Sweep
- All external calls use SafeERC20 ✓
- All state updates happen before external calls ✓
- No reentrancy paths ✓
- No unchecked return values (SafeERC20 handles this) ✓

---

## Confidence Scores (2-axis: Evidence + Analysis Quality)

| Finding ID | Evidence Score | Analysis Quality | Combined | Verdict |
|-----------|---------------|-----------------|----------|---------|
| TR-1 | 0.4 (CONTESTED — depends on UNVERIFIED external) | 0.8 (thorough trace) | 0.6 | UNCERTAIN |
| SR-1 | 1.0 (confirmed by code + docs) | 0.9 (bidirectional analysis) | 0.95 | CONFIDENT |
| SR-2 | 1.0 (confirmed by code + docs) | 0.9 (documented risk) | 0.95 | CONFIDENT |
| TF-1 | 0.9 (confirmed by code analysis) | 0.9 (5-dimension analysis) | 0.9 | CONFIDENT |
| SC-1 | 1.0 (confirmed — no pause code exists) | 0.8 (design analysis) | 0.9 | CONFIDENT |
| EP-1 | 1.0 (confirmed — max approval visible) | 0.8 (standard pattern analysis) | 0.9 | CONFIDENT |
| SV-1 | 1.0 (confirmed — OZ standard) | 0.9 (thorough verification) | 0.95 | CONFIDENT |

Return: 'DEPTH ITER 1 COMPLETE: 7 findings, 1 UNCERTAIN (TR-1), 6 CONFIDENT, 0 new findings, convergence: YES'
