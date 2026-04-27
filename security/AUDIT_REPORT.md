# Security Audit Report — sEURe-on-Gnosis

**Date**: 2026-04-27
**Auditor**: Automated Security Analysis (Plamen v1.1.8, Thorough mode), merged with Plamen v1.0.5 baseline notes
**Scope**: 3 in-scope contracts (SavingsEURe, InterestReceiver, SavingsEUReAdapter) + 3 interfaces
**Language/Version**: Solidity ^0.8.20, Foundry
**Build Status**: Compiled successfully
**Static Analysis Status**: Slither — available, findings reviewed
**Fork ancestry**: sDAI-on-Gnosis

---

## Executive Summary

sEURe is an ERC-4626 vault for EURe on Gnosis Chain, depositing user EURe for sEURe shares that appreciate through epoch-based yield dripping. The protocol is minimal by design — no admin, no pause, no oracle, no external integrations beyond the EURe token. The only privileged role (claimer) has extremely limited scope.

The remediation review invalidated the Medium impact originally assigned to the state-before-transfer pattern: if `eure.safeTransfer()` reverts, the full `claim()` call reverts and prior epoch-state writes roll back. The remaining actionable code issue was adapter observability when opportunistic claims fail; this has been remediated with `ClaimFailed(bytes reason)`. The remaining Low findings are accepted economic or operational tradeoffs documented for integrators.

No Critical or High severity issues were found. The protocol benefits from a clean design with minimal attack surface, comprehensive test coverage, and OpenZeppelin v5.3's built-in protections.

---

## Summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 4 |
| Informational | 2 |

### Components Audited

| Component | Path | Lines | Description |
|----------|------|-------|-------------|
| SavingsEURe | `src/SavingsEURe.sol` | 68 | ERC-4626 vault wrapping EURe with permit support |
| InterestReceiver | `src/InterestReceiver.sol` | 166 | Epoch-based EURe yield drip into the vault |
| SavingsEUReAdapter | `src/periphery/SavingsEUReAdapter.sol` | 78 | User-facing adapter bundling vault ops with claims |
| ISavingsEURe | `src/interfaces/ISavingsEURe.sol` | 49 | Vault interface with permit |
| IInterestReceiver | `src/interfaces/IInterestReceiver.sol` | 96 | Drip interface |
| ISavingsEUReAdapter | `src/interfaces/ISavingsEUReAdapter.sol` | 52 | Adapter interface |

---

## Reclassified Findings

### [M-01] Claim State Committed Before EURe Transfer [RECLASSIFIED]

**Severity**: Informational / invalidated impact
**Location**: `InterestReceiver.sol:88-93`, `SavingsEUReAdapter.sol:36-37`
**Status**: Regression-tested; no production code change required in `InterestReceiver.claim()`

**Description**:

`InterestReceiver.claim()` writes four storage variables (`currentEpochBalance`, `dripRate`, `nextClaimEpoch`, `lastClaimTimestamp`) before executing `eure.safeTransfer()`. The original report treated those writes as permanently committed if the transfer reverts.

That impact is not reproducible under EVM revert semantics. If `eure.safeTransfer()` reverts, the entire `claim()` call reverts and all prior writes from that call roll back. The adapter `try/catch` catches the failed external call at the caller boundary, but it does not preserve partial callee state.

```solidity
// InterestReceiver.sol:88-93 — state before transfer
currentEpochBalance = nextEpochBalance;
dripRate = nextDripRate;
nextClaimEpoch = nextEpochTimestamp;
lastClaimTimestamp = block.timestamp;

eure.safeTransfer(address(sEURe), claimed);  // if this reverts, state above rolls back
```

```solidity
// SavingsEUReAdapter.sol — remediated observability
try interestReceiver.claim() {}
catch (bytes memory reason) {
    emit ClaimFailed(reason);
}
```

**Impact**:

The permanent-loss impact is invalid. The real impact was operational observability: adapter-triggered user operations could continue after a failed opportunistic claim without an on-chain signal. This is covered by L-04 and remediated with `ClaimFailed(bytes reason)`.

**Regression coverage**:

