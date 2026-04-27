# X-Ray Report

> sEURe | 270 nSLOC | 6ff3047 (`master`) | Foundry | 27/04/26

---

## 1. Protocol Overview

**What it does:** ERC-4626 vault for EURe on Gnosis Chain — users deposit EURe, receive sEURe shares, and earn yield dripped in over 5-day epochs.

- **Users**: EURe holders depositing for yield; Monerium bot funding the InterestReceiver
- **Core flow**: Deposit EURe → receive sEURe shares → yield dripped into vault over epochs → share price appreciates → redeem for more EURe
- **Key mechanism**: Epoch-based linear drip with `dripRate = epochBalance / epochLength`; same-block claim guard prevents flash-loan yield grabbing
- **Token model**: EURe (underlying ERC-20 at `0x420CA...a3430`), sEURe (ERC-4626 share token with 3-decimal offset)
- **Admin model**: `claimer` role on InterestReceiver — only role in the system, controls contract claim access and claimer transfer

For a visual overview of the protocol's architecture, see the [architecture diagram](architecture.svg).

### Contracts in Scope

| Subsystem | Key Contracts | nSLOC | Role |
|-----------|--------------|------:|------|
| Core Vault | SavingsEURe | 46 | ERC-4626 vault wrapping EURe with permit support |
| Yield Drip | InterestReceiver | 117 | Epoch-based EURe yield drip into the vault |
| Periphery | SavingsEUReAdapter | 53 | User-facing adapter bundling vault ops with opportunistic claims |

### How It Fits Together

The core trick: external EURe funding is dripped into the vault linearly over 5-day epochs, incrementally increasing `totalAssets` without minting shares, so the sEURe/EURe exchange rate rises for all holders.

### Deposit via Adapter

```
User → SavingsEUReAdapter.deposit(assets, receiver)
  ├─ _claimHook()                          ← EOA only: try interestReceiver.claim()
  │   └─ InterestReceiver.claim()
  │       ├─ _calculateClaim(balance)      ← compute claimable, next epoch params
  │       ├─ update epoch state            ← currentEpochBalance, dripRate, nextClaimEpoch
  │       └─ eure.safeTransfer(sEURe)      ← yield enters vault
  ├─ eure.safeTransferFrom(user, adapter)
  └─ sEURe.deposit(assets, receiver)       ← OZ ERC4626 mints shares
```

### Direct Vault Deposit

```
User → SavingsEURe.deposit(assets, receiver)   ← inherited ERC4626
  ├─ eure.transferFrom(user, vault)
  └─ _mint(receiver, shares)                   ← share conservation invariant
```

### Epoch Rollover (inside claim)

```
InterestReceiver.claim()
  └─ _calculateClaim(balance)
      ├─ claimable = unclaimedTime * dripRate  ← partial epoch
      ├─ claimable = currentEpochBalance       ← full epoch expired
      ├─ claimable = min(claimable, balance)   ← bounded by actual holdings
      └─ if block.timestamp > nextClaimEpoch:  ← rollover
          remaining = balance - claimable
          ├─ remaining < MIN_EPOCH_BALANCE → dripRate = 0, stop
          └─ remaining >= MIN_EPOCH_BALANCE → new epoch with updated dripRate
```

---

## 2. Threat & Trust Model

> **Bullet brevity rule (applies to every bullet-heavy subsection in Sections 2, 3, 6):** one tight sentence per bullet — ideally one line, max two. Don't restate what the `file:line` reference already shows.

### Protocol Threat Profile

> Protocol classified as: **Yield Aggregator / Vault** with **Liquid Staking** characteristics

ERC-4626 vault pattern with deposit/withdraw/convertToShares/convertToAssets, epoch-based yield drip, and share-based accounting. Secondary liquid-staking signal: derivative token (sEURe) with monotonically increasing exchange rate against the underlying.

### Actors & Adversary Model

| Actor | Trust Level | Capabilities |
|-------|-------------|-------------|
| User | Untrusted | Deposit, withdraw, redeem via adapter or directly on vault; call `claim()` as EOA |
| Claimer | Bounded (single address, no delay) | Call `claim()` as contract; transfer claimer role (one-step, no delay) |

