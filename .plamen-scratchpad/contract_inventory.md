# Contract Inventory

| Contract | File | Lines | In Scope? | Inheritance |
|----------|------|-------|-----------|-------------|
| SavingsEURe | src/SavingsEURe.sol | 69 | YES | ERC4626, ISavingsEURe, EIP712, Nonces |
| InterestReceiver | src/InterestReceiver.sol | 162 | YES | Initializable, IInterestReceiver |
| SavingsEUReAdapter | src/periphery/SavingsEUReAdapter.sol | 78 | YES | ISavingsEUReAdapter |
| ISavingsEURe | src/interfaces/ISavingsEURe.sol | 49 | interface | IERC4626 |
| IInterestReceiver | src/interfaces/IInterestReceiver.sol | 96 | interface | — |
| ISavingsEUReAdapter | src/interfaces/ISavingsEUReAdapter.sol | 52 | interface | — |

Total: 6 files, ~505 lines, 3 implementation contracts + 3 interfaces

### Inheritance Analysis
- SavingsEURe → ERC4626 (OZ) → significant vault logic with conditional branches
- InterestReceiver → Initializable (OZ) — uses `_getInitializedVersion()` guard
- No PARENT_CONDITIONAL_OVERRIDE flags — OZ parents are well-audited
- No proxy pattern detected (no upgradeable, no UUPS, no transparent proxy)
