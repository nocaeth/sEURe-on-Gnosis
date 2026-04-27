# Modifiers

## InterestReceiver
- `isInitialized` — checks `_getInitializedVersion() != 0`
- `isClaimer` — checks `tx.origin == msg.sender` OR `msg.sender == claimer`