**Adversary Ranking** (ordered by threat level for this protocol type, adjusted by git evidence):

1. **Share inflation attacker (first depositor)** — Canonical vault attack: manipulate empty-vault share price to steal from subsequent depositors.
2. **Donation/direct-transfer attacker** — Sends EURe directly to InterestReceiver to manipulate epoch parameters at rollover.
3. **Compromised claimer** — Can transfer claimer role instantly (one-step, no delay), but cannot extract user funds or change vault parameters.

See [entry-points.md](entry-points.md) for the full permissionless entry point map.

### Trust Boundaries

- **User → Vault** — no access control needed; standard ERC4626 deposit/withdraw; share conservation enforced by OZ internals.
- **Contract → InterestReceiver.claim()** — `isClaimer` modifier at `InterestReceiver.sol:60` restricts contract callers to the designated claimer address; EOAs always pass. No timelock, no multisig. One-step `setClaimer()` at `InterestReceiver.sol:157` with no delay.

### Key Attack Surfaces

- **Epoch rollover donation inflation** &nbsp;&#91;[X-1](invariants.md#x-1)&#93; — `InterestReceiver._calculateClaim:128-136` uses `balance - claimable` as next epoch balance at rollover, where `balance = eure.balanceOf(address(this))`. Worth tracing whether a donation right before rollover inflates the next epoch's drip rate and whether `vaultAPY()` consumers are affected.

- **Claim state committed before safeTransfer, failures swallowed** &nbsp;&#91;[X-2](invariants.md#x-2)&#93; — `InterestReceiver.claim():88-93` writes four storage variables before `eure.safeTransfer()` at line 93; the adapter's `try/catch` at `SavingsEUReAdapter.sol:36` swallows any revert. Worth confirming the transfer cannot fail under normal EURe operation (not paused, not blacklisting the vault).

- **Single-step claimer transfer with no delay** — `InterestReceiver.setClaimer:157-165`. No two-step handoff, no timelock. The claimer role is limited (only controls contract claim access), but a compromised claimer could call `claim()` at adversarial timing.

- **ERC4626 first-depositor share inflation** — `SavingsEURe._decimalsOffset:24` returns 3, providing OZ v5.3's virtual offset protection. Worth confirming the offset is sufficient for the vault's expected TVL range.

- **Adapter claim only for EOAs** — `SavingsEUReAdapter._claimHook:35` checks `msg.sender == tx.origin`; contract callers (DeFi composability) do not trigger claims. Worth confirming this is acceptable for intended integrations.

### Protocol-Type Concerns

**As a Yield Aggregator / Vault:**
- `totalAssets()` reads `eure.balanceOf(address(vault))` via OZ ERC4626 default — direct EURe donation to the vault changes share price without going through deposit. Worth confirming OZ's virtual offset mitigates this for the expected TVL range.
- `_decimalsOffset() = 3` provides 10³ = 1000 virtual shares — standard OZ v5.3 inflation protection. Verify this is adequate for vault size.

**As a Liquid Staking derivative:**
- sEURe exchange rate increases monotonically from yield — no rebasing, no slashing. The rate is purely a function of `totalAssets / totalSupply` where `totalAssets` only grows from claim transfers.

### Temporal Risk Profile

**Deployment & Initialization:**
- `InterestReceiver.initialize():64-73` must be called by the deployer (current claimer) while `claimer` hasn't been transferred to the adapter yet. The README documents this ordering requirement explicitly. After `setClaimer(adapter)`, only the adapter could call `initialize` as a contract, but the adapter doesn't expose it. **Mitigated** by documented deployment sequence.
- `initialize()` requires `currentEpochBalance > MIN_EPOCH_BALANCE` (100 EURe). Deployment must fund the receiver first. **Mitigated** by the guard at `InterestReceiver.sol:67`.

### Composability & Dependency Risks

**Dependency Risk Map:**

> **EURe (ERC-20)** — via `SavingsEURe`, `InterestReceiver`, `SavingsEUReAdapter`
> - Assumes: standard ERC-20 behavior (exact transfer amounts, no fees, no rebasing)
> - Validates: `SafeERC20` used throughout; no fee-on-transfer handling (no `balanceOf` diff checks)
> - Mutability: Immutable (no proxy, hardcoded at `0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430`)
> - On failure: `safeTransfer`/`safeTransferFrom` revert on failure

