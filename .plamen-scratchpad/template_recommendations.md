# Template Recommendations

## Recommended Analysis Templates

### Template: SEMI_TRUSTED_ROLES
**Trigger**: SEMI_TRUSTED_ROLE flag — claimer role with isClaimer modifier, tx.origin==msg.sender check
**Relevance**: The claimer role controls who can call claim() from contracts. tx.origin check is unusual — any EOA can claim. Claimer can be transferred one-step.
**Instantiation Parameters**:
- role_holder: claimer (initially deployer, then adapter)
- role_modifier: isClaimer (tx.origin==msg.sender || msg.sender==claimer)
- protected_functions: claim(), initialize(), setClaimer()
- transfer_mechanism: one-step setClaimer()
**Key Questions**:
1. Can tx.origin check be exploited in Gnosis Chain context?
2. Is one-step claimer transfer safe for immutable contract?

### Template: TOKEN_FLOW_TRACING
**Trigger**: BALANCE_DEPENDENT flag — InterestReceiver uses eure.balanceOf(address(this)) for all calculations
**Relevance**: EURe balance of receiver drives claim calculations, epoch rollover, drip rate. Unsolicited transfers directly manipulate this.
**Instantiation Parameters**:
- tracked_token: EURe (0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430)
- tracking_mechanism: balanceOf(address(this)) — no internal accounting
- entry_points: claim(), initialize(), vaultAPY()
- donation_possible: true (anyone can transfer EURe to receiver or vault)
**Key Questions**:
1. Can EURe donation to receiver before epoch rollover manipulate dripRate?
2. Can EURe donation to vault inflate share price and steal from depositors?

### Template: TEMPORAL_PARAMETER_STALENESS
**Trigger**: TEMPORAL flag — epoch-based drip system with cached parameters (dripRate, currentEpochBalance, nextClaimEpoch)
**Relevance**: Parameters cached at epoch start, recalculated on claim. If claims are delayed, parameters become stale. If balance changes between epoch start and claim, rollover math may be incorrect.
**Instantiation Parameters**:
- cached_params: dripRate, currentEpochBalance, nextClaimEpoch, lastClaimTimestamp
- staleness_window: epochLength (5 days)
- recalculation_trigger: claim() when block.timestamp > nextClaimEpoch
- balance_dependency: eure.balanceOf(address(this)) — can change without claim
**Key Questions**:
1. What happens if balance drops below claimable during a claim?
2. Can delayed claims + balance changes cause epoch rollover miscalculation?

### Template: SHARE_ALLOCATION_FAIRNESS
**Trigger**: SHARE_ALLOCATION flag — ERC4626 shares with decimalsOffset=3
**Relevance**: Share price changes when EURe drips into vault. Depositors before claim get different rate than after. First-depositor protection via decimalsOffset.
**Instantiation Parameters**:
- share_mechanism: ERC4626 with _decimalsOffset()=3
- price_change_source: InterestReceiver.claim() → EURe transfer to vault → totalAssets increase
- first_depositor_protection: decimalsOffset=3 (1000x virtual shares)
**Key Questions**:
1. Is decimalsOffset=3 sufficient for realistic deposit sizes?
2. Can claim timing be used to front-run deposits for share price manipulation?

### Template: ECONOMIC_DESIGN_AUDIT
**Trigger**: MONETARY_PARAMETER flag — dripRate, epochLength, MIN_EPOCH_BALANCE
**Relevance**: Drip rate is set from balance/epochLength. No cap on drip rate. APY is uncapped and depends on funded balance.
**Instantiation Parameters**:
- monetary_params: dripRate (balance/epochLength), MIN_EPOCH_BALANCE (100 ether), epochLength (5 days)
- rate_setter: claim() recalculates automatically
- apy_formula: (dripRate * 365 days * 1e18) / totalAssets
**Key Questions**:
1. What's the maximum APY achievable with adversarial EURe funding?
2. Can epoch revival mechanism be exploited for abnormal yield?

