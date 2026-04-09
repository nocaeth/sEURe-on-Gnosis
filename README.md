# sEURe — Savings EURe on Gnosis

ERC4626 yield-bearing vault for [Monerium EURe](https://monerium.com/) on Gnosis Chain. Adapted from [sDAI-on-Gnosis](https://github.com/gnosischain/sDAI-on-Gnosis).

Users deposit EURe and receive sEURe shares. A Monerium-funded bot periodically deposits yield into the InterestReceiver, which drips it to the vault over 3-day epochs to prevent flashloan exploitation.

## Contracts

| Contract | Description |
|----------|-------------|
| `SavingsEURe` | ERC4626 vault with EIP-2612 permit (EOA + ERC-1271 multisig) |
| `InterestReceiver` | Epoch-based yield drip mechanism. Receives EURe from bot, releases to vault over time |
| `SavingsEUReAdapter` | User-facing proxy that auto-claims pending yield on every deposit/withdraw |

## Build & Test

```
forge build
forge test
```

## Deploy

```
# Set env vars: MNEMONIC or PRIVATE_KEY, RPC_GNOSIS
make deploy-gnosis
```

Post-deployment: fund InterestReceiver with >= 10,000 EURe, then call `initialize()`.

## Changes from sDAI

See [CHANGES-FROM-SDAI.md](CHANGES-FROM-SDAI.md) for a full breakdown of modifications, bug fixes, and security hardening applied vs the deployed sDAI contracts.