**Token Assumptions** *(unvalidated only)*:
- EURe: assumes no fee-on-transfer — impact if violated: vault accounting would drift (deposits record more assets than received)

**Shared State Exposure:**
- `InterestReceiver._balance()` reads `eure.balanceOf(address(this))` — any address can change this value via direct transfer, affecting epoch rollover calculations (see X-1).

---

## 3. Invariants

> ### 📋 Full invariant map: **[invariants.md](invariants.md)**
>
> A dedicated reference file contains the complete invariant analysis — do not look here for the catalog.
>
> - **9 Enforced Guards** (`G-1` … `G-9`) — per-call preconditions with `Check` / `Location` / `Purpose`
> - **3 Single-Contract Invariants** (`I-1` … `I-3`) — Conservation, Bound, StateMachine
> - **2 Cross-Contract Invariants** (`X-1` … `X-2`) — caller/callee pairs that cross scope boundaries
> - **1 Economic Invariant** (`E-1`) — higher-order property deriving from `I-1` + `X-2`
>
> Every inferred block cites a concrete Δ-pair, guard-lift + write-sites, state edge, or NatSpec quote. The **On-chain=No** blocks are the high-signal ones — each is simultaneously an invariant and a potential bug. Attack-surface bullets above cross-link directly into the relevant blocks (e.g. `[X-1]`, `[X-2]`).

---

## 4. Documentation Quality

| Aspect | Status | Notes |
|--------|--------|-------|
| README | Present | `README.md` — architecture overview, deployment ordering, contract descriptions |
| NatSpec | ~6 annotations | `@inheritdoc` on public state vars; `@notice`/`@dev` on interface functions; sparse on internal logic |
| Spec/Whitepaper | Missing | No formal spec; README serves as lightweight spec (per spec: "yield cannot be grabbed in a single block") |
| Inline Comments | Sparse | Key design decisions commented (e.g., `// only EOAs are able to claim interest`, `_claimHook` try/catch rationale) |

---

## 5. Test Analysis

| Metric | Value | Source |
|--------|-------|--------|
| Test files | 9 | File scan (always reliable) |
| Test functions | 69 (85 including harness) | File scan (always reliable) |
| Line coverage | 100.00% (155/155) | `forge coverage` |
| Branch coverage | 100.00% (27/27) | `forge coverage` |
| Statement coverage | 100.00% (169/169) | `forge coverage` |

### Test Depth

| Category | Count | Contracts Covered |
|----------|-------|-------------------|
| Unit | 60+ | SavingsEURe, InterestReceiver, SavingsEUReAdapter |
| Stateless Fuzz | 9 | SavingsEURe, InterestReceiver |
| Stateful Fuzz (Foundry) | 0 | none |
| Stateful Fuzz (Echidna) | 0 | none |
| Formal Verification (Certora) | 0 | none |
| Formal Verification (Halmos) | 0 | none |
| Formal Verification (HEVM) | 0 | none |

### Gaps

- **No stateful fuzz testing** — epoch boundary logic (`_calculateClaim` rollover paths) is stateful by nature; unit tests may not cover multi-epoch sequences with adversarial timing.
- **No formal verification** — drip rate math and epoch rollover arithmetic are financial calculations that benefit from formal methods.
- **No fork tests** — protocol interacts with real EURe token on Gnosis; fork tests would validate SafeERC20 assumptions against the deployed token.

---

## 6. Developer & Git History

> Repo shape: `normal_dev` — 3 source-touching commits over 18 days; short but visible history.

### Contributors

| Author | Commits | Source Lines (+/-) | % of Source Changes |
|--------|--------:|--------------------|--------------------:|
| daveai | 3 | +382 / -0 | 53.2% |
| Luigy-Lemon | 1 | +336 / -0 | 46.8% |

Two-developer concentration: 100% of source changes from 2 authors across 4 commits.

### Review & Process Signals

