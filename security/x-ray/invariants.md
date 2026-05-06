# Invariant Map

> sEURe | 15 guards | 4 inferred (single-contract) | 2 cross-contract | 1 economic

---

## 1. Enforced Guards (Reference)

Per-call preconditions. Heading IDs below (`G-N`) are anchor targets from x-ray.md attack surfaces.

#### G-1
`interestDispatcher_ == address(0) \|\| interestDispatcher_.code.length == 0` · `SavingsEURe.sol:30-31` · Ensures vault is constructed with a valid, deployed interest receiver.

#### G-2
`msg.sender != interestDispatcher` · `SavingsEURe.sol:39` · Restricts claim sync enablement to the designated receiver address.

#### G-3
`!interestClaimingEnabled` · `SavingsEURe.sol:47` · Blocks yield claiming until receiver has initialized and opted in.

#### G-4
`block.timestamp > deadline` · `SavingsEURe.sol:89` · Rejects expired permit signatures.

#### G-5
`owner == address(0)` · `SavingsEURe.sol:92` · Prevents setting allowance for the zero address.

#### G-6
`!SignatureChecker.isValidSignatureNow(owner, digest, signature)` · `SavingsEURe.sol:99` · Validates permit signature via EOA ECDSA or ERC-1271 contract wallet.

#### G-7
`!_isRuntimeInitialized()` (checks `sEURe != address(0) && owner != address(0)`) · `InterestDispatcher.sol:54-56` · Blocks all receiver operations before initialize sets required state.

#### G-8
`vault == address(0) \|\| owner_ == address(0)` · `InterestDispatcher.sol:60` · Rejects zero addresses during receiver initialization.

#### G-9
`currentEpochBalance <= MIN_EPOCH_BALANCE` · `InterestDispatcher.sol:66` · Ensures initial epoch has enough EURe (>100) to produce a non-zero drip rate.

#### G-10
`lastClaimTimestamp == block.timestamp` · `InterestDispatcher.sol:76` · Returns 0 if already claimed this block; prevents same-block double-claim.

#### G-11
`claimable > balance` · `InterestDispatcher.sol:122` · Caps claim at actual EURe balance held by receiver.

#### G-12
`remaining < MIN_EPOCH_BALANCE` · `InterestDispatcher.sol:128` · Prevents starting a new drip epoch with insufficient EURe; sets drip rate to zero instead.

#### G-13
`msg.sender != owner` · `InterestDispatcher.sol:157` · Restricts ownership transfer to current owner.

#### G-14
`newOwner == address(0)` · `InterestDispatcher.sol:158` · Prevents transferring upgrade ownership to zero address.

#### G-15
`msg.sender != owner` · `InterestDispatcher.sol:166` · Restricts proxy implementation upgrades to owner.

---

## 2. Inferred Invariants (Single-Contract)

---

#### I-1

`StateMachine` · On-chain: **Yes**

> `interestClaimingEnabled` transitions from `false` to `true` exactly once with no reverse path.

**Derivation** — edge: `false@SavingsEURe.sol:23 → true@SavingsEURe.sol:41`. Single write site at `enableInterestClaiming()`, gated by `msg.sender != interestDispatcher` (G-2). No function resets it. Once true, `_claimInterest()` always proceeds.

**If violated** — Claim sync could be disabled after users expect yield accrual, or enabled before receiver is ready.

---

#### I-2

`Bound` · On-chain: **Yes**

> `owner != address(0)` after initialization.

**Derivation** — guard-lift: G-8 at InterestDispatcher.sol:60 checks `owner_ != address(0)` during initialization. G-14 at InterestDispatcher.sol:158 checks `newOwner != address(0)` during transfer. All write sites of `owner`: L63 (initialize, guarded by G-8), L161 (transferOwnership, guarded by G-14). Both enforce non-zero.

**If violated** — Upgrade authority burned, permanently locking the InterestDispatcher implementation.

---

#### I-3

`Conservation` · On-chain: **Yes**

> `totalSupply == Σ balanceOf[account]` for sEURe shares.

**Derivation** — Δ-pair: OZ ERC20 `_mint` does `Δ(totalSupply) = +shares, Δ(balanceOf[to]) = +shares`; `_burn` does `Δ(totalSupply) = -shares, Δ(balanceOf[from]) = -shares`. No function writes one without the other. Standard OZ invariant.

**If violated** — Share accounting breaks; users cannot redeem correct amounts.

---

#### I-4

`Temporal` · On-chain: **Yes**

> At most one effective claim per block — `lastClaimTimestamp` uniquely identifies the last claimed block.

**Derivation** — temporal: `lastClaimTimestamp == block.timestamp` check at InterestDispatcher.sol:76 returns 0 without state change if already claimed this block. Write at InterestDispatcher.sol:90 sets `lastClaimTimestamp = block.timestamp`. Same-block re-entry returns 0.

**If violated** — Yield could be double-counted within a single block, inflating share price.

---

## 3. Inferred Invariants (Cross-Contract)

---

#### X-1

On-chain: **No**

> SavingsEURe assumes InterestDispatcher.claim() will not revert during normal operation (returns 0 if already claimed or no balance).

**Caller side** — `SavingsEURe.sol:49` — `_claimInterest()` calls `IInterestDispatcher(interestDispatcher).claim()` before every deposit, mint, withdraw, and redeem. If claim() reverts, the entire vault operation reverts.

**Callee side** — `InterestDispatcher.sol:165-167` — `owner` can upgrade the implementation via UUPS (`_authorizeUpgrade`). A malicious or broken upgrade can make claim() revert, permanently blocking all vault operations. The only revert path in the current implementation is `_requireInitialized()` (G-7), which is unreachable after successful initialization.

**If violated** — All vault operations (deposit, mint, withdraw, redeem) are permanently blocked if the receiver's claim() reverts.

---

#### X-2

On-chain: **Yes**

> InterestDispatcher.claim() transfers EURe directly into the vault, increasing `totalAssets()` without minting shares.

**Caller side** — `InterestDispatcher.sol:92` — `eure.safeTransfer(address(sEURe), claimed)` sends EURe to the vault.

**Callee side** — `SavingsEURe` (via OZ ERC4626 `totalAssets()`) reads `IERC20(asset).balanceOf(address(this))`. The transferred EURe increases the vault's asset balance, increasing share price for all holders. No other external contract can remove EURe from the vault — only withdraw/redeem paths via standard ERC4626.

**If violated** — Share price calculation becomes incorrect; users receive wrong amounts on redemption.

---

## 4. Economic Invariants

---

#### E-1

On-chain: **Yes**

> sEURe share price is monotonically non-decreasing (absent withdrawals).

**Follows from** — `I-3` + `X-2`

Conservation of supply/balances (I-3) ensures share count tracks holdings. InterestDispatcher only adds assets to the vault (X-2) — it never removes them. Each claim increases totalAssets without minting shares, so `totalAssets / totalSupply` can only increase or stay constant between deposit/withdraw operations.

**If violated** — Users receive fewer assets than expected on redemption; yield is lost.
