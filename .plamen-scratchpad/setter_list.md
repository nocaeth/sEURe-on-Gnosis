# Setter List

## Admin/Setter Functions

| Setter | Contract | Param Modified | Access Control | Emits Event? | Event Name |
|--------|----------|---------------|----------------|-------------|------------|
| `setClaimer(address)` | InterestReceiver | claimer | isClaimer (caller must be current claimer) | YES | ClaimerUpdated |
| `initialize()` | InterestReceiver | dripRate, currentEpochBalance, lastClaimTimestamp, nextClaimEpoch | initializer + msg.sender==claimer | YES | Initialized |

## State-Modifying Functions

| Function | Contract | State Modified | Access | Emits? |
|----------|----------|---------------|--------|--------|
| `claim()` | InterestReceiver | dripRate, currentEpochBalance, nextClaimEpoch, lastClaimTimestamp | isInitialized + isClaimer | YES (Claimed) |
| `deposit(assets, receiver)` | SavingsEURe (ERC4626) | shares minted | permissionless | YES (Deposit) |
| `mint(shares, receiver)` | SavingsEURe (ERC4626) | shares minted | permissionless | YES (Deposit) |
| `withdraw(assets, receiver, owner)` | SavingsEURe (ERC4626) | shares burned | owner or approved | YES (Withdraw) |
| `redeem(shares, receiver, owner)` | SavingsEURe (ERC4626) | shares burned | owner or approved | YES (Withdraw) |
| `permit(owner, spender, value, deadline, sig)` | SavingsEURe | allowance | signature-based | YES (Approval) |
| `deposit(assets, receiver)` | SavingsEUReAdapter | EURe transfer + vault deposit | permissionless | NO (vault emits) |
| `mint(shares, receiver)` | SavingsEUReAdapter | EURe transfer + vault mint | permissionless | NO (vault emits) |
| `withdraw(assets, receiver)` | SavingsEUReAdapter | vault withdraw | permissionless | NO (vault emits) |
| `redeem(shares, receiver)` | SavingsEUReAdapter | vault redeem | permissionless | NO (vault emits) |
| `redeemAll(receiver)` | SavingsEUReAdapter | vault redeem | permissionless | NO (vault emits) |

## Setter x Emit Cross-Reference

| Setter | Emits Event? | Missing? |
|-------|-------------|----------|
| setClaimer | YES (ClaimerUpdated) | No |
| initialize | YES (Initialized) | No |
| claim | YES (Claimed) | No |

No SILENT SETTERs detected — all state-changing functions emit events.