- `testClaim_transferRevertRollsBackEpochState`
- `testDeposit_claimRevertLeavesReceiverStateUnchangedAndDeposits`

**Recommendation**:

No `InterestReceiver` state ordering change is required. Keep the current checks-effects-interactions ordering and retain the regression tests to prevent the false-positive impact from returning to the report.

---

## Low Findings

### [L-01] Donation-Enabled MEV and APY Manipulation [VERIFIED]

**Severity**: Low
**Location**: `InterestReceiver.sol:128-136`, `InterestReceiver.sol:141-143`
**Confidence**: HIGH (3 agents confirmed, Static Analysis: Y, PoC: PASS)

**Description**:

`InterestReceiver._balance()` reads `eure.balanceOf(address(this))` directly. Any address can transfer EURe to the receiver, and at epoch rollover, `remaining = balance - claimable` is used as the next epoch's parameters. This inflates `dripRate` and `currentEpochBalance` for the next epoch.

Additionally, `vaultAPY()` computes `1e18 * (dripRate * 365 days) / totalAssets`. An inflated `dripRate` produces an artificially high APY.

Between claims, yield accumulates in the receiver but is not reflected in the share price (`totalAssets` only counts vault balance). A user who deposits right before a `claim()` gets shares at the stale lower price, capturing disproportionate yield.

**Impact**:

All sEURe holders benefit proportionally from donations — no direct value extraction. However, `vaultAPY()` can be manipulated to mislead downstream DeFi integrations. The MEV vector allows front-running claims to capture yield that should be pro-rata.

**Recommendation**:

Document the behavior rather than changing accounting. Direct receiver funding is part of the yield model, and switching to internal accounting would require a new funding notification flow. `vaultAPY()` NatSpec now warns integrators that it is an instantaneous display metric, not an oracle or risk input. Regression coverage: `testVaultAPY_receiverDonationOnlyAffectsNextEpochAndAccruesToHolders`.

---

### [L-02] Single-Step Claimer Transfer with No Delay [VERIFIED]

**Severity**: Low
**Location**: `InterestReceiver.sol:157-165`
**Confidence**: HIGH (1 agent confirmed, PoC: PASS)

**Description**:

`setClaimer()` transfers the claimer role in one step with no timelock, no two-step handoff, and no delay. A compromised claimer key can instantly transfer the role to any address (excluding zero address).

**Impact**:

The claimer role is extremely limited — it can only call `claim()` and `setClaimer()`. No user funds are at risk. The maximum damage from a compromised key is strategic claim timing (already covered in L-01) or transferring the role to an inactive address. EOAs can always call `claim()` directly, providing a decentralized fallback.

**Recommendation**:

Accepted as an intentional one-step handoff. The adapter contract cannot accept a two-step role transfer, the role cannot move funds, and EOAs can always call `claim()` directly. Operational guidance is documented in `README.md`.

---

### [L-03] Return-to-Zero Residual Yield Capture [VERIFIED]

**Severity**: Low
**Location**: `SavingsEURe.sol:24-26`
**Confidence**: MEDIUM (1 agent confirmed, PoC: PASS)

**Description**:

If all users exit the vault (`totalSupply -> 0`) while yield continues to drip from InterestReceiver, residual EURe accumulates in the vault. The first new depositor captures this residual yield through share calculation. With `_decimalsOffset() = 3` providing 1000 virtual shares, the capture is bounded by the virtual offset.

**Impact**:

At normal TVL, the impact is negligible. Only exploitable if all users exit and significant residual yield remains.

**Recommendation**:

Document as expected ERC-4626 virtual-offset behavior rather than adding an admin or keeper sweep role. Regression coverage: `testZeroSupplyResidualAssetsAreDilutedByVirtualOffset`.

---

### [L-04] Adapter Silently Ignores Claim Failures [VERIFIED]

**Severity**: Low
**Location**: `SavingsEUReAdapter.sol:36-37`
**Confidence**: HIGH (2 agents confirmed, PoC: PASS)
**Status**: Remediated

**Description**:

The adapter's `_claimHook()` calls `interestReceiver.claim()` inside a `try/catch`. Before remediation, the catch path silently swallowed all failures. A failed `claim()` does not permanently commit receiver state, but without an event operators and indexers had no signal that opportunistic yield claiming was failing.

