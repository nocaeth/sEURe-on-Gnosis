# Invariant Map

> sEURe | 9 guards | 3 inferred | 2 not enforced on-chain

---

## 1. Enforced Guards (Reference)

Per-call preconditions. Heading IDs below (`G-N`) are anchor targets from x-ray.md attack surfaces.

[NatSpec-stated global invariants do NOT belong here — they route directly to §2/§3/§4 by shape.]

#### G-1
`_getInitializedVersion() == 0` · `InterestReceiver.sol:56` · blocks all state-changing calls before `initialize()` sets the first epoch

#### G-2
`tx.origin != msg.sender && msg.sender != claimer` · `InterestReceiver.sol:60` · restricts contract callers of `claim()` to the designated claimer; EOAs always pass

#### G-3
`msg.sender != claimer` · `InterestReceiver.sol:65` · restricts `initialize()` to the current claimer (deployer pre-handoff)

#### G-4
`currentEpochBalance <= MIN_EPOCH_BALANCE` · `InterestReceiver.sol:67` · ensures the first epoch has ≥ 100 EURe so `dripRate` is non-zero

#### G-5
`claimer != msg.sender` · `InterestReceiver.sol:158` · only the current claimer can transfer the claimer role

#### G-6
`newClaimer == address(0)` · `InterestReceiver.sol:159` · prevents the claimer role from being set to the zero address

#### G-7
`block.timestamp > deadline` · `SavingsEURe.sol:39` · rejects expired permit signatures

#### G-8
`owner == address(0)` · `SavingsEURe.sol:40` · prevents permit from being issued by the zero address

#### G-9
`!_isValidSignature(owner, digest, signature)` · `SavingsEURe.sol:45` · validates EOA or ERC-1271 permit signature

---

## 2. Inferred Invariants (Single-Contract)

Inferred invariants are derived from structural analysis of the source code. Each block below cites one of five extraction methods in its `Derivation` field:

- **Δ-pair (delta-pair) analysis** — two or more storage variables in the same function body that change by equal-and-opposite amounts (e.g. `totalSupply += x` paired with `balances[to] += x`), implying a conservation law like `A == Σ B[key]` or `A + B = const`.

- **Guard lift** — a `require` / `if-revert` on a storage variable, promoted from a per-call precondition to a global property by checking that *every* other write site of that variable enforces an equivalent guard. If any write site lacks it, the lifted invariant is On-chain=**No** (and a candidate bug).

- **State-machine edge** — a storage variable that transitions through discrete values via patterns like `require(state == A); state = B`, with no reverse path. Captures one-shot latches (`setStrategy`) and lifecycle machines (`Pending → Claimable → Claimed`).

- **Temporal predicate** — a check tied to `block.timestamp`, `block.number`, or a stored duration/deadline variable (e.g. `require(block.timestamp < deadline)`).

- **NatSpec-stated global property** — a developer-asserted invariant in a NatSpec `@invariant` tag or inline comment (e.g. *"totalSupply always equals Σ balances"*). Routed directly to this section and then confirmed or contradicted by the structural scan.

Each block is classified into one of five **categories** by shape: `Conservation` · `Bound` · `Ratio` · `StateMachine` · `Temporal`. Category definitions at the end of §2.

---

#### I-1

`Conservation` · On-chain: **Yes**

> `totalSupply == Σ balanceOf[owner]` — every mint/burn pair preserves share conservation.

**Derivation** — Δ-pair: OZ `_mint`/`_burn` always pair `Δ(totalSupply) = ±shares` with `Δ(balanceOf[to/from]) = ±shares`. No other write sites touch `totalSupply` or `balanceOf`.

**If violated** — share accounting breaks; deposits/withdrawals compute wrong amounts.

---

#### I-2

`Bound` · On-chain: **Yes**

> `claimer != address(0)` — the claimer role is always set to a valid address.

**Derivation** — guard-lift: G-6 (`newClaimer == address(0) → revert`) + write-site enumeration. Write sites of `claimer`: (1) `constructor` — set to `msg.sender` (never zero in a real tx); (2) `setClaimer()` — enforces `newClaimer != address(0)`. All write sites enforce the bound.

**If violated** — `claim()` would be restricted to EOAs only (no contract could claim), which is a partial loss of functionality but not a fund-loss risk.

---

