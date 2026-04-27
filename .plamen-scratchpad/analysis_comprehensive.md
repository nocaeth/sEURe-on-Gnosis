# Comprehensive Breadth Analysis — sEURe Savings Vault

## FINDING INDEX

| ID | Severity | Location | Title | Verdict |
|----|----------|----------|-------|---------|
| [TR-1] | LOW | InterestReceiver.sol:124 | _calculateClaim rollover underflow if balance drops below claimable | CONTESTED |
| [SR-1] | INFO | InterestReceiver.sol:59-60 | tx.origin-based EOA detection allows any EOA to claim | CONFIRMED (by design) |
| [SR-2] | INFO | InterestReceiver.sol:153-161 | One-step claimer transfer — typo permanently locks role | CONFIRMED (documented risk) |
| [TF-1] | INFO | InterestReceiver.sol:138 | EURe balanceOf(this) donation manipulates epoch calculations | CONFIRMED (expected) |
| [SC-1] | INFO | InterestReceiver.sol:29-38 | No emergency pause or circuit breaker mechanism | CONFIRMED (design choice) |
| [EP-1] | INFO | SavingsEUReAdapter.sol:25 | Unlimited EURe approval to vault in adapter constructor | CONFIRMED (standard pattern) |
| [SV-1] | INFO | SavingsEURe.sol:30-31 | Permit uses SignatureChecker — supports both EOA and ERC1271 | CONFIRMED (correct) |

---

## FINDING [TR-1]: _calculateClaim Rollover Underflow If Balance Drops Below Claimable
**Severity**: LOW (CONTESTED — depends on EURe token implementation)
**Location**: InterestReceiver.sol:124
**Template**: TEMPORAL_PARAMETER_STALENESS

### Description
`_calculateClaim` computes `remaining = balance - claimable` on line 124. The `balance` value comes from `_balance()` = `eure.balanceOf(address(this))`, called fresh in `claim()` on line 81. The `claimable` value is set from `currentEpochBalance` (full-epoch path) or `unclaimedTime * dripRate` (partial-epoch path), both derived from state variables set at the start of the current epoch.

If the actual EURe balance of the receiver drops below `currentEpochBalance` between epoch start and the epoch-end claim, `remaining = balance - claimable` will revert with an underflow.

### Attack Path
1. Epoch starts: `currentEpochBalance = B`, `dripRate = B / epochLength`
2. EURe issuer (Monerium) exercises a burn-from or seizure mechanism on the receiver address, reducing `balanceOf(receiver)` to `B' < B`
3. Claim at epoch end: `claimable = B`, `balance = B' < B`
4. `remaining = B' - B` → arithmetic underflow, claim reverts
5. All subsequent claims revert, permanently bricking yield distribution
6. Adapter deposits/withdrawals continue working (try/catch swallows the revert)

### Preconditions
- EURe token must have a mechanism to reduce `balanceOf(receiver)` without the receiver initiating a transfer
- EURe is a permissioned token — Monerium can potentially blocklist or seize funds

### Impact
If triggered: yield distribution permanently halted. User deposits/withdrawals unaffected (adapter uses try/catch). Yield that should have been distributed remains frozen in receiver.

### Evidence
- [CODE-TRACE] — arithmetic underflow on line 124 if `balance < claimable`
- [EXT-UNV] — EURe token's actual capabilities are UNVERIFIED (no on-chain ABI fetched)
- The CHANGES-FROM-SDAI.md documents "EURe blocklist" as Known Risk #1 but only considers freeze, not balance reduction

### Worst-Case Severity
If EURe can reduce balances: MEDIUM (permanent yield halt, no recovery path for immutable contract)

### Rules Applied
| Rule | Applied? | Notes |
|------|----------|-------|
| R2 (Griefable Preconditions) | YES | Balance-dependent precondition griefable by token issuer |
| R8 (Cached Params) | YES | currentEpochBalance is cached at epoch start, may not reflect current balance |
| R10 (Worst-State) | YES | Assessed at receiver holding 100k+ EURe (realistic operational TVL) |
| R11 (Unsolicited Transfer) | YES | Reverse direction — unsolicited REMOVAL of tokens |
| R14 (Cross-Variable) | YES | currentEpochBalance and actual balance can desync |

### Mitigation
Add a guard: `if (balance < claimable) { claimable = balance; }` before the rollover calculation. Or: `uint256 remaining = balance > claimable ? balance - claimable : 0;`

---

## FINDING [SR-1]: tx.origin-Based EOA Detection — Any EOA Can Claim
**Severity**: INFO (documented as intentional design)
**Location**: InterestReceiver.sol:59-60
**Template**: SEMI_TRUSTED_ROLES

### Description
The `isClaimer` modifier uses `tx.origin == msg.sender` to detect EOAs. This means ANY EOA can call `claim()`, not just the designated claimer. The `claimer` role is only meaningful for contract callers (i.e., the adapter).

