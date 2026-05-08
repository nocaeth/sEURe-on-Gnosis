# sEURe — Savings EURe on Gnosis

ERC-4626 yield-bearing vault for [Monerium EURe](https://monerium.com/) on Gnosis Chain. Adapted from [sDAI-on-Gnosis](https://github.com/gnosischain/sDAI-on-Gnosis).

Users deposit EURe and receive sEURe shares. A Monerium-funded bot sends yield to `InterestDispatcher`, which drips it into the vault over **5-day** epochs so yield cannot be grabbed in a single block (e.g. via flash loans). The vault claims interest automatically before every deposit, mint, withdraw, and redeem.

Underlying EURe on Gnosis: `0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430`.

## Contracts

| Contract | Description |
|----------|-------------|
| `SavingsEURe` | ERC-4626 vault; 3-decimal offset vs EURe; claims interest before share-changing ops; EIP-712 permit with `bytes` signature (EOA + ERC-1271) and legacy `v,r,s` overload |
| `InterestDispatcher` | UUPS-upgradeable epoch-based drip into the vault; deployed behind `ERC1967Proxy` with `initialize(owner)` in constructor `_data` (OZ v5.6+); owner-only `bootstrap(vault)` wires the vault and requires balance ≥ `MIN_INITIAL_BALANCE` (1 EURe); ERC-7201 namespaced storage; rollover pauses new drips when post-claim balance is below `DRIP_PAUSE_THRESHOLD` (100 EURe) |

## Security and Integration Notes

- `InterestDispatcher.vaultAPY()` is an instantaneous display metric, not an oracle. Direct EURe transfers to `InterestDispatcher` are part of the funding model and can affect the next epoch's `dripRate` and reported APY after rollover.
- `claim()` is permissionless — anyone (EOA or contract) can trigger yield distribution. The vault also claims automatically before every deposit, mint, withdraw, and redeem.
- `owner` controls UUPS implementation upgrades on the InterestDispatcher. Transfer this to a multisig after deployment and monitor `OwnerUpdated` events.
- If vault supply returns to zero while residual EURe remains in the vault, the next depositor can receive part of that residual through ERC-4626 share math. OpenZeppelin's virtual-share offset (`_decimalsOffset() = 3`) bounds this behavior, and the deployer seeds the vault with 1 EURe at deployment to mitigate first-depositor edge cases.

## Prerequisites

- [Foundry](https://book.getfoundry.sh/) (`forge`, `cast`, …)

## Build & test

```bash
forge build
forge test
```

Coverage (summary + `lcov.info`; HTML via `genhtml` if installed):

```bash
make coverage
make coverage-html
```

Verbose tests (same as `make tests`):

```bash
make tests
```

## Deploy

Set `RPC_GNOSIS` or `RPC_CHIADO` (see `foundry.toml` `[rpc_endpoints]`). The deployer script expects either a long `MNEMONIC` string (path `0` via `vm.deriveKey`) or `PRIVATE_KEY`.

**Gnosis Chain** (`chainId` 100, broadcast + verify):

```bash
make deploy-gnosis
```

Deploy sequence: `InterestDispatcher` implementation → `ERC1967Proxy` with `abi.encodeCall(InterestDispatcher.initialize, (deployer))` so the upgrade owner is set atomically (OpenZeppelin v5.6+ requires non-empty proxy init data) → `SavingsEURe` (proxy as interest receiver) → fund the proxy with **101 EURe** → `bootstrap(vault)` (owner-only) → seed the vault with **1 EURe** — all in one broadcast so `bootstrap` cannot be front-run by a non-owner.

**Chiado** (Makefile only; not supported by the stock script):

```bash
make deploy-chiado
```

`script/SavingsEUReDeployer.s.sol` **reverts unless `block.chainid == 100`** (`InvalidChain`). The Chiado target runs Forge against the `chiado` RPC but needs a script change (allow Chiado’s `chainId` and any testnet token addresses) before it can succeed.

## Security

- [Audit report](security/AUDIT_REPORT.md)
- [X-ray / protocol review notes](security/x-ray/x-ray.md) (entry points, invariants, architecture diagram)
- [Upgradeable storage layout (ERC-7201)](security/STORAGE_LAYOUT.md)

## Changes from sDAI

See [CHANGES-FROM-SDAI.md](security/CHANGES-FROM-SDAI.md) for architecture differences, bug fixes, and hardening vs the deployed sDAI stack.

## License

Core vault and receiver sources are **AGPL-3.0-only** unless a file header states otherwise (e.g. the deployer script is GPL-2.0-only).
