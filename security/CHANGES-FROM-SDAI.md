# Changes from sDAI-on-Gnosis

This document details every change made from the [sDAI-on-Gnosis](https://github.com/gnosischain/sDAI-on-Gnosis) codebase when adapting it to sEURe. The sDAI contracts are deployed and audited on Gnosis Chain at:

- SavingsXDai: `0xaf204776c7245bF4147c2612BF6e5972Ee483701`
- BridgeInterestDispatcher: `0x670daeaF0F1a5e336090504C68179670B5059088`
- SavingsXDaiAdapter: `0xD499b51fcFc66bd31248ef4b28d656d67E591A94`

## Architecture Changes

### Underlying token: WXDAI → EURe

| | sDAI | sEURe |
|---|---|---|
| Token | WXDAI `0xe91D153E0b41518A2Ce8Dd3D7944Fa863463a97d` | EURe `0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430` |
| Type | Wrapped native gas token | Standard ERC-20 |
| Issuer | Protocol-level | Monerium (permissioned, blocklist) |

### Yield source: Bridge → Bot

sDAI receives yield from the Ethereum-Gnosis xDAI bridge, which deposits DAI into Spark's sDAI/sUSDS on mainnet and bridges the accrued interest as native xDAI. sEURe receives yield from a Monerium-funded bot that transfers EURe directly on Gnosis Chain. No cross-chain component.

### Removed: All native token handling

Since EURe is a standard ERC-20 (not a wrapped native gas token), all native xDAI wrapping/unwrapping logic was removed:

**Removed from adapter (5 functions + fallback):**
- `depositXDAI(address receiver)` — deposited native xDAI by wrapping to WXDAI
- `withdrawXDAI(uint256 assets, address receiver)` — withdrew as native xDAI
- `redeemXDAI(uint256 shares, address receiver)` — redeemed as native xDAI
- `redeemAllXDAI(address receiver)` — redeemed all as native xDAI
- `receive() external payable` — auto-deposited native xDAI sent to adapter

**Removed from interest receiver:**
- `receive() external payable {}` — accepted native xDAI from bridge
- `_aggregateBalance()` wrapping logic — wrapped native xDAI to WXDAI before calculating balance

**Removed entirely:**
- `IWXDAI.sol` interface — no wrapped native token needed

### Removed: Adapter contract

sDAI uses `SavingsXDaiAdapter` as the user-facing entrypoint that bundles claim calls with vault operations. sEURe folds this responsibility into the vault itself:

- SavingsEURe calls `_claimInterest()` before every `deposit`, `mint`, `withdraw`, and `redeem`
- The vault stores an immutable `interestDispatcher` address and an `interestClaimingEnabled` flag
- Only the interest receiver can call `enableInterestClaiming()` (called during its own `initialize()`)
- No separate adapter contract, `ISavingsEUReAdapter` interface, or periphery directory

This eliminates an entire contract and removes the EOA-only claim restriction (`msg.sender == tx.origin` in the adapter). Claims now fire for all vault interactions regardless of caller type.

### InterestDispatcher is now UUPS upgradeable

sDAI's `BridgeInterestDispatcher` is an immutable deployed contract. sEURe's `InterestDispatcher` is deployed behind an `ERC1967Proxy` and uses the UUPS upgrade pattern:

- `constructor()` calls `_disableInitializers()` — implementation is logic-only
- `initialize(address vault, address owner_)` sets vault reference and upgrade authority through the proxy
- `_authorizeUpgrade()` gates upgrades to `owner`
- `transferOwnership(address newOwner)` allows ownership transfer
- `sEURe` reference is no longer `immutable` (set during `initialize` through the proxy)

### `claimer` role replaced with permissionless claims + `owner`

sDAI's claim model restricts contract callers to a designated `claimer` address while allowing any EOA. sEURe removes the `claimer` concept entirely:

- `claim()` is permissionless — anyone (EOA or contract) can call it
- The `isClaimer` modifier, `NotValidClaimer` error, and `setClaimer()` function are removed
- `owner` governs only UUPS implementation upgrades, not claim access
- The vault itself calls `claim()` before share-changing operations, removing the need for a separate claimer contract

---

## Bug Fixes (vs deployed sDAI)

### 1. `currentEpochBalance` not zeroed after full drain (Critical)

**sDAI code (`BridgeInterestDispatcher.sol:74,90`):**
```solidity
// Full-epoch branch — currentEpochBalance NOT zeroed
if (unclaimedTime >= epochLength) {
    claimable = currentEpochBalance;
}
// ...
// Low-balance drain — currentEpochBalance NOT zeroed
if ((balance - claimable) < 1000 ether) {
    dripRate = 0;
}
```

**sEURe fix (`InterestDispatcher.sol`):**
```solidity
if (unclaimedTime >= epochLength) {
    claimable = currentEpochBalance;
    currentEpochBalance = 0;  // ADDED
}
// ...
if ((balance - claimable) < 1000 ether) {
    dripRate = 0;
    currentEpochBalance = 0;  // ADDED
}
```

**Why:** When the receiver drains below 1000 and `dripRate` is set to 0, `currentEpochBalance` retained its stale value. If new funds arrived and a full epoch passed, `claim()` would attempt to transfer the stale (large) `currentEpochBalance` from a smaller actual balance, causing an arithmetic underflow revert. This permanently bricks the drip mechanism until the balance exceeds the stale value. In sDAI this is unlikely due to continuous bridge funding. In sEURe with periodic bot deposits, it's a real scenario.

### 2. `adapter.mint()` rounding mismatch (Medium)

**sDAI code (`SavingsXDaiAdapter.sol:37`):**
```solidity
wxdai.transferFrom(msg.sender, address(this), sDAI.convertToAssets(shares));
```

**sEURe fix:**
The adapter was removed entirely. Users interact directly with the vault, which inherits OpenZeppelin's rounding-safe `mint()` implementation. No separate `convertToAssets` / `previewMint` mismatch can occur because there is no intermediary contract.

**Why:** `convertToAssets` uses floor rounding, but the vault's `mint()` internally requires `previewMint` (ceiling rounding). When the share price isn't a clean integer ratio, the adapter pulls 1 wei too few, and the vault's transfer from the adapter fails. This causes `adapter.mint()` to intermittently revert once yield accrues. Removing the adapter eliminates this class of bug.

### 3. `claim()` failure no longer blocks user operations (High)

**sDAI code (`SavingsXDaiAdapter.sol:24`):**
```solidity
interestDispatcher.claim();
```

**sEURe design (`SavingsEURe.sol`):**
The vault calls `_claimInterest()` before share-changing operations. If `interestClaimingEnabled` is `false` (receiver not yet initialized), the call is a silent no-op. Once enabled, the receiver's `claim()` handles its own edge cases (same-block dedup, zero balance). This removes the scenario where a raw revert in `claim()` blocks all user operations — the gate is a simple flag, not a try/catch around an external call that can fail for many reasons.

---

## Security Hardening (new in sEURe)

### 4. ERC4626 inflation attack protection

**Added `_decimalsOffset()` override returning 3.**

The default offset of 0 leaves the vault vulnerable to the first-depositor inflation attack (attacker deposits 1 wei, donates large amount, next depositor gets ~0 shares). With offset 3, the virtual share multiplier is 1000x, making this attack 1000x more expensive. sDAI's ship has sailed (already has liquidity), but sEURe gets this protection at deploy.

### 5. `initialize()` gated by proxy + OpenZeppelin initializer

**Uses OpenZeppelin's `initializer` modifier via `ERC1967Proxy`.**

In sDAI, `initialize()` is permissionless — anyone can call it once the balance threshold is met. A front-runner could initialize at a suboptimal moment, permanently locking in bad epoch parameters on an immutable contract. sEURe solves this structurally: the implementation's constructor disables initializers, so `initialize()` can only be called once through the proxy during the deployment broadcast. The `owner` is set at that time.

### 6. `vaultAPY()` division-by-zero guard

**Added `if (deposits == 0) return 0` before the division.**

sDAI's `vaultAPY()` reverts with a division-by-zero panic when the vault is empty. Any frontend calling this pre-first-deposit or after full withdrawal breaks. sEURe returns 0 instead.

### 7. SafeERC20 used throughout

**All ERC-20 transfers use SafeERC20.**

sDAI uses raw `wxdai.transferFrom()` in the adapter — safe because WXDAI is a known-good contract. EURe is a different, permissioned token maintained by Monerium. sEURe uses `safeTransfer` for all EURe operations in the receiver. The vault relies on OpenZeppelin ERC4626's built-in SafeERC20 for asset transfers.

### 8. `transferOwnership` zero-address check

**Added a `ZeroAddress()` check.**

sDAI's `setClaimer` allowed setting the claimer to `address(0)`, permanently bricking the claimer role. sEURe replaces `setClaimer` with `transferOwnership`, which also validates against zero address. The role is different — it governs UUPS upgrades, not claim access — but the same foot-gun prevention applies.

### 9. `IInterestDispatcher.claim()` return type

**Fixed interface to declare `returns (uint256)` matching the implementation.**

sDAI's interface declares `claim()` with no return value, but the implementation returns `uint256`. The mismatch prevents external integrators from reading the claimed amount through the interface.

### 10. Permit signature validation upgraded to OpenZeppelin helpers

**Replaced custom `ecrecover` / ERC-1271 handling with `SignatureChecker.isValidSignatureNow`.**

sEURe originally carried custom permit verification logic so EOAs and contract wallets could both approve by signature. That logic accepted high-`s` malleable ECDSA signatures and duplicated behavior already provided by OpenZeppelin. The current implementation delegates signature validation to `SignatureChecker`, preserving ERC-1271 support while using OpenZeppelin's canonical ECDSA checks.

### 11. Permit domain separator uses OpenZeppelin EIP-712 path

**Removed the custom cached domain separator and now hashes permits with `_hashTypedDataV4`.**

The previous implementation maintained a second domain-separator cache alongside OpenZeppelin's `EIP712` cache. Both produced the same value, but duplicating this logic made future drift possible. sEURe now uses OpenZeppelin's fork-aware `_domainSeparatorV4()` path through `_hashTypedDataV4`.

### 12. Duplicate `Approval` event removed from `permit()`

**Removed manual `emit Approval(...)` after `_approve`.**

OpenZeppelin Contracts v5 `_approve(owner, spender, value)` already emits `Approval`. The extra manual emit caused each successful permit to produce two identical approval logs. sEURe now emits the standard single event.

### 13. InterestDispatcher custom errors

**Replaced string reverts with custom errors.**

The receiver now uses `NotInitialized`, `NotOwner`, `InsufficientInitialBalance`, and `ZeroAddress`. This reduces bytecode/revert overhead and makes test and integration expectations more precise.

### 14. InterestDispatcher operational events

**Added `Initialized` and `OwnerUpdated` events.**

The receiver already emitted `Claimed`; initialization and upgrade ownership transfers are now also visible to indexers, dashboards, and deployment checks.

### 15. InterestDispatcher NatSpec and explicit policy constants

**Documented the receiver, interface, public state, role model, APY semantics, and thresholds.**

The previously inline balance threshold is now the named constant `MIN_EPOCH_BALANCE`, used both for initialization and epoch renewal.

---

## Simplification & Gas Optimization

### 16. `epochLength` changed to `constant`

sDAI declares `epochLength` as a storage variable (costs ~2100 gas cold SLOAD per read). It has no setter and never changes. sEURe declares it `constant`, eliminating the storage slot entirely.

### 17. Removed duplicate `vault` variable

sDAI's `BridgeInterestDispatcher` stores both `address public vault` and `SavingsXDai private sDAI` pointing to the same contract. sEURe uses a single `ISavingsEURe public override sEURe` (set during `initialize` for UUPS compatibility) and references `address(sEURe)` where needed.

### 18. Removed unused imports and custom signature plumbing

- `IERC4626` import in InterestDispatcher (never referenced)
- Custom `IERC1271` interface in SavingsEURe (replaced by OpenZeppelin `SignatureChecker`)
- Custom domain-separator state in SavingsEURe (replaced by OpenZeppelin `EIP712`)

### 19. Renamed `_aggregateBalance()` to `_balance()`

The original name implied aggregation across multiple balance sources (native xDAI + WXDAI). In sEURe it's a single `eure.balanceOf()` call. Renamed for clarity.

### 20. Internal claim state math

`claim()` uses a single internal `_calculateClaim()` path to derive the claimed amount and next epoch state. The external `previewClaimable()` view was removed to keep the receiver interface focused on the mutation path used by the vault and keepers.

---

## Threshold Changes

| Parameter | sDAI | sEURe | Rationale |
|-----------|------|-------|-----------|
| Init minimum | 30,000 | 100 | Lower barrier for a new product to go live |
| Epoch minimum | 1,000 | 100 | Lower threshold for bot-funded EURe epochs |
| Epoch length | 3 days | 5 days | Slower drip cadence for sEURe |
| First epoch | 6 days | 5 days | No special bridge-integration lag; uses regular epoch length |

---

## Dependencies

| Library | sDAI | sEURe |
|---------|------|-------|
| OpenZeppelin | v5.x (untagged commit) | v5.3.0 (tagged, audited) |
| forge-std | unknown (submodule not populated) | v1.15.0 |

All in-repo Solidity files now use standard SPDX identifiers and `pragma solidity ^0.8.20`, matching the OpenZeppelin v5.3.0 dependency baseline.

---

## Known Accepted Risks

1. **EURe blocklist** — Monerium can freeze the vault or receiver address, permanently locking all deposits. No code mitigation exists for an immutable contract. This is inherent to using a permissioned stablecoin.

2. **`claim()` is permissionless** — Anyone (EOA or contract) can call `claim()`. This is intentional — the vault claims before every share-changing operation, and external keepers can trigger claims at any time. There is no flash-loan risk from permissionless claims because the epoch-based drip model spreads yield over time.

3. **Epoch revival requires two claims** — After a full drain (dripRate=0), the first `claim()` after new deposits sets up the new epoch but distributes 0. A second claim is needed to actually drip yield. This is by design and self-heals.

4. **UUPS upgrade authority** — `owner` can upgrade the InterestDispatcher implementation. If this key is compromised or lost, an attacker could replace the receiver logic or the role becomes permanently stuck. This is the tradeoff for having a fixable receiver on an otherwise immutable system.