#### I-3

`StateMachine` · On-chain: **Yes**

> `InterestReceiver.initialize()` is callable exactly once. State transitions from `uninitialized → initialized` with no reverse path.

**Derivation** — edge: `require(_getInitializedVersion() == 0)` enforced by OZ `initializer` modifier at `InterestReceiver.sol:64`. After execution, `_getInitializedVersion()` returns 1. No function resets it.

**If violated** — re-initialization could overwrite epoch parameters, disrupting drip accounting.

---

**Categories:**
- **Conservation**: Two or more storage variables change by equal-and-opposite amounts in the same function body. Pattern: `Δ(A) = +x, Δ(B) = -x` → `A + B = const`.
- **Bound**: A guard on a storage variable, *lifted to a global property* and enforced across every write site of that variable. Pattern: `require(x <= MAX)` enforced at every writer of `x` → `x ∈ [0, MAX]` globally. On-chain=**No** if any write site lacks the equivalent guard — that unguarded path is a potential bug. Per-call guards with no global implication stay in §1 and are NOT promoted here.
- **Ratio**: A storage variable is defined as a formula of other storage variables. Pattern: `withdrawAmount = totalBalance * shares / totalSupply`.
- **StateMachine**: A storage variable transitions through discrete values with guards preventing reversal. Pattern: `require(state == A); state = B`.
- **Temporal**: A condition depends on `block.timestamp`, `block.number`, or a duration/deadline variable.

---

## 3. Inferred Invariants (Cross-Contract)

Trust assumptions that span contract boundaries. Each block cites both caller-side and callee-side code.

---

#### X-1

On-chain: **No**

> At epoch rollover, the next epoch's `dripRate` and `currentEpochBalance` derive from `eure.balanceOf(address(this)) - claimable` (actual token balance), not from internally tracked accounting. Direct EURe donations to the InterestReceiver inflate the next epoch's parameters.

**Caller side** — `InterestReceiver.sol:128-136` — `_calculateClaim` computes `remaining = balance - claimable` and uses it as the next epoch's balance and drip rate when `block.timestamp > nextClaimEpoch`.

**Callee side** — `InterestReceiver.sol:141-143` — `_balance()` returns `eure.balanceOf(address(this))`, which any address can inflate by transferring EURe directly to the receiver.

**If violated** — a donation before epoch rollover increases `remaining`, producing a higher `dripRate` and `currentEpochBalance` for the next epoch. This accelerates yield distribution to the vault. The effect benefits all sEURe holders proportionally (yield goes to the vault), so direct value extraction is not possible. However, if `vaultAPY()` is consumed by downstream protocols for collateral/risk decisions, the inflated rate could mislead.

---

#### X-2

On-chain: **Yes**

> `SavingsEUReAdapter._claimHook()` calls `interestReceiver.claim()` inside a `try/catch` that silently ignores failures. User operations (deposit/withdraw) always succeed regardless of claim outcome.

**Caller side** — `SavingsEUReAdapter.sol:36-37` — `try interestReceiver.claim() {} catch {}`

**Callee side** — `InterestReceiver.sol:76-97` — `claim()` updates four storage variables before the external `eure.safeTransfer`. If the transfer fails (e.g., EURe paused or blacklisted), state has already been committed (lastClaimTimestamp, currentEpochBalance updated), but the `try/catch` swallows the revert.

**If violated** — if `claim()` reverts on the `safeTransfer` line, `lastClaimTimestamp` is already set to `block.timestamp`, so a retry in the same block returns 0. The claimable amount for that period is lost (currentEpochBalance was set to nextEpochBalance_ which may be lower or zero).

---

## 4. Economic Invariants

Higher-order properties derived from combinations of §2 and §3 invariants. Every block traces back to concrete invariant IDs.

---

#### E-1

On-chain: **Yes**

> sEURe share price is monotonically non-decreasing when `InterestReceiver.claim()` transfers EURe into the vault without minting shares.

**Follows from** — `I-1` (share conservation) + `X-2` (claim transfers yield to vault)

**If violated** — share price could decrease, meaning depositors lose value. Since claims only add EURe to the vault without changing totalSupply, the share price (`totalAssets / totalSupply`) can only increase from yield. Rounding in ERC4626 conversion always rounds in favor of the vault (OZ default), preserving this property.
