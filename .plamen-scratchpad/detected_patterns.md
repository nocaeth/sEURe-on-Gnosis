# Detected Patterns

| Pattern | Flag | Evidence |
|---------|------|----------|
| Temporal | TEMPORAL | epochLength=5 days, epoch-based drip mechanism, lastClaimTimestamp, nextClaimEpoch |
| ERC4626 vault | ERC4626 | SavingsEURe extends ERC4626, deposit/withdraw/redeem/mint |
| Balance-dependent | BALANCE_DEPENDENT | InterestReceiver._balance() = eure.balanceOf(address(this)), SavingsEURe totalAssets = EURe balanceOf(vault) |
| Semi-trusted role | SEMI_TRUSTED_ROLE | claimer role, isClaimer modifier, tx.origin check |
| Share allocation | SHARE_ALLOCATION | ERC4626 shares, decimalsOffset=3 |
| Monetary parameter | MONETARY_PARAMETER | dripRate (EURe/second), currentEpochBalance, epochLength |
| Signatures | HAS_SIGNATURES | EIP712, SignatureChecker.isValidSignatureNow, permit(), DOMAIN_SEPARATOR, nonces |
| Multi-contract | HAS_MULTI_CONTRACT | 3 implementation contracts, shared EURe address, shared vault reference |
