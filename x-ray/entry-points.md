# Entry Point Map

> sEURe | 14 entry points | 12 permissionless | 2 role-gated | 0 admin-only

---

## Protocol Flow Paths

### Setup (Deployer → Claimer)

`InterestReceiver.constructor()` → [fund with ≥100 EURe] ◄── external → `InterestReceiver.initialize()` → `SavingsEUReAdapter.constructor()` → `InterestReceiver.setClaimer(adapter)`

### User Flow (via Adapter)

`[setup above]` → `SavingsEUReAdapter.deposit()` → `InterestReceiver.claim()` (try, EOA only) → `SavingsEURe.deposit()`
                                                 ├→ `SavingsEUReAdapter.withdraw()` → `SavingsEURe.withdraw()`
                                                 └→ `SavingsEUReAdapter.redeem()` → `SavingsEURe.redeem()`

### User Flow (Direct Vault)

`[setup above]` → `SavingsEURe.deposit()` ├→ `SavingsEURe.withdraw()`
                                    └→ `SavingsEURe.redeem()`

### Yield Drip (EOA / Claimer)

`[setup above]` → [EURe funded externally] ◄── Monerium bot → `InterestReceiver.claim()` → `EURe.safeTransfer(sEURe)`

### Permit Flow

`SavingsEURe.permit()` → `_approve(owner, spender, value)` ◄── enables gasless approvals via EIP-712 signature

---

## Permissionless

### `SavingsEUReAdapter.deposit(uint256 assets, address receiver)`

| Aspect | Detail |
|--------|--------|
| Visibility | public, `claim` modifier (not access control) |
| Caller | Any address |
| Parameters | `assets` (user-controlled), `receiver` (user-controlled) |
| Call chain | `→ _claimHook() → InterestReceiver.claim()` (try/catch, EOA only) → `→ eure.safeTransferFrom(user, adapter, assets)` → `sEURe.deposit(assets, receiver)` |
| State modified | none local; InterestReceiver claim state if EOA; SavingsEURe shares minted |
| Value flow | EURe: user → adapter → vault |
| Reentrancy guard | no |

### `SavingsEUReAdapter.mint(uint256 shares, address receiver)`

| Aspect | Detail |
|--------|--------|
| Visibility | public, `claim` modifier |
| Caller | Any address |
| Parameters | `shares` (user-controlled), `receiver` (user-controlled) |
| Call chain | `→ _claimHook() → InterestReceiver.claim()` (try/catch, EOA only) → `→ eure.safeTransferFrom(user, adapter, previewMint(shares))` → `sEURe.mint(shares, receiver)` |
| State modified | none local; InterestReceiver claim state if EOA; SavingsEURe shares minted |
| Value flow | EURe: user → adapter → vault |
| Reentrancy guard | no |

### `SavingsEUReAdapter.withdraw(uint256 assets, address receiver)`

| Aspect | Detail |
|--------|--------|
| Visibility | public, `claim` modifier |
| Caller | Any address (clamps to `maxWithdraw(msg.sender)`) |
| Parameters | `assets` (user-controlled, clamped), `receiver` (user-controlled) |
| Call chain | `→ _claimHook() → InterestReceiver.claim()` (try/catch, EOA only) → `→ sEURe.maxWithdraw(msg.sender)` → `sEURe.withdraw(clamped_assets, receiver, msg.sender)` |
| State modified | none local; InterestReceiver claim state if EOA; SavingsEURe shares burned |
| Value flow | EURe: vault → receiver |
| Reentrancy guard | no |

### `SavingsEUReAdapter.redeem(uint256 shares, address receiver)`

| Aspect | Detail |
|--------|--------|
| Visibility | public, `claim` modifier |
| Caller | Any address (clamps to `maxRedeem(msg.sender)`) |
| Parameters | `shares` (user-controlled, clamped), `receiver` (user-controlled) |
| Call chain | `→ _claimHook() → InterestReceiver.claim()` (try/catch, EOA only) → `→ sEURe.maxRedeem(msg.sender)` → `sEURe.redeem(clamped_shares, receiver, msg.sender)` |
| State modified | none local; InterestReceiver claim state if EOA; SavingsEURe shares burned |
| Value flow | EURe: vault → receiver |
| Reentrancy guard | no |

### `SavingsEUReAdapter.redeemAll(address receiver)`

| Aspect | Detail |
|--------|--------|
| Visibility | public, `claim` modifier |
| Caller | Any address |
| Parameters | `receiver` (user-controlled) |
| Call chain | `→ _claimHook() → InterestReceiver.claim()` (try/catch, EOA only) → `→ sEURe.balanceOf(msg.sender)` → `sEURe.redeem(full_balance, receiver, msg.sender)` |
| State modified | none local; InterestReceiver claim state if EOA; SavingsEURe shares burned |
| Value flow | EURe: vault → receiver |
| Reentrancy guard | no |

### `SavingsEURe.deposit(uint256 assets, address receiver)` *(inherited ERC4626)*

| Aspect | Detail |
|--------|--------|
| Visibility | external |
| Caller | Any address |
| Parameters | `assets` (user-controlled), `receiver` (user-controlled) |
| Call chain | `→ OZ ERC4626._deposit(caller, receiver, assets, shares)` → `eure.transferFrom(caller, vault)` → `_mint(receiver, shares)` |
| State modified | `balanceOf[receiver] += shares`, `totalSupply += shares` |
| Value flow | EURe: caller → vault; sEURe: minted to receiver |
| Reentrancy guard | no |

