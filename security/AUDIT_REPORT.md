# sEURe Savings Vault — Security Audit Report

**Project**: sEURe-on-Gnosis
**Date**: 2026-04-27
**Auditor**: Plamen v1.0.5 (Thorough mode)
**Mode**: Thorough — iterative depth, PoC verification, all severities
**Scope**: Full project (6 Solidity files, ~505 lines)
**Fork ancestry**: sDAI-on-Gnosis (3 bug fixes + 10 security improvements applied)

---

## Executive Summary

The sEURe savings vault is a well-designed fork of the audited sDAI-on-Gnosis protocol, adapted for Monerium's EURe stablecoin on Gnosis Chain. The codebase benefits from documented bug fixes and security hardening applied during the fork. The architecture is simple and conservative — an ERC4626 vault with epoch-based yield dripping, an adapter for opportunistic claiming, and no external DeFi dependencies.

**One LOW-severity finding was confirmed with an executed PoC and mitigated**: a potential claim failure in the InterestReceiver if the EURe token balance decreases through non-protocol mechanisms (e.g., Monerium exercising balance reduction capabilities). The fix caps computed claims to the receiver's live EURe balance before transfer and rollover accounting.

All other observations are informational — documented design choices or expected behaviors.

**Overall assessment**: The codebase is well-structured, well-tested (85 tests, 100% pass rate including 8 fuzz tests), and incorporates lessons learned from the sDAI deployment.

---

## Findings Summary

| # | ID | Severity | Title | Location | Status |
|---|----|----------|-------|----------|--------|
| 1 | TR-1 | LOW | _calculateClaim claim failure if EURe balance reduced externally | InterestReceiver.sol:124 | Mitigated |
| 2 | SR-1 | INFO | tx.origin-based EOA detection allows any EOA to claim | InterestReceiver.sol:59-60 | By Design |
| 3 | SR-2 | INFO | One-step claimer transfer — no confirmation step | InterestReceiver.sol:153-161 | Documented Risk |
| 4 | TF-1 | INFO | EURe donation to receiver manipulates epoch parameters | InterestReceiver.sol:138 | Expected |
| 5 | SC-1 | INFO | No emergency pause mechanism | All contracts | Design Choice |
| 6 | EP-1 | INFO | Unlimited EURe approval to vault in adapter | SavingsEUReAdapter.sol:25 | Standard Pattern |
| 7 | SV-1 | INFO | Permit implementation verified correct | SavingsEURe.sol:30-56 | Verified |

---

## Findings Detail

### [TR-1] LOW — _calculateClaim Claim Failure If EURe Balance Reduced Externally

**Location**: `InterestReceiver.sol:124`
**Severity**: LOW
**Status**: Mitigated with regression tests
**Assumption Dependency**: `[ASSUMPTION-DEP: TRUSTED-ACTOR]` — requires EURe issuer (Monerium) to have balance reduction capability

#### Description

The `_calculateClaim` function computes `remaining = balance - claimable` during epoch rollover. The `balance` value is a fresh `eure.balanceOf(address(this))` reading, while `claimable` is derived from `currentEpochBalance` — a state variable set at epoch start.

If the actual EURe balance of the receiver decreases below the computed `claimable` amount between epoch start and a later claim (e.g., through Monerium exercising a burn or seizure mechanism on the receiver address), claims can fail. At rollover this caused an arithmetic underflow in `balance - claimable`; mid-epoch it could also make `safeTransfer(claimed)` revert because the receiver no longer held enough EURe.

#### Impact

- **Direct**: Subsequent `claim()` calls could revert while live balance remained below computed claimable amount
- **Yield distribution**: Could halt until receiver balance was replenished above the computed claimable amount
- **User operations**: Unaffected — adapter's try/catch gracefully absorbs the revert
- **Funds at risk**: EURe held by receiver could be temporarily stranded from direct claiming

#### PoC

```solidity
// test/PoC_TR1.t.sol — test_TR1_balanceReductionCapsEpochRolloverClaim
// 1. Initialize receiver with 10001 EURe
// 2. Skip past epoch end
// 3. Reduce receiver balance to currentEpochBalance / 2
// 4. claim() succeeds and transfers only the available receiver balance
```

Five PoC/regression tests all pass:
- `test_TR1_balanceReductionCapsEpochRolloverClaim` — confirms rollover claims are capped to live balance
- `test_TR1_balanceReductionCapsMidEpochClaim` — confirms mid-epoch claims are capped before transfer
- `test_TR1_noUnderflowWhenBalanceSufficient` — confirms normal operation
- `test_TR1_adapterDepositGraceful` — confirms adapter continues working
- `test_edge_epochBoundaryExactTimestamp` — confirms epoch boundary correctness

