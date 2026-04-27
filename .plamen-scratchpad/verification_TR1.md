# Verification Results

## TR-1: _calculateClaim Rollover Underflow

### PoC Test: test_TR1_balanceReductionCausesUnderflow
**Status**: PASS (bug confirmed)
**Evidence**: [EXECUTED-POC] — Forge test demonstrates arithmetic underflow when `balanceOf(receiver) < currentEpochBalance`

### PoC Test: test_TR1_noUnderflowWhenBalanceSufficient
**Status**: PASS (confirms normal operation)
**Evidence**: [EXECUTED-POC] — Normal claim succeeds when balance >= currentEpochBalance

### PoC Test: test_TR1_adapterDepositGraceful
**Status**: PASS (confirms graceful handling)
**Evidence**: [EXECUTED-POC] — Adapter deposit succeeds even when claim reverts due to underflow

### PoC Test: test_edge_epochBoundaryExactTimestamp
**Status**: PASS (confirms epoch boundary correctness)
**Evidence**: [EXECUTED-POC] — Claim at exact nextClaimEpoch works correctly

### Updated Verdict: CONFIRMED with [EXECUTED-POC]
**Severity**: LOW (upgraded from CONTESTED — bug is confirmed, but trigger requires trusted actor)

---

## All Other Findings (SR-1, SR-2, TF-1, SC-1, EP-1, SV-1)
**Status**: CONFIRMED (by design / documented)
**Verification**: Code review + existing test suite (76/76 pass)
