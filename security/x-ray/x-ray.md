# X-Ray Report

> sEURe | 255 nSLOC | 255c50c (`master`) | Foundry | 05/05/26

---

## 1. Protocol Overview

**What it does:** ERC-4626 yield vault for Monerium EURe on Gnosis Chain — users deposit EURe, receive sEURe shares that appreciate as yield drips in over 5-day epochs.

- **Users**: Deposit EURe, hold sEURe shares that appreciate; anyone can trigger yield claims
- **Core flow**: Deposit EURe → receive sEURe → yield drips into vault over epochs → redeem for more EURe
- **Key mechanism**: Epoch-based linear drip — InterestDispatcher releases EURe into vault at a constant rate per epoch, rolling over every 5 days
- **Token model**: sEURe (ERC4626 share token, 18 decimals, 3-decimal virtual offset); EURe (underlying Monerium ERC20, 18 decimals)
- **Admin model**: No owner on SavingsEURe; `owner` on InterestDispatcher controls UUPS upgrades and ownership transfer

Adapted from [sDAI-on-Gnosis](https://github.com/gnosischain/sDAI-on-Gnosis).

For a visual overview of the protocol's architecture, see the [architecture diagram](architecture.svg).

### Contracts in Scope

| Subsystem | Key Contracts | nSLOC | Role |
|-----------|--------------|------:|------|
| Vault | SavingsEURe | 91 | ERC4626 vault wrapping EURe with permit support |
| Yield Drip | InterestDispatcher | 119 | Epoch-based EURe drip into vault; UUPS upgradeable |
| Interfaces | ISavingsEURe, IInterestDispatcher | 45 | Type definitions and NatSpec |

### How It Fits Together

The core trick: EURe yield flows through a permissionless epoch-based drip into the vault, and every share-changing operation claims yield first to keep accounting current.

### Deposit

```
SavingsEURe.deposit(assets, receiver)
├─ SavingsEURe._claimInterest()
│  └─ InterestDispatcher.claim()                        ← updates drip epoch, transfers EURe to vault
└─ ERC4626.deposit(assets, receiver)
   └─ ERC20._mint(receiver, shares)                   ← mints sEURe shares
   └─ EURe.safeTransferFrom(user, vault, assets)      ← pulls EURe from user
```

### Withdraw

```
SavingsEURe.withdraw(assets, receiver, owner)
├─ SavingsEURe._claimInterest()
│  └─ InterestDispatcher.claim()                        ← updates drip epoch, transfers EURe to vault
└─ ERC4626.withdraw(assets, receiver, owner)
   └─ ERC20._burn(owner, shares)                      ← burns sEURe shares
   └─ EURe.safeTransfer(receiver, assets)             ← pushes EURe to receiver
```

### Yield Drip

```
InterestDispatcher.claim()                               ← permissionless
├─ InterestDispatcher._calculateClaim(balance)
│  ├─ claimable = elapsed × dripRate                  ← linear drip within epoch
│  └─ [if epoch elapsed] recalculate from remaining   ← rollover to new epoch
├─ [update currentEpochBalance, dripRate, nextClaimEpoch, lastClaimTimestamp]
└─ EURe.safeTransfer(address(sEURe), claimed)         ← increases vault totalAssets
```

### Initialization

```
InterestDispatcher.initialize(vault, owner_)             ← proxy initializer, once
├─ SavingsEURe.enableInterestClaiming()               ← enables _claimInterest guard
├─ currentEpochBalance = EURe.balanceOf(this)
├─ dripRate = currentEpochBalance / epochLength       ← 5-day epoch
└─ emit Initialized(...)
```

---

## 2. Threat & Trust Model

> **Bullet brevity rule (applies to every bullet-heavy subsection in Sections 2, 3, 6):** one tight sentence per bullet — ideally one line, max two. Don't restate what the `file:line` reference already shows.

### Protocol Threat Profile

> Protocol classified as: **Yield Aggregator / Vault**

ERC4626 vault with epoch-based yield drip. Shares appreciate as EURe flows in from InterestDispatcher. No lending, no DEX, no governance — pure deposit/yield/withdraw lifecycle.

### Actors & Adversary Model

| Actor | Trust Level | Capabilities |
|-------|-------------|-------------|
| User | Untrusted | deposit, mint, withdraw, redeem, permit, transfer/approve sEURe |
| Keeper / Anyone | Untrusted | claim() — triggers yield drip, no negative side effects |
| owner | Bounded (single EOA, no timelock) | Upgrade InterestDispatcher implementation (UUPS), transfer ownership — instant, no delay |
| interestDispatcher | Bounded (address, immutable) | enableInterestClaiming() — one-time, enables vault-side claim sync |
| Monerium Bot | External | Funds InterestDispatcher with EURe via direct transfer |

**Adversary Ranking** (ordered by threat level for this protocol type, adjusted by git evidence):

1. **Compromised owner** — Single EOA with instant UUPS upgrade power over InterestDispatcher; all vault operations depend on the receiver's correctness.
2. **Share inflation attacker (first depositor)** — Classic ERC4626 empty-vault manipulation; mitigated by `_decimalsOffset(3)` but worth confirming sufficiency.
3. **Donation / direct-transfer attacker** — Sending EURe directly to InterestDispatcher alters next epoch's drip rate and reported APY; intentional per design docs.

See [entry-points.md](entry-points.md) for the full permissionless entry point map.

### Trust Boundaries

- **owner ↔ InterestDispatcher implementation** — No timelock or multisig; instant UUPS upgrade authority. Single EOA compromise → receiver can be replaced with malicious implementation → all vault ops blocked or manipulated. InterestDispatcher.sol:165-167.
- **SavingsEURe ↔ InterestDispatcher claim()** — Every deposit/mint/withdraw/redeem calls `_claimInterest()` which calls `receiver.claim()`. If claim() reverts, all vault operations are blocked. SavingsEURe.sol:49.

### Key Attack Surfaces

- **InterestDispatcher UUPS upgrade authority** &nbsp;&#91;[X-1](invariants.md#x-1)&#93; — `owner` can replace implementation instantly (InterestDispatcher.sol:165-167); no timelock, no multisig. Worth tracing what a malicious implementation could do to vault operations that call claim() before every share change.

- **Vault↔Receiver operational coupling** &nbsp;&#91;[X-1](invariants.md#x-1), [X-2](invariants.md#x-2)&#93; — All four vault operations (deposit, mint, withdraw, redeem) call `_claimInterest()` first (SavingsEURe.sol:54,60,69,80). Worth confirming claim() has no revert path under normal operation and that the receiver cannot be bricked by external state changes.

- **ERC4626 empty-vault share math** — `_decimalsOffset() = 3` provides a 10³ virtual-share offset (SavingsEURe.sol:124-126). Worth confirming this is sufficient given EURe's 18-decimal precision and typical deposit sizes.

- **EURe token behavior assumptions** — Vault uses `safeTransferFrom`/`safeTransfer` but assumes standard ERC20 behavior (no fee-on-transfer, no rebase). InterestDispatcher reads `eure.balanceOf(address(this))` for accounting (InterestDispatcher.sol:141). Worth confirming Monerium EURe is a vanilla ERC20.

- **vaultAPY display metric** — Derived from `dripRate * 365 days / totalAssets` (InterestDispatcher.sol:151-152). Not oracle-validated; direct EURe transfers to receiver affect next epoch's drip rate. NatSpec explicitly warns integrators. Worth confirming no downstream protocol uses it as a price feed.

- **Integer division in drip rate** — `dripRate = currentEpochBalance / epochLength` (InterestDispatcher.sol:69) and `remaining / epochLength` at rollover (L132). Remainder locked until rollover. Worth checking if rounding direction is consistently conservative or if it creates systematic drift.

### Upgrade Architecture Concerns

- **InterestDispatcher is UUPS upgradeable** — `_authorizeUpgrade` checks `msg.sender == owner` (InterestDispatcher.sol:165-167). No timelock, no delay. Storage layout must be preserved across upgrades. Constructor calls `_disableInitializers()` (L41-43) preventing implementation contract initialization.

### Protocol-Type Concerns

**As a Yield Aggregator / Vault:**
- `totalAssets()` reads `asset.balanceOf(address(this))` via OZ ERC4626 — direct EURe donations to the vault (not through deposit) increase share price. The 3-decimal virtual offset mitigates first-depositor inflation. SavingsEURe.sol:124-126.
- No strategy contract — yield comes from InterestDispatcher drips, not from deploying funds into external protocols. This limits the attack surface to the receiver's epoch accounting.

### Temporal Risk Profile

**Deployment & Initialization:**
- `initialize()` gated by `initializer` modifier and proxy pattern — called during deployment broadcast to prevent front-running. Receiver must hold ≥100 EURe (`MIN_EPOCH_BALANCE`). Deployment ordering: implementation → proxy → vault → fund receiver → initialize → seed vault (all in single broadcast).

### Composability & Dependency Risks

**Dependency Risk Map:**

> **EURe (Monerium)** — via `InterestDispatcher.sol:21`, `SavingsEURe.sol:27`
> - Assumes: Standard ERC20 behavior (exact transfer amounts, no rebase, no fee-on-transfer)
> - Validates: Uses SafeERC20 for transfer/transferFrom
> - Mutability: Immutable (hardcoded address `0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430`)
> - On failure: revert

**Token Assumptions** *(unvalidated)*:
- EURe: assumes no fee-on-transfer — impact if violated: vault accounting > real balance, share price inflation
- EURe: assumes no rebasing — impact if violated: balanceOf drift between claim and deposit/withdraw

---

## 3. Invariants

> ### 📋 Full invariant map: **[invariants.md](invariants.md)**
>
> A dedicated reference file contains the complete invariant analysis — do not look here for the catalog.
>
> - **15 Enforced Guards** (`G-1` … `G-15`) — per-call preconditions with `Check` / `Location` / `Purpose`
> - **4 Single-Contract Invariants** (`I-1` … `I-4`) — StateMachine, Bound, Conservation, Temporal
> - **2 Cross-Contract Invariants** (`X-1` … `X-2`) — vault↔receiver dependency chain
> - **1 Economic Invariant** (`E-1`) — monotonic share price
>
> Every inferred block cites a concrete Δ-pair, guard-lift + write-sites, state edge, temporal predicate, or NatSpec quote. The **On-chain=No** blocks are the high-signal ones — each is simultaneously an invariant and a potential bug. Attack-surface bullets above cross-link directly into the relevant blocks (e.g. `[X-1]`, `[X-2]`).

---

## 4. Documentation Quality

| Aspect | Status | Notes |
|--------|--------|-------|
| README | Present | README.md — deployment, security notes, integration notes |
| NatSpec | ~4 annotations | Sparse — functions documented but invariants not explicitly stated in code |
| Spec/Whitepaper | Present | README.md + referenced CHANGES-FROM-SDAI.md |
| Inline Comments | Sparse | Key logic in `_calculateClaim` uncommented |

---

## 5. Test Analysis

| Metric | Value | Source |
|--------|-------|--------|
| Test files | 7 | File scan (always reliable) |
| Test functions | 68 | File scan (always reliable) |
| Line coverage | 100.00% (169/169) | forge coverage |
| Branch coverage | 100.00% (30/30) | forge coverage |

### Test Depth

| Category | Count | Contracts Covered |
|----------|-------|-------------------|
| Unit | 63 | SavingsEURe, InterestDispatcher, deploy script |
| Stateless Fuzz | 5 | SavingsEURe, InterestDispatcher |
| Stateful Fuzz (Foundry) | 0 | — |
| Stateful Fuzz (Echidna) | 0 | — |
| Formal Verification (Certora) | 0 | — |
| Fork | 0 | — |

### Gaps

- **No stateful fuzz / invariant tests** — Epoch drip accounting and ERC4626 share math across multi-operation sequences are untested by property-based tools.
- **No fork tests** — Protocol behavior against real EURe token on Gnosis is unverified.
- **No formal verification** — Drip rate calculation and share price monotonicity are mathematically amenable to formal methods.

---

## 6. Developer & Git History

> Repo shape: normal_dev — 5 source-touching commits over 18 days

### Contributors

| Author | Commits | Source Lines (+/-) | % of Source Changes |
|--------|--------:|--------------------|--------------------:|
| daveai | 3 | +382 / -23 | 52.1% |
| Luigy-Lemon | 7 | +351 / -192 | 47.9% |

### Review & Process Signals

| Signal | Value | Assessment |
|--------|-------|------------|
| Unique contributors | 2 | Small team |
| Merge commits | 0 of 10 (0%) | No merge commits — likely no peer review |
| Repo age | 2026-04-09 → 2026-04-27 | 18 days |
| Recent source activity (30d) | 5 commits | Active — late burst before audit |
| Test co-change rate | 100% | Every source commit also modifies test files |

### File Hotspots

| File | Modifications | Note |
|------|-------------:|------|
| src/InterestDispatcher.sol | 4 | Highest churn — all fix-scored commits touch it |
| src/SavingsEURe.sol | 3 | Core vault logic |
| src/interfaces/IInterestDispatcher.sol | 4 | Interface churn suggests design iteration |

### Security-Relevant Commits

**Score** = weighted sum of fix-like signals. **10+ warrants a manual diff.**

| SHA | Date | Subject | Score | Key Signal |
|-----|------|---------|------:|------------|
| 35f6334 | 2026-04-27 | Audit artifacts, x-ray docs, PoC, and receiver/docs hardening | 17 | hardening/validation + adds runtime guards + tightens access control |
| bba8371 | 2026-04-09 | sEURe savings vault — adapted from sDAI-on-Gnosis | 15 | spans 3 security domains + adds guards |
| 962607b | 2026-04-09 | remove old OZ | 15 | 355 lines changed, 3 security domains |
| 6ff3047 | 2026-04-27 | Upgrade to OZ v5.3, custom errors, interfaces, expanded tests | 13 | removes 11 runtime guards + large change (526 lines) |
| 6f38210 | 2026-04-27 | feat: update audit report, harden interfaces and adapter, expand tests | 11 | hardening + spans oracle/signature/accounting |

### Dangerous Area Evolution

| Security Area | Commits | Key Files |
|--------------|--------:|-----------|
| fund_flows | 4 | InterestDispatcher.sol, SavingsEURe.sol |
| oracle_price | 4 | IInterestDispatcher.sol |
| signatures | 3 | SavingsEURe.sol, ISavingsEURe.sol |

### Forked Dependencies

| Library | Path | Upstream | Status | Notes |
|---------|------|----------|--------|-------|
| openzeppelin-contracts | lib/openzeppelin-contracts | OpenZeppelin | Submodule | Standard OZ v5.3; no modifications detected |

### Security Observations

- **Two-dev concentration** — daveai (52%) + Luigy-Lemon (48%) = 100% of source changes.
- **No merge commits** — 0/10; likely no formal code review process.
- **InterestDispatcher.sol is #1 hotspot** — 4 modifications across all fix-scored commits.
- **Late burst before audit** — 5 source-touching commits in 18 days, 4 on 2026-04-27.
- **Guard removal in 6ff3047** — removes 11 runtime guards while upgrading to OZ v5.3; worth manual diff to confirm replacements are equivalent.
- **Fix co-change rate 100%** — every source commit includes test changes (measures co-modification, not coverage).

### Cross-Reference Synthesis

- **InterestDispatcher.sol is #1 in both churn AND attack-surface priority** — owner UUPS authority + fund_flows area → highest-leverage review: `claim()`, `_calculateClaim()`, `_authorizeUpgrade`.
- **Guard removal commit (6ff3047) overlaps fund_flows area** — removed guards in a security domain with 4 commits → elevated risk of missing protection.

---

## X-Ray Verdict

**FRAGILE** — Single EOA controls UUPS upgrades on InterestDispatcher with no timelock; all vault operations depend on receiver correctness. Test coverage is excellent (100% across all metrics) but lacks stateful fuzz and formal verification.

**Structural facts:**
1. 255 nSLOC across 2 contracts (vault + receiver) and 2 interfaces.
2. 1 upgradeable contract (InterestDispatcher, UUPS) with single-EOA upgrade authority, no timelock.
3. 80 tests achieving 100% line/branch/statement/function coverage.
4. 2 developers, 18-day history, no merge commits (no formal review process).
5. 0 stateful fuzz tests, 0 formal verification, 0 fork tests.
