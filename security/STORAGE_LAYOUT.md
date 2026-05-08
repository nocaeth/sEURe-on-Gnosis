# Upgradeable storage layout (InterestDispatcher)

This note records how `InterestDispatcher` stores state in the **current** greenfield deployment and how it relates to ERC-7201 / namespaced storage.

## Current: ERC-7201 namespaced struct (manual slot)

[`InterestDispatcher`](../src/InterestDispatcher.sol) is **UUPS**-upgradeable and inherits OpenZeppelin `Initializable` and `UUPSUpgradeable` (both use ERC-7201-style documented storage locations upstream).

Module state (`vault`, `owner`, `dripRate`, `nextClaimEpoch`, `currentEpochBalance`, `lastClaimTimestamp`) lives in a single struct annotated with:

`@custom:storage-location erc7201:noca.savings_eure.interest_dispatcher`

The implementation uses the standard ERC-7201 slot formula (same as OpenZeppelin’s `Initializable` comment pattern), committed as:

`INTEREST_DISPATCHER_STORAGE_LOCATION = 0x9164f8c205381b64e458ee01bc88d5de773af3a65d86bd29c05ea24ac702cd00`

Implications:

- Future upgrades **must** only change this struct append-only (or introduce **new** namespaces / structs with distinct ERC-7201 ids) — never reorder or resize existing fields in place.
- Inherited OZ modules keep their own ERC-7201 namespaces; they do not share slots with the module struct above.

## Solidity `layout at erc7201("…")` (optional alternative)

Solidity **0.8.29+** supports relocating contract storage with **`layout at <expression>`**; **0.8.35** adds the **`erc7201("namespace")`** builtin ([EIP-7201](https://eips.ethereum.org/EIPS/eip-7201)). This repo uses the **manual slot constant + struct** pattern instead of `layout at` on the contract, but the **namespace string and slot math** follow the same EIP.

### What layout changes are *not*

You **cannot** change the namespace id or struct field order on an **already deployed** proxy **without** a **storage migration** that copies each field. Greenfield deployments should pick the final namespace before mainnet.

### Safe adoption paths (reference)

1. **New deployment** — New `ERC1967Proxy` + implementation with a fixed ERC-7201 namespace (this repo’s path for sEURe).
2. **Controlled migration** — One-shot migration that reads legacy layout, writes new layout, then switches implementation (only with audited scripts and tests).

## Related repo settings

[`foundry.toml`](../foundry.toml) pins **`solc_version`**, sets **`evm_version = "prague"`** (Gnosis / Chiado Pectra opcode set), and uses **`via_ir = true`**.

Compiler diagnostics: **`deny = "warnings"`** treats Solidity warnings as errors for first-party code; **`ignored_warnings_from = ["lib"]`** excludes dependency warnings (for example OpenZeppelin’s future-keyword notices in upstream sources) so `forge build` stays strict without forking vendored libs.
