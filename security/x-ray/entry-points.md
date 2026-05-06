# Entry Point Map

> sEURe | 10 entry points | 8 permissionless | 2 role-gated | 0 admin-only

---

## Protocol Flow Paths

### Setup (Deployer)

`InterestDispatcher.initialize(vault, owner_)` → `SavingsEURe.enableInterestClaiming()`

### User Flow

`[setup above]` → `SavingsEURe.deposit(assets, receiver)` ◄── auto-claims first
                                    ├─→ `SavingsEURe.mint(shares, receiver)` ◄── auto-claims first
                                    ├─→ `SavingsEURe.withdraw(assets, receiver, owner)` ◄── auto-claims first, needs allowance if owner ≠ caller
                                    └─→ `SavingsEURe.redeem(shares, receiver, owner)` ◄── auto-claims first, needs allowance if owner ≠ caller

### Auth Flow

`SavingsEURe.permit(owner, spender, value, deadline, signature)` ◄── EOA or ERC-1271
                                    └─→ `SavingsEURe.permit(owner, spender, value, deadline, v, r, s)` ◄── wraps to bytes

### Yield Flow (Anyone)

`[setup above]` → `[time passes]` → `InterestDispatcher.claim()` ◄── drips EURe into vault, updates epoch

### Maintenance (owner)

`InterestDispatcher.transferOwnership(newOwner)`

---

## Permissionless

### `SavingsEURe.deposit(uint256 assets, address receiver)`

| Aspect | Detail |
|--------|--------|
| Visibility | public |
| Caller | User |
| Parameters | assets (user-controlled), receiver (user-controlled) |
| Call chain | `→ SavingsEURe._claimInterest() → InterestDispatcher.claim() → EURe.safeTransfer(sEURe, claimed)` then `→ ERC4626.deposit() → ERC20._mint(receiver, shares) → EURe.safeTransferFrom(user, vault, assets)` |
| State modified | InterestDispatcher: currentEpochBalance, dripRate, nextClaimEpoch, lastClaimTimestamp; SavingsEURe: _totalSupply, balanceOf[receiver] |
| Value flow | EURe: user → vault |
| Reentrancy guard | no |

### `SavingsEURe.mint(uint256 shares, address receiver)`

| Aspect | Detail |
|--------|--------|
| Visibility | public |
| Caller | User |
| Parameters | shares (user-controlled), receiver (user-controlled) |
| Call chain | `→ SavingsEURe._claimInterest() → InterestDispatcher.claim()` then `→ ERC4626.mint() → ERC20._mint(receiver, shares) → EURe.safeTransferFrom(user, vault, assets)` |
| State modified | InterestDispatcher: currentEpochBalance, dripRate, nextClaimEpoch, lastClaimTimestamp; SavingsEURe: _totalSupply, balanceOf[receiver] |
| Value flow | EURe: user → vault |
| Reentrancy guard | no |

### `SavingsEURe.withdraw(uint256 assets, address receiver, address owner)`

| Aspect | Detail |
|--------|--------|
| Visibility | public |
| Caller | User (owner or approved operator) |
| Parameters | assets (user-controlled), receiver (user-controlled), owner (user-controlled) |
| Call chain | `→ SavingsEURe._claimInterest() → InterestDispatcher.claim()` then `→ ERC4626.withdraw() → ERC20._burn(owner, shares) → EURe.safeTransfer(receiver, assets)` |
| State modified | InterestDispatcher: currentEpochBalance, dripRate, nextClaimEpoch, lastClaimTimestamp; SavingsEURe: _totalSupply, balanceOf[owner], allowance[owner][spender] (if owner ≠ caller) |
| Value flow | EURe: vault → receiver |
| Reentrancy guard | no |

### `SavingsEURe.redeem(uint256 shares, address receiver, address owner)`