### Bidirectional Analysis (Rule 6)

**Direction 1: Role harming users**
- A malicious EOA could front-run adapter deposits by calling claim() first, but this only transfers yield to the vault (beneficial to all depositors)
- No way for an EOA to harm users through claim() — the function only moves EURe from receiver to vault

**Direction 2: Users exploiting role**
- Users can time claims to deposit right before (getting lower share price) or withdraw right after (getting higher share price)
- This is standard ERC4626 yield accrual timing — not exploitable for profit since the claim benefits all shareholders equally

### Rules Applied
| Rule | Applied? | Notes |
|------|----------|-------|
| R6 (Bidirectional) | YES | Both directions analyzed |
| R13 (Anti-Normalization) | YES | No user harm identified — genuinely by design |

---

## FINDING [SR-2]: One-Step Claimer Transfer
**Severity**: INFO (documented risk)
**Location**: InterestReceiver.sol:153-161
**Template**: SEMI_TRUSTED_ROLES

### Description
`setClaimer()` transfers the claimer role in one step — no pending confirmation. If the current claimer sets an incorrect address, the claimer role is permanently lost. The contract is immutable (no proxy, no upgrade mechanism).

### Impact
- Claimer role permanently lost if wrong address set
- EOAs can still call claim() directly — yield distribution continues
- The adapter loses its special claimer status — adapter-triggered claims from contract calls stop working
- External keepers/bots would need to be deployed to maintain automated claiming

### Mitigation
The CHANGES-FROM-SDAI.md documents this as intentional: "one-step because the claimer is expected to become the adapter contract, which cannot accept a two-step handoff."

### Rules Applied
| Rule | Applied? | Notes |
|------|----------|-------|
| R9 (Stranded Asset) | YES | No assets stranded — claimer role is operational, not custodial |
| R13 (Anti-Normalization) | YES | Documented, accepted risk |

---

## FINDING [TF-1]: EURe Donation Manipulates Epoch Calculations
**Severity**: INFO (expected behavior, no profitable attack identified)
**Location**: InterestReceiver.sol:138
**Template**: TOKEN_FLOW_TRACING

### Description
`_balance()` returns `eure.balanceOf(address(this))`. Anyone can transfer EURe to the receiver, directly affecting epoch calculations without going through any protocol function.

### 5-Dimension Analysis (Rule 11)

| Dimension | Analysis | Impact |
|-----------|---------|--------|
| Transferability | YES — direct ERC20 transfer | Must analyze all 4 below |
| Accounting | YES — _balance() affects claim(), initialize(), epoch rollover | Donated EURe included in epoch calculations |
| Operation Blocking | NO — donations increase balance, never decrease | Cannot block operations |
| Loop Iteration | NO — no iterable collections | N/A |
| Side Effects | NO — EURe is standard ERC20, no transfer hooks | N/A |

### Donation Attack Vectors
1. **Before initialize()**: Donated EURe included in initial epoch balance and drip rate. This BENEFITS depositors (higher yield). Attacker cannot extract the donated EURe.
2. **Before epoch rollover**: Increases `remaining`, setting higher drip rate for next epoch. Again benefits all depositors.
3. **Before claim in partial epoch**: Doesn't affect current epoch's drip rate (already set). Only affects rollover.
4. **To vault (not receiver)**: Increases totalAssets, inflating share price. This is the standard ERC4626 donation vector. With decimalsOffset=3, the cost to manipulate share price by 0.1% requires donating ~0.1% of totalAssets.

