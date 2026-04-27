# Call Graph

```
User → SavingsEUReAdapter.deposit() → SavingsEURe.deposit() [ERC4626]
                                   → InterestReceiver.claim() [try/catch, EOA only]

User → SavingsEUReAdapter.mint()   → SavingsEURe.previewMint()
                                   → SavingsEURe.mint() [ERC4626]
                                   → InterestReceiver.claim() [try/catch, EOA only]

User → SavingsEUReAdapter.withdraw() → SavingsEURe.maxWithdraw()
                                     → SavingsEURe.withdraw() [ERC4626]
                                     → InterestReceiver.claim() [try/catch, EOA only]

User → SavingsEUReAdapter.redeem()  → SavingsEURe.maxRedeem()
                                    → SavingsEURe.redeem() [ERC4626]
                                    → InterestReceiver.claim() [try/catch, EOA only]

User → SavingsEUReAdapter.redeemAll() → SavingsEURe.balanceOf()
                                      → SavingsEURe.redeem() [ERC4626]
                                      → InterestReceiver.claim() [try/catch, EOA only]

User/Claimer → InterestReceiver.claim() → _calculateClaim()
                                        → EURe.safeTransfer(vault)

Claimer → InterestReceiver.initialize() → _balance()
                                       → sets epoch state

Claimer → InterestReceiver.setClaimer()

User → SavingsEURe.permit() → _isValidSignature() → SignatureChecker.isValidSignatureNow()

EOA → InterestReceiver.claim() [direct, no adapter]
```

No reentrancy paths detected — InterestReceiver.claim() transfers EURe to vault (no callback), vault's deposit/receive has no hook back.