| Aspect | Detail |
|--------|--------|
| Visibility | public |
| Caller | User (owner or approved operator) |
| Parameters | shares (user-controlled), receiver (user-controlled), owner (user-controlled) |
| Call chain | `→ SavingsEURe._claimInterest() → InterestDispatcher.claim()` then `→ ERC4626.redeem() → ERC20._burn(owner, shares) → EURe.safeTransfer(receiver, assets)` |
| State modified | InterestDispatcher: currentEpochBalance, dripRate, nextClaimEpoch, lastClaimTimestamp; SavingsEURe: _totalSupply, balanceOf[owner], allowance[owner][spender] (if owner ≠ caller) |
| Value flow | EURe: vault → receiver |
| Reentrancy guard | no |

### `SavingsEURe.permit(address owner, address spender, uint256 value, uint256 deadline, bytes signature)`

| Aspect | Detail |
|--------|--------|
| Visibility | public |
| Caller | Anyone (with valid signature from owner) |
| Parameters | owner (user-signed), spender (user-signed), value (user-signed), deadline (user-signed), signature (user-signed) |
| Call chain | `→ EIP712._hashTypedDataV4(structHash) → SignatureChecker.isValidSignatureNow(owner, digest, signature) → ERC20._approve(owner, spender, value)` |
| State modified | SavingsEURe: allowance[owner][spender], nonces[owner] |
| Value flow | none |
| Reentrancy guard | no |

### `SavingsEURe.permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)`

| Aspect | Detail |
|--------|--------|
| Visibility | external |
| Caller | Anyone (with valid ECDSA signature from owner) |
| Parameters | owner (user-signed), spender (user-signed), value (user-signed), deadline (user-signed), v, r, s (user-signed) |
| Call chain | `→ SavingsEURe.permit(owner, spender, value, deadline, abi.encodePacked(r, s, v))` |
| State modified | SavingsEURe: allowance[owner][spender], nonces[owner] |
| Value flow | none |
| Reentrancy guard | no |

### `InterestDispatcher.claim()`

| Aspect | Detail |
|--------|--------|
| Visibility | public |
| Caller | Anyone / Keeper |
| Parameters | none |
| Call chain | `→ InterestDispatcher._calculateClaim(balance) → EURe.safeTransfer(address(sEURe), claimed)` |
| State modified | InterestDispatcher: currentEpochBalance, dripRate, nextClaimEpoch, lastClaimTimestamp |
| Value flow | EURe: InterestDispatcher → SavingsEURe vault |
| Reentrancy guard | no |

### Inherited ERC20

| Function | Visibility | Value Flow |
|----------|-----------|------------|
| `transfer(address to, uint256 amount)` | public | sEURe: caller → to |
| `approve(address spender, uint256 amount)` | public | none |
| `transferFrom(address from, address to, uint256 amount)` | public | sEURe: from → to |

---

## Role-Gated

### interestDispatcher

#### `SavingsEURe.enableInterestClaiming()`

| Aspect | Detail |
|--------|--------|
| Visibility | external |
| Caller | InterestDispatcher (during initialization) |
| Parameters | none |
| Call chain | `→ ERC20._approve` (no external calls) |
| State modified | SavingsEURe: interestClaimingEnabled (false → true, one-shot) |
| Value flow | none |
| Reentrancy guard | no |

### owner

#### `InterestDispatcher.transferOwnership(address newOwner)`

| Aspect | Detail |
|--------|--------|
| Visibility | external |
| Caller | Current owner |
| Parameters | newOwner (user-controlled) |
| Call chain | none (direct storage write) |
| State modified | InterestDispatcher: owner |
| Value flow | none |
| Reentrancy guard | no |

---

## Initialization

### `InterestDispatcher.initialize(address vault, address owner_)`

| Aspect | Detail |
|--------|--------|
| Visibility | public, initializer modifier |
| Caller | Deployer (via proxy) |
| Parameters | vault (deployer-controlled), owner_ (deployer-controlled) |
| Call chain | `→ SavingsEURe.enableInterestClaiming()` |
| State modified | InterestDispatcher: sEURe, owner, currentEpochBalance, lastClaimTimestamp, nextClaimEpoch, dripRate |
| Value flow | none |
| Notes | One-time; requires ≥100 EURe balance in receiver; called during deployment broadcast |
