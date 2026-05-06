# Security Audit Report — sEURe (Savings EURe on Gnosis)

**Date**: 2026-05-06
**Auditor**: Automated Security Analysis (Plamen v1.1.8, Thorough mode)
**Scope**: SavingsEURe.sol (135 lines) + InterestDispatcher.sol (177 lines) + interfaces (167 lines)
**Language/Version**: Solidity ^0.8.20
**Build Status**: Compiled successfully (forge build, 85/85 tests pass)
**Static Analysis Status**: Slither — 7 in-scope findings analyzed and triaged

---

## Executive Summary

sEURe is an ERC-4626 yield-bearing vault for Monerium EURe on Gnosis Chain. Users deposit EURe and receive sEURe shares. Yield originates from a Monerium-funded bot that sends EURe to the InterestDispatcher, which drips it into the vault over 5-day epochs. The protocol is adapted from sDAI-on-Gnosis with architectural differences (epoch-based drip vs Pot-based savings rate).

The audit found **no Critical, High, or Medium severity issues**. The codebase is well-structured, follows established patterns (OpenZeppelin ERC4626, UUPS upgradeability, EIP-2612 permits), and includes explicit mitigations for known attack vectors (seed deposit against first-depositor inflation, epoch-based drip against flash-loan yield capture, `_decimalsOffset()` for share math safety).

One Low-severity finding relates to a misleading view function (`vaultAPY()` reporting non-zero when no yield is actually being generated). Four Informational findings document design considerations and theoretical edge cases.

## Summary

| Severity | Count |
|----------|-------|
| Critical | 0 |
| High | 0 |
| Medium | 0 |
| Low | 1 |
| Informational | 4 |

### Components Audited

| Component | Path | Lines | Description |
|----------|------|-------|-------------|
| SavingsEURe | src/SavingsEURe.sol | 135 | ERC4626 vault with EIP-712 permit, 3-decimal offset |
| InterestDispatcher | src/InterestDispatcher.sol | 177 | UUPS-upgradeable epoch-based drip |
| ISavingsEURe | src/interfaces/ISavingsEURe.sol | 70 | Vault + permit interface |
| IInterestDispatcher | src/interfaces/IInterestDispatcher.sol | 97 | Drip receiver interface |

---

## Low Findings

### [L-01] vaultAPY() reports non-zero APY when epoch is exhausted [UNVERIFIED]

**Severity**: Low
**Location**: `InterestDispatcher.sol:145-153`
**Confidence**: MEDIUM (2 agents confirmed, Static Analysis: Y, PoC: SKIPPED)

**Description**:
`vaultAPY()` uses `dripRate` directly without verifying that the current epoch still has remaining balance (`currentEpochBalance > 0`). When partial claims within an epoch fully exhaust `currentEpochBalance`, `dripRate` retains its non-zero value until the next claim triggers a rollover.

```solidity
function vaultAPY() external view override returns (uint256) {
    if (!_isRuntimeInitialized() || dripRate == 0) return 0;
    // ↑ Checks dripRate != 0, but currentEpochBalance could be 0
    uint256 deposits = sEURe.totalAssets();
    if (deposits == 0) return 0;
    uint256 annualYield = (dripRate * 365 days);
    return (1 ether * annualYield) / deposits;
}
```

**Impact**:
Integrators relying on `vaultAPY()` for display purposes see inflated APY values when the epoch is exhausted but not yet rolled over. The NatSpec explicitly warns: *"Integrators MUST NOT use this value as an oracle or risk input without independent validation."* The function returns a misleading non-zero value despite no actual yield being generated.

Additionally, with extremely small deposit-to-yield ratios (e.g., 1 wei deposit with 1 EURe/s drip rate), the returned APY can exceed `1e18` (100%), reaching values like `3.15e43`, which are numerically correct but meaningless for display.

**PoC Result**:
Verification skipped — view function only, no fund impact.

**Recommendation**:
Add a check for `currentEpochBalance == 0` before computing the APY:

```diff
  function vaultAPY() external view override returns (uint256) {
-     if (!_isRuntimeInitialized() || dripRate == 0) return 0;
+     if (!_isRuntimeInitialized() || dripRate == 0 || currentEpochBalance == 0) return 0;
```

---

## Informational Findings

### [I-01] No storage gap in InterestDispatcher limits upgrade safety

**Severity**: Informational
**Location**: `InterestDispatcher.sol` (class definition)
**Confidence**: HIGH

**Description**:
InterestDispatcher inherits from `Initializable` and `UUPSUpgradeable` but does not include a `__gap` storage reservation. The current layout uses slots 0–7 (including inherited OZ slots). Future upgrades must append new variables after slot 7 — removing, reordering, or inserting between existing slots would corrupt storage.