**Impact**:

Users' deposits and withdrawals succeed normally. The silent failure made it difficult for operators to detect when yield was not being claimed.

**Recommendation**:

Resolved by emitting the raw revert data in the catch block:

```diff
 function _claimHook() internal {
     if (msg.sender == tx.origin) {
-        try interestReceiver.claim() {} catch {}
+        try interestReceiver.claim() {}
+        catch (bytes memory reason) {
+            emit ClaimFailed(reason);
+        }
     }
 }
```

Regression coverage: `testDeposit_claimRevertLeavesReceiverStateUnchangedAndDeposits`.

---

## Informational Findings

### [I-01] Contract Callers Cannot Trigger Claims

**Severity**: Informational
**Location**: `SavingsEUReAdapter.sol:35`

**Description**:

`_claimHook()` checks `msg.sender == tx.origin`, preventing contract callers from triggering claims through the adapter. This is documented as intentional ("only EOAs are able to claim interest") but limits DeFi composability for protocols that interact through the adapter.

**Impact**: Contracts (aggregators, other DeFi protocols) using the adapter skip the claim step. Yield still accumulates in the receiver and can be claimed by EOAs or the designated claimer directly.

**Recommendation**: Document this as a known limitation for integrators. Contract callers can use direct vault flows, rely on public EOA/keeper claims, or coordinate with the designated claimer path. Regression coverage: `testDeposit_ContractCallerSkipsClaimHook`.

---

### [I-02] Baseline TR-1 Balance Reduction Finding [MITIGATED]

**Severity**: Informational after mitigation
**Location**: `InterestReceiver.sol:123-128`

The baseline audit identified a potential claim failure if EURe balance is externally reduced below computed claimable amount. Current code caps `claimable` to the receiver's live balance before transfer and before rollover accounting:

```solidity
if (claimable > balance) {
    claimable = balance;
}
```

Regression coverage includes `test_TR1_balanceReductionCapsEpochRolloverClaim`, `test_TR1_balanceReductionCapsMidEpochClaim`, `test_TR1_noUnderflowWhenBalanceSufficient`, `test_TR1_adapterDepositGraceful`, and `test_edge_epochBoundaryExactTimestamp`.

---

## Baseline Observations

- **tx.origin-based EOA detection**: Any EOA can call `claim()` by design; contract callers must be the configured `claimer`.
- **No emergency pause mechanism**: The contracts are immutable and intentionally omit owner, pause, and upgrade paths.
- **Unlimited EURe approval in adapter**: The adapter approves the immutable vault for `type(uint256).max`; the adapter should only hold EURe transiently.
- **Permit implementation**: Uses OpenZeppelin `SignatureChecker`, `_hashTypedDataV4`, and `Nonces`; EOA and ERC-1271 paths are covered by tests.

---

## Priority Remediation Order

1. **M-01**: Reclassified; retain rollback regression tests.
2. **L-04**: Add `ClaimFailed(bytes reason)` event to adapter catch block — completed.
3. **L-01**: Document donation behavior and `vaultAPY()` limitations — completed.
4. **L-02**: Document one-step claimer transfer as accepted design — completed.
5. **L-03**: Document residual zero-supply behavior and retain quantification test — completed.
6. **I-01**: Document EOA-only claim as integration constraint — completed.

---

## Appendix A: Internal Audit Traceability

| Report ID | Internal Hypothesis | Verification | Agent Sources |
|-----------|-------------------|--------------|---------------|
| M-01 | H-1 | RECLASSIFIED | Semi-Trusted Roles, Token Flow, Multi-Step Ops |
| L-01 | H-2 | CONFIRMED | Token Flow, Economic Design, Semi-Trusted Roles |
| L-02 | H-3 | CONFIRMED | Semi-Trusted Roles |
| L-03 | H-5 | CONFIRMED | Zero State |
| L-04 | H-1 (adapter) | CONFIRMED / REMEDIATED | Multi-Step Ops |
| I-01 | H-4 | CONFIRMED | Multi-Step Ops |
| I-02 | TR-1 | MITIGATED | Baseline audit, PoC_TR1 |

---