### Profitability Analysis
- All donation vectors BENEFIT depositors (more yield)
- Attacker cannot extract donated EURe — it's locked in the receiver/vault
- No profitable sandwich attack identified
- Cost of attack = donated amount, benefit = 0 (attacker can't extract value)

### Rules Applied
| Rule | Applied? | Notes |
|------|----------|-------|
| R7 (Threshold Manipulation) | YES | Donations can push balance above/below MIN_EPOCH_BALANCE — but both directions benefit protocol |
| R11 (Unsolicited Transfer) | YES | Full 5-dimension analysis complete |
| R15 (Flash Loan) | YES | Flash-donate to receiver → trigger claim → deposit → withdraw → cannot recover donation — not profitable |

---

## FINDING [SC-1]: No Emergency Pause Mechanism
**Severity**: INFO (design choice, immutable contract)
**Location**: All contracts
**Template**: SEMANTIC_CONSISTENCY_AUDIT

### Description
None of the three contracts (SavingsEURe, InterestReceiver, SavingsEUReAdapter) implement a pause mechanism. If a vulnerability is discovered post-deployment, there's no way to halt operations.

### Impact Analysis (Rule 13 — Anti-Normalization)
1. **Who is harmed?** Depositors if a vulnerability is exploited
2. **Can they avoid it?** Yes — by withdrawing before exploitation
3. **Is it documented?** Yes — immutable contract design is implied by no proxy pattern
4. **Could the same goal be achieved?** No — pause requires mutable state, conflicting with immutability goal
5. **Does the protocol fulfill its purpose?** Yes — all core functions work correctly

### Verdict
INFO — design choice consistent with immutable contract philosophy. Users accept this risk by depositing.

---

## FINDING [EP-1]: Unlimited EURe Approval in Adapter
**Severity**: INFO (standard pattern, no persistent balance)
**Location**: SavingsEUReAdapter.sol:25
**Template**: EXTERNAL_PRECONDITION_AUDIT

### Description
`eure.approve(savingsEuRe_, type(uint256).max)` in constructor grants unlimited allowance to the vault. The adapter only holds EURe transiently during deposit/mint operations — no persistent balance.

### Impact
- If the vault is compromised, attacker could drain the adapter's EURe balance
- But adapter only holds EURe within a single transaction (deposit flow: user → adapter → vault)
- At rest, adapter's EURe balance is 0
- Risk: MEV attacker could front-run a deposit, exploiting the approval to drain EURe that's in-flight
- But the deposit flow is: safeTransferFrom(user, adapter) → sEURe.deposit(assets) which calls asset.transferFrom(adapter, vault)
- The vault pulls from adapter using the existing approval — no external exploit possible

### Rules Applied
| Rule | Applied? | Notes |
|------|----------|-------|
| R3 (Transfer Side Effects) | YES | EURe is standard ERC20 — no side effects |
| R11 (Unsolicited Transfer) | YES | No persistent balance to exploit |

---

## FINDING [SV-1]: Permit Implementation Correct
**Severity**: INFO (no issue found — verification)
**Location**: SavingsEURe.sol:30-31, 35-56
**Template**: SIGNATURE_VERIFICATION_AUDIT

### Analysis
1. **EIP712 Domain**: Uses OpenZeppelin `_hashTypedDataV4()` — correct, fork-aware
2. **Typehash**: Standard Permit typehash — correct
3. **Nonce**: Uses `_useNonce(owner)` — increments nonce, prevents replay ✓
4. **Deadline check**: `block.timestamp > deadline` reverts — correct ✓
5. **Zero owner check**: `owner == address(0)` reverts — correct ✓
6. **Signature validation**: `SignatureChecker.isValidSignatureNow` — supports EOA (ECDSA) + ERC1271 (contract wallets) ✓
7. **No high-s malleability**: SignatureChecker uses OZ's ECDSA internally, which rejects high-s ✓
8. **No duplicate event**: Fixed from sDAI — `_approve` emits Approval once ✓

### v,r,s Overload
`abi.encodePacked(r, s, v)` — correct packing order. The bytes-based permit handles the validation.

### Rules Applied
| Rule | Applied? | Notes |
|------|----------|-------|
| R1 (External Return Type) | YES | SignatureChecker handles both EOA and contract wallets |
| R4 (Adversarial Assumption) | YES | No unknowns — OZ SignatureChecker is well-audited |

---

## ANALYSIS COVERAGE BY TEMPLATE

### ZERO_STATE_RETURN
- `_decimalsOffset() = 3` provides 1000x virtual share multiplier
- First depositor attack requires attacker to donate ~1000x first depositor's amount
- For a 100 EURe first deposit, attacker needs ~100,000 EURe — economically infeasible for most attackers
- Protection is **adequate** for expected deposit sizes
- Edge case: if no one deposits for a long time and yield accumulates in receiver, the first depositor after a claim could benefit disproportionately — but this is normal yield accrual, not a vulnerability

### ECONOMIC_DESIGN_AUDIT
- `dripRate = balance / epochLength` — uncapped, depends on funded balance
- `vaultAPY()` is instantaneous, not trailing — can show inflated APY right after a large deposit to receiver
- `MIN_EPOCH_BALANCE = 100 ether` is the threshold for epoch renewal — if receiver's post-claim balance falls below this, dripRate is set to 0 (epoch drains and stops)
- No rate cap or APY ceiling — but APY is purely informational (not used in any state-changing logic)
- No economic attack identified — yield is distributed pro-rata to all shareholders

### SHARE_ALLOCATION_FAIRNESS
- Standard ERC4626 share allocation — no custom allocation logic
- `decimalsOffset = 3` ensures fair first-depositor treatment
- Claim timing affects share price but distributes yield pro-rata
- No front-running attack identified beyond standard ERC4626 MEV (which is inherent to the standard)
- Adapter's `withdraw` and `redeem` clamp to maxWithdraw/maxRedeem — prevents over-withdrawal

---

## DEPTH TARGETS
None identified — all findings are INFO or LOW/CONTESTED. No REFUTED findings to re-evaluate. No incomplete analysis flags.
