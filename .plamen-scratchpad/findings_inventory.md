# Findings Inventory

**Total: 7 findings from 1 comprehensive analysis pass**

| # | Finding ID | Agent | Severity | Location | Title | Verdict | Step Execution | Rules Applied |
|---|-----------|-------|----------|----------|-------|---------|---------------|---------------|
| 1 | TR-1 | Breadth | LOW | InterestReceiver.sol:124 | _calculateClaim rollover underflow if balance drops below claimable | CONTESTED | Complete | R2,R8,R10,R11,R14 |
| 2 | SR-1 | Breadth | INFO | InterestReceiver.sol:59-60 | tx.origin-based EOA detection allows any EOA to claim | CONFIRMED | Complete | R6,R13 |
| 3 | SR-2 | Breadth | INFO | InterestReceiver.sol:153-161 | One-step claimer transfer | CONFIRMED | Complete | R9,R13 |
| 4 | TF-1 | Breadth | INFO | InterestReceiver.sol:138 | EURe donation manipulates epoch calculations | CONFIRMED | Complete | R7,R11,R15 |
| 5 | SC-1 | Breadth | INFO | All contracts | No emergency pause mechanism | CONFIRMED | Complete | R13 |
| 6 | EP-1 | Breadth | INFO | SavingsEUReAdapter.sol:25 | Unlimited EURe approval in adapter | CONFIRMED | Complete | R3,R11 |
| 7 | SV-1 | Breadth | INFO | SavingsEURe.sol:30-56 | Permit implementation verified correct | CONFIRMED | Complete | R1,R4 |

## Chain Summary
| Finding ID | Location | Root Cause (1-line) | Verdict | Severity | Precondition Type | Postcondition Type |
|-----------|----------|--------------------|---------|----------|-------------------|-------------------|
| TR-1 | InterestReceiver.sol:124 | balanceOf(this) can decrease below cached currentEpochBalance | CONTESTED | LOW | External token balance reduction | Claim reverts permanently |
| SR-1 | InterestReceiver.sol:59-60 | tx.origin check allows any EOA to call claim | CONFIRMED | INFO | EOA caller | Yield distributed by any EOA |
| SR-2 | InterestReceiver.sol:153-161 | One-step setClaimer no confirmation | CONFIRMED | INFO | Current claimer calls setClaimer | Claimer role transferred |
| TF-1 | InterestReceiver.sol:138 | balanceOf(this) used directly for calculations | CONFIRMED | INFO | EURe transferred to receiver | Epoch parameters affected |
| SC-1 | All contracts | No Ownable/Pausable/upgradeable | CONFIRMED | INFO | Vulnerability discovered | No way to halt |
| EP-1 | SavingsEUReAdapter.sol:25 | max approval in constructor | CONFIRMED | INFO | Adapter holds EURe | Vault can pull max |
| SV-1 | SavingsEURe.sol:30-56 | Permit implementation | CONFIRMED | INFO | None | Correct behavior |

## REFUTED Findings (for Depth Second Opinion)
None.

## CONTESTED Findings (for Depth Priority)
| Finding ID | Agent | External Dep Involved | Worst-Case Severity | Notes |
|-----------|-------|---------------------|--------------------|----|
| TR-1 | Breadth | EURe token (UNVERIFIED) | MEDIUM | Requires EURe token to have balance reduction mechanism |

## Incomplete Analysis Flags
None.

## Rule Application Violations
None — all applicable rules checked per finding.

## Assumption Dependency Audit
| Finding ID | Attack Actor | Actor Trust Level | Within Bounds? | Tag | Original Severity |
|-----------|-------------|-------------------|---------------|-----|-------------------|
| TR-1 | Monerium (EURe issuer) | FULLY_TRUSTED | N/A (balance reduction not documented as bounded) | [ASSUMPTION-DEP: TRUSTED-ACTOR] | LOW → INFO |
| SR-1 | Any EOA | UNTRUSTED | N/A | No tag | INFO |
| SR-2 | Claimer | SEMI_TRUSTED | YES (within bounds — function designed for this) | [ASSUMPTION-DEP: WITHIN-BOUNDS] | INFO |
| TF-1 | Any address | UNTRUSTED | N/A | No tag | INFO |
| SC-1 | N/A | N/A | N/A | No tag | INFO |
| EP-1 | N/A | N/A | N/A | No tag | INFO |
| SV-1 | N/A | N/A | N/A | No tag | INFO |

---

## Side Effect Trace Audit
### Side Effect Trace Summary
| # | External Call | Side Effect | Token Type | Landing | Consuming Code | Handled? | Breadth Coverage | Finding |
|---|---------------|-------------|------------|---------|----------------|----------|------------------|---------|
| 1 | InterestReceiver.claim() → eure.safeTransfer(vault) | EURe transfer to vault | EURe | SavingsEURe vault | vault.totalAssets(), vault.convertToShares() | YES — standard ERC4626 accounting | Covered by TF-1 | None |
| 2 | Adapter._claimHook() → interestReceiver.claim() | Claim state changes | N/A | InterestReceiver | claim() itself | YES — try/catch protects | Covered by design | None |

### Side Effect Findings
None — all external call side effects traced to safe termination.

### Side Effect Coverage Gaps
None — EURe is standard ERC20 with no transfer hooks, no callbacks, no rebasing.

---

## Elevated Signal Audit
| Signal | Tag | Addressed? | Finding ID / Depth Flag |
|--------|-----|-----------|----------------------|
| Fork ancestry: sDAI-on-Gnosis | ELEVATE:FORK_ANCESTRY:sDAI-on-Gnosis | YES | TR-1 (sDAI had related epoch drain bug, fixed) |
| Branch asymmetry in _calculateClaim | ELEVATE:BRANCH_ASYMMETRY | YES | TR-1 (full-epoch zeros, partial-epoch decrements) |
| Single claimer mapping entry | ELEVATE:SINGLE_ENTRY | YES | SR-2 (one-step claimer transfer) |
