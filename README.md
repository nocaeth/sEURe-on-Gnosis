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

## Security and Integration Notes

- `InterestReceiver.vaultAPY()` is an instantaneous display metric, not an oracle. Direct EURe transfers to `InterestReceiver` are part of the funding model and can affect the next epoch's `dripRate` and reported APY after rollover.
- The claimer role is intentionally narrow: it can call `claim()` as a contract and transfer the claimer role, but it cannot move vault funds or change vault parameters. Initialize the receiver before handing this role to the adapter, monitor `ClaimerUpdated`, and prefer multisig-controlled deployment operations.
- If vault supply returns to zero while residual EURe remains in the vault, the next depositor can receive part of that residual through ERC-4626 share math. OpenZeppelin's virtual-share offset (`_decimalsOffset() = 3`) bounds this behavior, and no admin sweep role is included.
- Adapter auto-claims are EOA-only (`msg.sender == tx.origin`). Contract callers can still use the adapter, but they skip the bundled claim and should rely on direct vault flows, public EOA/keeper claims, or the configured claimer path.
- If an adapter auto-claim fails, the adapter emits `ClaimFailed(bytes reason)` and continues the user operation.

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

## Security

- [Audit report](security/AUDIT_REPORT.md)
- [X-ray / protocol review notes](security/x-ray/x-ray.md) (entry points, invariants, architecture diagram)

## Changes from sDAI

See [CHANGES-FROM-SDAI.md](CHANGES-FROM-SDAI.md) for architecture differences, bug fixes, and hardening vs the deployed sDAI stack.

## License

Core vault/receiver/adapter sources are **AGPL-3.0-only** unless a file header states otherwise (e.g. the deployer script is GPL-2.0-only).