### Template: EXTERNAL_PRECONDITION_AUDIT
**Trigger**: External interactions detected — EURe token (permissioned, blocklistable), SavingsEURe vault
**Relevance**: EURe is a permissioned token with blocklist capability. If vault or receiver is blocklisted, all operations revert.
**Instantiation Parameters**:
- external_deps: EURe (0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430), SavingsEURe vault
- failure_modes: blocklist (permanent freeze), transfer revert, approve failure
- precondition_functions: safeTransferFrom (adapter), safeTransfer (receiver), deposit (vault)
**Key Questions**:
1. What happens if EURe is blocklisted after deposits but before withdrawal?
2. Are all external calls properly guarded against revert propagation?

### Template: ZERO_STATE_RETURN
**Trigger**: ERC4626 vault — first depositor edge case
**Relevance**: With decimalsOffset=3, first deposit gets shares = assets * 10^3. Need to verify this is safe.
**Instantiation Parameters**:
- vault: SavingsEURe (ERC4626 with decimalsOffset=3)
- first_deposit_shares: assets * 10^(decimalsOffset) = assets * 1000
- total_assets_before_first: 0
**Key Questions**:
1. Is the inflation attack protection sufficient with decimalsOffset=3?

### Template: VERIFICATION_PROTOCOL
**Trigger**: Always required for verifiers
**Relevance**: Standard PoC verification template

---

## BINDING MANIFEST

| Template | Pattern Trigger | Required? | Reason |
|----------|-----------------|-----------|--------|
| SEMI_TRUSTED_ROLES | SEMI_TRUSTED_ROLE flag | YES | claimer role with tx.origin check |
| TOKEN_FLOW_TRACING | BALANCE_DEPENDENT flag | YES | balanceOf(this) drives all InterestReceiver calculations |
| TEMPORAL_PARAMETER_STALENESS | TEMPORAL flag | YES | epoch-based cached drip params |
| SHARE_ALLOCATION_FAIRNESS | SHARE_ALLOCATION flag | YES | ERC4626 shares with yield-driven price changes |
| ECONOMIC_DESIGN_AUDIT | MONETARY_PARAMETER flag | YES | dripRate, epochLength, MIN_EPOCH_BALANCE |
| EXTERNAL_PRECONDITION_AUDIT | External interactions detected | YES | EURe permissioned token, vault interactions |
| ZERO_STATE_RETURN | ERC4626/first-depositor pattern | YES | decimalsOffset=3 inflation protection |
| FLASH_LOAN_INTERACTION | FLASH_LOAN flag | NO | No flash loan patterns detected |
| ORACLE_ANALYSIS | ORACLE flag | NO | No oracle usage |
| CROSS_CHAIN_TIMING | CROSS_CHAIN flag | NO | No cross-chain component |
| MIGRATION_ANALYSIS | MIGRATION flag | NO | No migration patterns (fork ancestry documented) |
| EVENT_CORRECTNESS | >15 events | NO | Only 7 events total |
| STAKING_RECEIPT_TOKENS | Receipt token detected | NO | sEURe is ERC4626 shares, not staking receipt |

### Niche Agents

| Niche Agent | Trigger | Required? | Reason |
|-------------|---------|-----------|--------|
| EVENT_COMPLETENESS | MISSING_EVENT flag | NO | All state-changing functions emit events |
| SIGNATURE_VERIFICATION_AUDIT | HAS_SIGNATURES flag | YES | permit() uses SignatureChecker + EIP712 — need to verify malleability, replay, edge cases |
| SEMANTIC_CONSISTENCY_AUDIT | HAS_MULTI_CONTRACT flag | YES | 3 contracts share EURe address and vault reference — verify consistent behavior across contract boundaries |

### Manifest Summary
- **Total Required Breadth Agents**: 7
- **Total Required Niche Agents**: 2
- **Total Optional Agents**: 5
- **HARD GATE**: Orchestrator MUST spawn agent for each REQUIRED template AND each REQUIRED niche agent

## Injectable Skills
None recommended — no complex multi-phase operations, no governance, no bridge timing.
