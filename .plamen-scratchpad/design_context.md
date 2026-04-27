# Design Context

## Protocol Purpose
SavingsEURe (sEURe) is an ERC4626 vault for EURe (Monerium EUR stablecoin on Gnosis Chain). Users deposit EURe, receive sEURe shares, and earn yield from EURe dripped by the InterestReceiver via epoch-based drip mechanism.

## Architecture
- **SavingsEURe**: ERC4626 vault with EIP712 permit support. Holds EURe, issues sEURe shares. `_decimalsOffset()=3` for inflation protection.
- **InterestReceiver**: Holds EURe externally, drips into vault over epochs (5-day periods). Tracks drip rate, epoch balance, and epoch rollover.
- **SavingsEUReAdapter**: Optional wrapper for vault interactions. Auto-triggers `claim()` on EOA deposits/withdrawals via try/catch.

## Key Invariants
1. sEURe shares are ERC4626-compliant — `convertToShares(totalAssets()) == totalSupply()` at all times
2. InterestReceiver drips EURe linearly over epochs at `dripRate` per second
3. Epoch transitions: when `block.timestamp > nextClaimEpoch`, remaining balance recalculates new drip rate
4. `claim()` transfers claimable EURe from receiver to vault, increasing share value
5. No one can withdraw more than their proportional share of total assets

## Yield Source
Bot-funded EURe deposits on Gnosis Chain. No cross-chain. No bridge. No oracle. No external DeFi integration.

## Trust Model

| # | Actor | Trust Level | Assumption | Source |
|---|-------|-------------|------------|--------|
| 1 | Claimer (deployer → adapter) | SEMI_TRUSTED(bounds: can call initialize once, can call claim, can transfer claimer role) | One-step claimer transfer, cannot be address(0) | Code |
| 2 | Any EOA | UNTRUSTED | Any EOA can call claim() — tx.origin==msg.sender check | Code |
| 3 | Contract callers | UNTRUSTED | Only claimer contract can call claim() — prevents contract flash-loan attacks | Code |
| 4 | Monerium (EURe issuer) | FULLY_TRUSTED | Can blocklist vault/receiver addresses, freezing all deposits | CHANGES-FROM-SDAI.md Known Risk #1 |
| 5 | Bot (yield funder) | SEMI_TRUSTED(bounds: funds receiver periodically) | Must fund receiver above MIN_EPOCH_BALANCE for epoch renewal | Design |
| 6 | Users | UNTRUSTED | Deposit/withdraw via adapter or vault directly | Design |

## Fork Ancestry
- **Parent**: sDAI-on-Gnosis (Gnosis Chain)
- **Deployed parent addresses**: SavingsXDai `0xaf204776c7245bF4147c2612BF6e5972Ee483701`, BridgeInterestReceiver `0x670daeaF0F1a5e336090504C68179670B5059088`, SavingsXDaiAdapter `0xD499b51fcFc66bd31248ef4b28d656d67E591A94`
- **Key divergences**: native token handling removed, bug fixes applied (epoch drain zeroing, mint rounding, claim try/catch), security hardening (decimalsOffset, restricted initialize, SafeERC20, zero-address check, SignatureChecker upgrade)
