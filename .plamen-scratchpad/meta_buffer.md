# Meta-Buffer: sEURe Savings Vault (vault)

## Protocol Classification
- **Type**: vault (ERC4626 savings vault with epoch-based yield drip)
- **Key Indicators**: ERC4626, deposit/withdraw, shares, drip rate, epoch-based yield distribution, no external DeFi integration

## Protocol Context (from CHANGES-FROM-SDAI.md)
- Fork of sDAI-on-Gnosis with 3 bug fixes, 10 security improvements, and architectural simplification
- Yield source: bot-funded EURe deposits (no bridge, no oracle, no cross-chain)
- EURe is a permissioned token (Monerium can blocklist)

## RAG: UNAVAILABLE — no subagent dispatch. Phase 4b.5 RAG Sweep will compensate.

## Key Questions for Analysis Agents
1. Can `_calculateClaim` produce a `claimable` value > `balance` in any edge case? (balance could decrease between `_balance()` call and state update if EURe is transferred out)
2. Is the epoch rollover arithmetic safe when `balance - claimable` underflows? (line 124: `remaining = balance - claimable`)
3. Can the `dripRate` be manipulated via unsolicited EURe transfers to the receiver before/during epoch transitions?
4. Does `_decimalsOffset()=3` provide sufficient inflation protection for realistic deposit sizes?
5. Can `tx.origin == msg.sender` check be bypassed in any Gnosis Chain context (e.g., via CREATE2 or metatx)?
6. What happens if `initialize()` is never called? (receiver stays uninitialized, no yield drips, but vault still works as pure ERC4626)
7. Is the adapter's `previewMint` → `mint` pattern safe from sandwich attacks on share price?