| Signal | Value | Assessment |
|--------|-------|------------|
| Unique contributors | 2 | Small team |
| Merge commits | 0 of 4 (0%) | No merge commits — likely no formal peer review |
| Repo age | 2026-04-09 → 2026-04-27 | 18 days |
| Recent source activity (30d) | 3 commits | Active — most changes in last 30 days |
| Test co-change rate | 100% | All source-changing commits also modify tests |

### File Hotspots

| File | Modifications | Note |
|------|-------------:|------|
| src/InterestReceiver.sol | 3 | Highest churn — core drip logic |
| src/SavingsEURe.sol | 3 | Vault + permit logic |
| src/periphery/SavingsEUReAdapter.sol | 3 | Adapter with claim hook |
| src/interfaces/IInterestReceiver.sol | 3 | Interface definitions |
| src/interfaces/ISavingsEUReAdapter.sol | 3 | Interface definitions |
| src/interfaces/ISavingsEURe.sol | 1 | Least modified |

### Security-Relevant Commits

**Score** = weighted sum of fix-like signals in a commit: message keywords (fix, bug, reentrancy, overflow...), diff patterns (deletes code, changes `require`/`assert`, touches access control or accounting), and change shape (focused = higher). **10+ warrants a manual diff.**

| SHA | Date | Subject | Score | Key Signal |
|-----|------|---------|------:|------------|
| bba8371 | 2026-04-09 | sEURe savings vault — adapted from sDAI-on-Gnosis | 15 | Initial implementation: fund flows, signatures, access control |
| 962607b | 2026-04-09 | remove old OZ | 15 | Access control tightening (+11), guards added (+9) |
| 6ff3047 | 2026-04-27 | Upgrade to OZ v5.3, custom errors, interfaces | 13 | Guards removed (-11), access control changes (+6/-1), 526 lines |

### Dangerous Area Evolution

| Security Area | Commits | Key Files |
|--------------|--------:|-----------|
| fund_flows | 3 | InterestReceiver.sol, SavingsEUReAdapter.sol, SavingsEURe.sol |
| signatures | 3 | SavingsEURe.sol, ISavingsEURe.sol |

### Forked Dependencies

| Library | Path | Upstream | Status | Notes |
|---------|------|----------|--------|-------|
| openzeppelin-contracts | `lib/openzeppelin-contracts` | OpenZeppelin | Submodule | Contains pragma versions `>=0.4.22 <0.9.0` and `>=0.6.0 <0.9.0` from legacy OZ files; in-scope files use `^0.8.20` |

### Security Observations

- **Two-developer concentration** — daveai (53%) + Luigy-Lemon (47%) = 100% of source; no independent third reviewer.
- **No merge commits** — 0 of 4 commits merged; likely no formal peer review process.
- **Large initial commit** — `962607b` (355 lines) and `6ff3047` (526 lines) are large changes touching all security areas simultaneously.
- **100% test co-change rate** — every source-changing commit also modifies tests, indicating disciplined development.
- **18-day history** — very young codebase; all commits within 3 weeks.

### Cross-Reference Synthesis

- **InterestReceiver.sol is #1 in churn AND #1 in attack surfaces** — all epoch rollover and donation concerns route through `_calculateClaim` → highest-leverage review target.
- **`6ff3047` removed 11 guards while adding custom errors** — worth diffing to confirm no guard was dropped unintentionally during the OZ v5.3 migration.
- **Fund flows and signatures changed in every commit** — 3/3 commits touch both areas; the permit + deposit/withdraw paths have been continuously reworked.

---

## X-Ray Verdict

**FRAGILE** — no timelock on claimer transfer, no pause mechanism, no admin controls beyond a single one-step role; 18-day codebase history from 2 developers with no merge commits.

**Structural facts:**
1. 270 nSLOC across 3 contracts (vault + drip + adapter)
2. 100% line/branch/statement coverage across all contracts (85 tests)
3. 2 developers, 4 commits, 18-day history, no formal review process
4. No admin/owner role, no pause, no timelock, no upgrade mechanism — claimer is the only privileged role
5. All financial logic (epoch drip, share conversion) depends on OZ ERC4626 + custom drip math — no oracle, no liquidation, no external protocol integration beyond EURe token