#### Resolution

`InterestReceiver._calculateClaim` now caps `claimable` to the receiver's live EURe balance before transfer and before rollover accounting:

```solidity
if (claimable > balance) {
    claimable = balance;
}
uint256 remaining = balance - claimable;
```

This ensures the function degrades gracefully by claiming available balance rather than reverting. Regression coverage includes both the epoch rollover underflow path and the mid-epoch transfer-revert path.

#### Likelihood Assessment

- **EURe blocklisting**: Prevents transfers but does NOT reduce balanceOf → causes different failure mode (safeTransfer reverts, rolling back state correctly)
- **EURe balance reduction**: Would require Monerium to exercise undocumented capabilities → LOW likelihood
- **Worst-case severity without mitigation**: MEDIUM (permanent yield halt)

---

### [SR-1] INFO — tx.origin-Based EOA Detection

**Location**: `InterestReceiver.sol:59-60`

The `isClaimer` modifier uses `tx.origin == msg.sender` to detect EOAs, allowing any EOA to call `claim()`. This is inherited from sDAI and documented as intentional — it prevents contract-based flash loan attacks on claim timing while allowing any EOA to trigger yield distribution. The `claimer` role is only meaningful for contract callers (the adapter).

---

### [SR-2] INFO — One-Step Claimer Transfer

**Location**: `InterestReceiver.sol:153-161`

`setClaimer()` is one-step with no pending confirmation. A typo permanently locks the claimer role on an immutable contract. Mitigated by: (1) zero-address check, (2) only current claimer can call, (3) EOAs can still claim directly regardless. Documented as intentional — the adapter contract cannot accept a two-step handoff.

---

### [TF-1] INFO — EURe Donation Manipulates Epoch Parameters

**Location**: `InterestReceiver.sol:138`

`_balance()` uses `eure.balanceOf(address(this))` directly. EURe donations to the receiver affect epoch calculations. All donation vectors benefit all depositors equally (higher yield) — no profitable attack identified. The cost of attack equals the donated amount with no extraction mechanism.

---

### [SC-1] INFO — No Emergency Pause Mechanism

All three contracts are immutable with no Ownable, Pausable, or upgradeable patterns. If a vulnerability is discovered post-deployment, there is no way to halt operations. This is consistent with the project's immutable contract design philosophy.

---

### [EP-1] INFO — Unlimited EURe Approval in Adapter

**Location**: `SavingsEUReAdapter.sol:25`

`eure.approve(savingsEuRe_, type(uint256).max)` in the constructor. The adapter only holds EURe transiently during deposit operations — no persistent balance at risk. Standard pattern for ERC4626 adapters.

---

### [SV-1] INFO — Permit Implementation Verified Correct

**Location**: `SavingsEURe.sol:30-56`

The permit implementation uses OpenZeppelin's `SignatureChecker.isValidSignatureNow` (supports both EOA ECDSA and ERC1271 contract wallets), `_hashTypedDataV4` for EIP712 domain separation, `_useNonce` for replay protection, and properly validates deadline and zero-address owner. No malleability issues (high-s rejected by OZ ECDSA internally). No duplicate event emission (fixed from sDAI).

---

## Codebase Quality Assessment

| Metric | Assessment |
|--------|-----------|
| Test coverage | Excellent — 85 tests, 8 fuzz tests @ 10k runs, all edge cases covered |
| Documentation | Excellent — NatSpec on all interfaces, CHANGES-FROM-SDAI.md documents every change |
| Dependencies | Minimal — only OpenZeppelin v5.3.0 (tagged, audited) |
| Architecture | Simple, conservative — no proxy, no upgrade, no external DeFi |
| Static analysis | Clean — Slither finds 0 project-specific issues |
| Fork provenance | Well-documented — 3 bug fixes + 10 security improvements from sDAI |

---

## Known Accepted Risks (from CHANGES-FROM-SDAI.md)

1. **EURe blocklist** — Monerium can freeze addresses, locking deposits. No code mitigation for immutable contracts.
2. **Any EOA can claim** — Intentional. Prevents contract flash loan attacks while allowing broad yield distribution.
3. **Epoch revival requires two claims** — After full drain, first claim sets up new epoch with 0 payout. Self-healing.
4. **Contract wallets don't trigger claims** — Safe multisigs and ERC-4337 wallets excluded from adapter's auto-claim due to `tx.origin` check. Yield depends on EOA interactions or external keepers.

---

## Artifacts

All analysis artifacts are in `.plamen-scratchpad/`. The PoC test file is at `test/PoC_TR1.t.sol`.

**This audit was performed in Thorough mode with iterative depth analysis and executed PoC verification.**
