# Function List

## SavingsEURe (src/SavingsEURe.sol)
- `constructor()` — sets ERC20("Savings EURe","sEURe"), ERC4626(EURe), EIP712("Savings EURe","1")
- `_decimalsOffset() → 3` — inflation protection virtual offset
- `_isValidSignature(signer, digest, signature) → bool` — wraps SignatureChecker
- `permit(owner, spender, value, deadline, signature)` — bytes-based permit (EOA + ERC1271)
- `permit(owner, spender, value, deadline, v, r, s)` — vrs-based permit
- `nonces(owner) → uint256` — nonce override (ISavingsEURe + Nonces)
- `DOMAIN_SEPARATOR() → bytes32` — EIP712 domain separator
- Inherited from ERC4626: `deposit`, `mint`, `withdraw`, `redeem`, `totalAssets`, `convertToShares`, `convertToAssets`, `previewDeposit`, `previewMint`, `previewWithdraw`, `previewRedeem`, `maxDeposit`, `maxMint`, `maxWithdraw`, `maxRedeem`, `asset`
- Inherited from ERC20: `transfer`, `transferFrom`, `approve`, `allowance`, `balanceOf`, `totalSupply`, `name`, `symbol`, `decimals`

## InterestReceiver (src/InterestReceiver.sol)
- `constructor(address _vault)` — sets sEURe, claimer=msg.sender
- `_requireInitialized()` — reverts if not initialized
- `_requireClaimer()` — reverts if tx.origin!=msg.sender AND msg.sender!=claimer
- `initialize()` — initializer, sets epoch params from current balance
- `claim() → uint256` — transfers claimable EURe to vault, updates epoch state
- `_calculateClaim(balance) → (claimable, nextEpochBalance, nextDripRate, nextClaimEpoch)` — pure calc
- `_balance() → uint256` — returns eure.balanceOf(address(this))
- `vaultAPY() → uint256` — annualized dripRate / totalAssets
- `setClaimer(address newClaimer)` — one-step claimer transfer

## SavingsEUReAdapter (src/periphery/SavingsEUReAdapter.sol)
- `constructor(interestReceiver_, savingsEuRe_)` — sets refs, max-approves EURe to vault
- `_claimHook()` — calls interestReceiver.claim() in try/catch (EOA only)
- `deposit(assets, receiver) → uint256` — transferFrom + sEURe.deposit
- `mint(shares, receiver) → uint256` — transferFrom(previewMint) + sEURe.mint
- `withdraw(assets, receiver) → uint256` — clamps to maxWithdraw + sEURe.withdraw
- `redeem(shares, receiver) → uint256` — clamps to maxRedeem + sEURe.redeem
- `redeemAll(receiver) → uint256` — redeems full balanceOf
- `vaultAPY() → uint256` — delegates to interestReceiver
