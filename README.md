# sEURe — Savings EURe on Gnosis

ERC-4626 yield-bearing vault for [Monerium EURe](https://monerium.com/) on Gnosis Chain. Adapted from [sDAI-on-Gnosis](https://github.com/gnosischain/sDAI-on-Gnosis).

Users deposit EURe and receive sEURe shares. A Monerium-funded bot sends yield to `InterestDispatcher`, which drips it into the vault over **5-day** epochs so yield cannot be grabbed in a single block (e.g. via flash loans). The vault claims interest automatically before every deposit, mint, withdraw, and redeem.

Underlying EURe on Gnosis: `0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430`.

## Contracts

| Contract | Description |
|----------|-------------|
| `SavingsEURe` | ERC-4626 vault; 3-decimal offset vs EURe; claims interest before share-changing ops; EIP-712 permit with `bytes` signature (EOA + ERC-1271) and legacy `v,r,s` overload |
| `InterestDispatcher` | UUPS-upgradeable epoch-based drip into the vault; deployed behind ERC1967Proxy; `initialize()` requires balance above `MIN_EPOCH_BALANCE` (100 EURe) |

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

The script deploys `InterestDispatcher` implementation → `ERC1967Proxy` → `SavingsEURe` (with proxy address as interest receiver), funds and initializes the receiver, then seeds the vault with 1 EURe — all in a single broadcast to prevent front-running the initializer.

## Security

- [Audit report](AUDIT_REPORT.md)
- [X-ray / protocol review notes](security/x-ray/x-ray.md) (entry points, invariants, architecture diagram)

## Changes from sDAI

See [CHANGES-FROM-SDAI.md](security/CHANGES-FROM-SDAI.md) for architecture differences, bug fixes, and hardening vs the deployed sDAI stack.

## License

Core vault and receiver sources are **AGPL-3.0-only** unless a file header states otherwise (e.g. the deployer script is GPL-2.0-only).
