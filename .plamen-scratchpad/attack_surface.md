# Attack Surface

## External Dependencies

| Dependency | Type | Address | Interaction Points |
|------------|------|---------|-------------------|
| EURe (Monerium) | ERC-20 permissioned stablecoin | 0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430 | balanceOf, transferFrom, approve, safeTransferFrom, safeTransfer |
| SavingsEURe | ERC4626 vault | deployed address | deposit, mint, withdraw, redeem, previewMint, maxWithdraw, maxRedeem, balanceOf, totalAssets |

## Token Flow Matrix

| Token | Type | Entry Functions | State Tracking | Accounting Affected? | Unsolicited Transfer? | Side-Effect? | Return-Value? |
|-------|------|----------------|---------------|---------------------|-----------------------|--------------|---------------|
| EURe | ERC-20 | deposit, mint (via adapter) | InterestReceiver._balance(), vault totalAssets() | YES — _balance() is balanceOf(this), totalAssets() is balanceOf(vault) | YES — direct transfer to receiver or vault | YES — claim() transfers to vault, increasing share price | NO |

## Attack Vectors

### 1. EURe Unsolicited Transfers
- **To InterestReceiver**: Direct EURe transfer increases `_balance()`, affecting claim calculations. Can manipulate epoch rollover rates.
- **To SavingsEURe vault**: Direct EURe transfer increases `totalAssets()`, inflating share price. `_decimalsOffset()=3` mitigates first-depositor attack but not subsequent donation-based manipulation.

### 2. Claim Timing Manipulation
- Any EOA can call `claim()` at any time. Strategic timing can:
  - Front-run deposits to claim before deposit, then deposit at higher share price
  - Delay claims to accumulate larger drip, then claim + withdraw in same tx
  - Same-block claim returns 0 (`lastClaimTimestamp == block.timestamp` guard)

### 3. Adapter Claim Hook
- `_claimHook()` uses `try/catch` — claim failures silently ignored
- Only triggers for EOAs (`msg.sender == tx.origin`) — contract wallets never trigger
- Safe multisigs, ERC-4337 wallets excluded from auto-claim

### 4. InterestReceiver Epoch Edge Cases
- Full drain → dripRate=0, currentEpochBalance=0. Epoch revival requires two claims.
- `unclaimedTime >= epochLength` → claims entire currentEpochBalance regardless of actual balance
- If `balance < claimable` in epoch rollover path: `remaining = balance - claimable` could underflow if balance tracking drifts from actual balance

### 5. Monerium Blocklist Risk
- EURe issuer can freeze vault or receiver addresses
- No code-level mitigation — inherent to permissioned token

### 6. setClaimer One-Step Transfer
- No two-step confirmation — typo or malicious claimer permanently locks contract claimer role
- Mitigated by: zero-address check, claimer must call setClaimer themselves

## Signal Elevation Tags

- `[ELEVATE:FORK_ANCESTRY:sDAI-on-Gnosis]` — Verify known sDAI vulnerability classes addressed. CHANGES-FROM-SDAI.md documents 3 bug fixes applied.
- `[ELEVATE:BRANCH_ASYMMETRY]` — _calculateClaim has asymmetric branches: full-epoch path zeros currentEpochBalance, partial-epoch path decrements. Verify state completeness in rollover logic.
- `[ELEVATE:SINGLE_ENTRY]` — InterestReceiver has single claimer mapping entry. setClaimer is one-step, no pending confirmation.

## Production Verification Status
- **EURe (0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430)**: UNVERIFIED — production address hardcoded. No on-chain verification performed. Analysis agents MUST NOT use mock behavior as evidence to REFUTE findings.