**Impact**:
Standard UUPS pattern. No automated protection against accidental layout violations in future upgrades. Low practical risk — competent upgrade reviews catch this. Adding `uint256[50] private __gap;` in the next upgrade provides a buffer.

**Recommendation**:
Add `uint256[50] private __gap;` at the end of InterestDispatcher's state variables after the next upgrade.

### [I-02] claim() skips state update when balance == 0

**Severity**: Informational
**Location**: `InterestDispatcher.sol:75-96`
**Confidence**: HIGH

**Description**:
When `_balance() == 0`, `claim()` returns 0 without updating `lastClaimTimestamp`. The code comment explicitly documents this as intentional: *"If the receiver has no EURe balance, time is not advanced so future funding remains claimable."*

```solidity
function claim() public override isInitialized returns (uint256 claimed) {
    if (lastClaimTimestamp == block.timestamp) return 0;
    uint256 balance = _balance();
    if (balance > 0) {
        // All state updates happen here
    }
    return claimed; // State NOT updated if balance == 0
}
```

**Impact**:
When balance reappears (bot sends EURe), `unclaimedTime` includes the entire zero-balance period. If `unclaimedTime >= epochLength`, the full `currentEpochBalance` is claimed immediately rather than being gradually dripped. This results in a lump-sum distribution rather than the intended gradual drip.

**Recommendation**:
No change needed — documented as by-design. Consider whether this behavior is desired if the bot's funding schedule is irregular.

### [I-03] Residual EURe capturable when totalSupply returns to zero

**Severity**: Informational
**Location**: `SavingsEURe.sol:55-58`
**Confidence**: HIGH

**Description**:
When all sEURe shares are redeemed (totalSupply = 0) and residual EURe exists in the vault (from rounding dust or claimed interest), the next depositor captures this residual. The `_decimalsOffset() = 3` bounds extraction to negligible amounts (sub-wei per transaction in practice). The deployer seeds the vault with 1 EURe at deployment specifically to prevent totalSupply from reaching zero.

```solidity
function totalAssets() public view override(ERC4626, IERC4626) returns (uint256) {
    if (!interestClaimingEnabled) return super.totalAssets();
    return super.totalAssets() + IInterestDispatcher(interestDispatcher).previewClaimable();
}
```

**Impact**:
Negligible with the 3-decimal offset and 1 EURe seed deposit. Maximum extraction per deposit-withdraw cycle is bounded by rounding dust (~10⁻¹⁵ EURe). As long as the deployer retains their seed shares, totalSupply cannot reach zero.

**Recommendation**:
No change needed — existing mitigations (seed deposit + decimal offset) adequately bound the risk. Consider documenting that the deployer's seed shares should not be redeemed.

### [I-04] Vault incompatible with fee-on-transfer tokens

**Severity**: Informational
**Location**: `SavingsEURe.sol:61-64`
**Confidence**: HIGH

**Description**:
Standard ERC4626 deposit assumes `transferFrom` transfers exactly `assets` tokens. If the underlying EURe token charged a transfer fee, the vault would receive fewer tokens than expected, creating an accounting deficit.

```solidity
function deposit(uint256 assets, address receiver) public override(ERC4626, IERC4626) returns (uint256) {
    _claimInterest();
    return super.deposit(assets, receiver); // ERC4626 assumes exact transfer
}
```

**Impact**:
None with current EURe implementation. Monerium EURe (`0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430`) is a standard ERC20 with no transfer fees. This is a theoretical concern for future EURe contract changes only.

**Recommendation**:
No change needed — EURe is a regulated stablecoin unlikely to add transfer fees. The hardcoded address makes this risk explicit and bounded.

---

## Priority Remediation Order

1. **L-01**: Fix `vaultAPY()` to check `currentEpochBalance == 0` — Low effort, improves integrator experience

The remaining four informational findings (I-01 through I-04) are design considerations that require no immediate action. Review during the next upgrade cycle.

---

## Appendix A: Internal Audit Traceability

| Report ID | Internal Hypothesis | Verification | Agent Sources |
|-----------|-------------------|--------------|---------------|
| L-01 | H-1 (TF-1, DT-2) | CODE-TRACE | Token Flow, Temporal/Econ |
| I-01 | H-2 (SL-1) | CODE-TRACE | Storage Layout |
| I-02 | H-3 (TF-2, TE-1) | CODE-TRACE | Token Flow, Temporal/Econ |
| I-03 | H-4 (ZS-1) | CODE-TRACE | Zero State/Share |
| I-04 | H-5 (DT-1) | CODE-TRACE | Depth Token Flow |

### Excluded Findings

| Internal ID | Severity | Title | Exclusion Reason |
|-------------|----------|-------|-----------------|
| SV-1 | N/A | No signature vulnerability found | REFUTED — standard EIP-2612 + ERC-1271 implementation |
| SC-1 | N/A | Cross-contract semantic consistency verified | REFUTED — no inconsistencies found |
