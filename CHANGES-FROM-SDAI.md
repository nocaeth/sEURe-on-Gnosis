# Changes from sDAI-on-Gnosis

This document details every change made from the [sDAI-on-Gnosis](https://github.com/gnosischain/sDAI-on-Gnosis) codebase when adapting it to sEURe. The sDAI contracts are deployed and audited on Gnosis Chain at:

- SavingsXDai: `0xaf204776c7245bF4147c2612BF6e5972Ee483701`
- BridgeInterestReceiver: `0x670daeaF0F1a5e336090504C68179670B5059088`
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

---

## Bug Fixes (vs deployed sDAI)

### 1. `currentEpochBalance` not zeroed after full drain (Critical)

**sDAI code (`BridgeInterestReceiver.sol:74,90`):**
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

**sEURe fix (`InterestReceiver.sol`):**
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

**sEURe fix (`SavingsEUReAdapter.sol`):**
```solidity
eure.safeTransferFrom(msg.sender, address(this), sEURe.previewMint(shares));
```

**Why:** `convertToAssets` uses floor rounding, but the vault's `mint()` internally requires `previewMint` (ceiling rounding). When the share price isn't a clean integer ratio, the adapter pulls 1 wei too few, and the vault's transfer from the adapter fails. This causes `adapter.mint()` to intermittently revert once yield accrues.

### 3. `claim()` modifier not wrapped in try/catch (High)

**sDAI code (`SavingsXDaiAdapter.sol:24`):**
```solidity
interestReceiver.claim();
```

**sEURe fix (`SavingsEUReAdapter.sol`):**
```solidity
try interestReceiver.claim() {} catch {}
```

**Why:** If the receiver reverts for any reason (not initialized, EURe frozen, the underflow bug), the raw call bubbles the revert up through the adapter, blocking all user deposits/withdrawals/mints/redeems. The try/catch ensures claim failures never block user operations.

---

## Security Hardening (new in sEURe)

### 4. ERC4626 inflation attack protection

**Added `_decimalsOffset()` override returning 3.**

The default offset of 0 leaves the vault vulnerable to the first-depositor inflation attack (attacker deposits 1 wei, donates large amount, next depositor gets ~0 shares). With offset 3, the virtual share multiplier is 1000x, making this attack 1000x more expensive. sDAI's ship has sailed (already has liquidity), but sEURe gets this protection at deploy.

### 5. `initialize()` restricted to claimer

**Added `require(msg.sender == claimer, "Not Claimer")` to `initialize()`.**

In sDAI, `initialize()` is permissionless — anyone can call it once the balance threshold is met. A front-runner could initialize at a suboptimal moment, permanently locking in bad epoch parameters on an immutable contract. sEURe restricts this to the claimer (deployer, then adapter).

### 6. `vaultAPY()` division-by-zero guard

**Added `if (deposits == 0) return 0` before the division.**

sDAI's `vaultAPY()` reverts with a division-by-zero panic when the vault is empty. Any frontend calling this pre-first-deposit or after full withdrawal breaks. sEURe returns 0 instead.

### 7. SafeERC20 in adapter

**Replaced raw `transferFrom` with `safeTransferFrom` in adapter.**

sDAI uses raw `wxdai.transferFrom()` — safe because WXDAI is a known-good contract. EURe is a different, permissioned token maintained by Monerium. SafeERC20 provides defensive return-value checking. The InterestReceiver already used SafeERC20 for its transfers.

### 8. `setClaimer` zero-address check

**Added `require(newClaimer != address(0), "Zero address")`.**

sDAI allows setting claimer to `address(0)`, permanently bricking the claimer role. While any EOA can still call `claim()` directly, the adapter would lose its special claimer status. On an immutable contract, this is unrecoverable.

### 9. `IInterestReceiver.claim()` return type

**Fixed interface to declare `returns (uint256)` matching the implementation.**

sDAI's interface declares `claim()` with no return value, but the implementation returns `uint256`. The mismatch prevents external integrators from reading the claimed amount through the interface.

---

## Simplification & Gas Optimization

### 10. `epochLength` changed to `constant`

sDAI declares `epochLength` as a storage variable (costs ~2100 gas cold SLOAD per read). It has no setter and never changes. sEURe declares it `constant`, eliminating the storage slot entirely.

### 11. Removed duplicate `vault` variable

sDAI's `BridgeInterestReceiver` stores both `address public vault` and `SavingsXDai private sDAI` pointing to the same contract. sEURe uses a single `SavingsEURe public immutable sEURe` and references `address(sEURe)` where needed.

### 12. Removed unused imports

- `IERC4626` import in InterestReceiver (never referenced)
- `ECDSA` import in SavingsEURe (never used — custom `ecrecover` is used instead)

### 13. Renamed `_aggregateBalance()` to `_balance()`

The original name implied aggregation across multiple balance sources (native xDAI + WXDAI). In sEURe it's a single `eure.balanceOf()` call. Renamed for clarity.

### 14. Cached `balance - claimable` in `_calcClaimable()`

The expression was computed 3 times in the epoch renewal block. Now cached in a `remaining` local variable.

---

## Threshold Changes

| Parameter | sDAI | sEURe | Rationale |
|-----------|------|-------|-----------|
| Init minimum | 30,000 | 10,000 | Lower barrier for a new product to go live |
| Epoch minimum | 1,000 | 1,000 | Kept — still reasonable for EURe |
| Epoch length | 3 days | 3 days | Kept — battle-tested |
| First epoch | 6 days | 6 days | Kept — conservative initial drip |

---

## Dependencies

| Library | sDAI | sEURe |
|---------|------|-------|
| OpenZeppelin | v5.x (untagged commit) | v5.3.0 (tagged, audited) |
| forge-std | unknown (submodule not populated) | v1.15.0 |

---

## Known Accepted Risks

1. **EURe blocklist** — Monerium can freeze the vault or receiver address, permanently locking all deposits. No code mitigation exists for an immutable contract. This is inherent to using a permissioned stablecoin.

2. **`isClaimer` modifier allows any EOA** — `tx.origin == msg.sender` passes for every EOA, not just the designated claimer. This is inherited from sDAI and is intentional (prevents smart contract flashloan attacks while allowing any EOA to trigger yield distribution). The `claimer` role is only meaningful for contract callers (i.e., the adapter).

3. **Epoch revival requires two claims** — After a full drain (dripRate=0), the first `claim()` after new deposits sets up the new epoch but distributes 0. A second claim is needed to actually drip yield. This is by design and self-heals.

4. **Contract wallets don't trigger claims** — Safe multisigs and ERC-4337 wallets never trigger the adapter's `claim()` modifier due to the `tx.origin` check. Yield distribution depends on EOA interactions or an external keeper.