### `SavingsEURe.mint(uint256 shares, address receiver)` *(inherited ERC4626)*

| Aspect | Detail |
|--------|--------|
| Visibility | external |
| Caller | Any address |
| Parameters | `shares` (user-controlled), `receiver` (user-controlled) |
| Call chain | `→ OZ ERC4626._deposit(caller, receiver, assets, shares)` → `eure.transferFrom(caller, vault)` → `_mint(receiver, shares)` |
| State modified | `balanceOf[receiver] += shares`, `totalSupply += shares` |
| Value flow | EURe: caller → vault; sEURe: minted to receiver |
| Reentrancy guard | no |

### `SavingsEURe.withdraw(uint256 assets, address receiver, address owner)` *(inherited ERC4626)*

| Aspect | Detail |
|--------|--------|
| Visibility | external |
| Caller | Any address; `owner` must approve caller if different |
| Parameters | `assets` (user-controlled), `receiver` (user-controlled), `owner` (user-controlled) |
| Call chain | `→ OZ ERC4626._withdraw(caller, receiver, owner, assets, shares)` → `_burn(owner, shares)` → `eure.transfer(receiver, assets)` |
| State modified | `balanceOf[owner] -= shares`, `totalSupply -= shares` |
| Value flow | EURe: vault → receiver; sEURe: burned from owner |
| Reentrancy guard | no |

### `SavingsEURe.redeem(uint256 shares, address receiver, address owner)` *(inherited ERC4626)*

| Aspect | Detail |
|--------|--------|
| Visibility | external |
| Caller | Any address; `owner` must approve caller if different |
| Parameters | `shares` (user-controlled), `receiver` (user-controlled), `owner` (user-controlled) |
| Call chain | `→ OZ ERC4626._withdraw(caller, receiver, owner, assets, shares)` → `_burn(owner, shares)` → `eure.transfer(receiver, assets)` |
| State modified | `balanceOf[owner] -= shares`, `totalSupply -= shares` |
| Value flow | EURe: vault → receiver; sEURe: burned from owner |
| Reentrancy guard | no |

### `SavingsEURe.permit(owner, spender, value, deadline, signature)` *(bytes-based)*

| Aspect | Detail |
|--------|--------|
| Visibility | public |
| Caller | Any address |
| Parameters | `owner` (user-signed), `spender` (user-signed), `value` (user-signed), `deadline` (user-signed), `signature` (user-signed) |
| Call chain | `→ _hashTypedDataV4(structHash)` → `SignatureChecker.isValidSignatureNow(owner, digest, signature)` → `_approve(owner, spender, value)` |
| State modified | `allowance[owner][spender] = value`, `nonces[owner] += 1` |
| Value flow | none |
| Reentrancy guard | no |

### `SavingsEURe.permit(owner, spender, value, deadline, v, r, s)` *(v,r,s-based)*

| Aspect | Detail |
|--------|--------|
| Visibility | external |
| Caller | Any address |
| Parameters | `owner` (user-signed), `spender` (user-signed), `value` (user-signed), `deadline` (user-signed), `v,r,s` (user-signed) |
| Call chain | `→ permit(owner, spender, value, deadline, abi.encodePacked(r, s, v))` — delegates to bytes overload |
| State modified | `allowance[owner][spender] = value`, `nonces[owner] += 1` |
| Value flow | none |
| Reentrancy guard | no |

### `InterestReceiver.claim()`

| Aspect | Detail |
|--------|--------|
| Visibility | public, `isInitialized` + `isClaimer` modifiers |
| Caller | EOA (always passes `tx.origin == msg.sender`) OR `claimer` contract |
| Parameters | none |
| Call chain | `→ _calculateClaim(balance)` → `eure.safeTransfer(address(sEURe), claimed)` |
| State modified | `currentEpochBalance`, `dripRate`, `nextClaimEpoch`, `lastClaimTimestamp` |
| Value flow | EURe: receiver → vault |
| Reentrancy guard | no (same-block guard via `lastClaimTimestamp == block.timestamp → return 0`) |

---

## Role-Gated

### `claimer` (current claimer address)

#### `InterestReceiver.initialize()`

| Aspect | Detail |
|--------|--------|
| Visibility | public, `initializer` modifier (one-shot) |
| Caller | Current `claimer` only |
| Parameters | none |
| Call chain | `→ _balance()` (reads `eure.balanceOf(address(this))`) → sets epoch parameters |
| State modified | `currentEpochBalance`, `lastClaimTimestamp`, `nextClaimEpoch`, `dripRate`, initialized version |
| Value flow | none |
| Reentrancy guard | no (OZ `initializer` prevents re-entry) |

#### `InterestReceiver.setClaimer(address newClaimer)`

| Aspect | Detail |
|--------|--------|
| Visibility | external |
| Caller | Current `claimer` only |
| Parameters | `newClaimer` (claimer-controlled) |
| Call chain | `→ writes claimer` |
| State modified | `claimer = newClaimer` |
| Value flow | none |
| Reentrancy guard | no |

---

## Initialization

| Contract | Function | Parameters | State Modified |
|----------|----------|------------|----------------|
| `InterestReceiver` | `initialize()` | none | `currentEpochBalance`, `lastClaimTimestamp`, `nextClaimEpoch`, `dripRate` |
