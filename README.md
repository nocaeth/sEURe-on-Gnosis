# sEURe — Savings EURe on Gnosis

ERC-4626 yield-bearing vault for [Monerium EURe](https://monerium.com/) on Gnosis Chain. Adapted from [sDAI-on-Gnosis](https://github.com/gnosischain/sDAI-on-Gnosis).

Users deposit EURe and receive sEURe shares. A Monerium-funded bot sends yield to `InterestReceiver`, which drips it into the vault over **5-day** epochs so yield cannot be grabbed in a single block (e.g. via flash loans).

Underlying EURe on Gnosis: `0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430`.

## Contracts

| Contract | Description |
|----------|-------------|
| `SavingsEURe` | ERC-4626 vault; 3-decimal offset vs EURe; EIP-712 permit with `bytes` signature (EOA + ERC-1271) and legacy `v,r,s` overload |
| `InterestReceiver` | Epoch-based drip into the vault; `initialize()` requires balance above `MIN_EPOCH_BALANCE` (100 EURe) |
| `SavingsEUReAdapter` | User-facing entrypoint: pulls EURe, deposits to the vault, and attempts `claim()` on deposit/withdraw for **EOA** callers (`msg.sender == tx.origin`) |

Direct vault interaction remains possible; the adapter is the recommended path when you want claims bundled with user flows.

## Prerequisites

- [Foundry](https://book.getfoundry.sh/) (`forge`, `cast`, …)

## Build & test

```bash
forge build
forge test
```

Verbose tests (same as `make tests`):

```bash
make tests
```

## Deploy

Set `RPC_GNOSIS` or `RPC_CHIADO` (see `foundry.toml` `[rpc_endpoints]`). The deployer script expects either a long `MNEMONIC` string (path `0` via `vm.deriveKey`) or `PRIVATE_KEY`.

**Gnosis Chain** (broadcast + verify):

```bash
make deploy-gnosis
```

**Chiado** (broadcast, no verify in Makefile):

```bash
make deploy-chiado
```

The script deploys `SavingsEURe` → `InterestReceiver` → `SavingsEUReAdapter`, then sets the adapter as the receiver’s `claimer`.

**After deploy:** `initialize()` may only be called by the **current** `claimer`. Right after `InterestReceiver` is created, that address is the **deployer**; once `setClaimer(adapter)` runs, only the adapter could satisfy that check, and the adapter does not forward `initialize()`. So you must **fund** `InterestReceiver` with at least **100 EURe** (`MIN_EPOCH_BALANCE`) and call **`initialize()` while `claimer` is still the deployer**—e.g. extend `SavingsEUReDeployer.s.sol` to transfer EURe in, call `initialize()`, then deploy the adapter and `setClaimer`, or use a separate broadcast before handing off `claimer`. Until initialized, `claim` is disabled.

## Changes from sDAI

See [CHANGES-FROM-SDAI.md](CHANGES-FROM-SDAI.md) for architecture differences, bug fixes, and hardening vs the deployed sDAI stack.

## License

Core vault/receiver/adapter sources are **AGPL-3.0-only** unless a file header states otherwise (e.g. the deployer script is GPL-2.0-only).
