// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.35;

import {IERC4626} from "openzeppelin/interfaces/IERC4626.sol";

/// @title ISavingsEURe
/// @notice ERC-4626 vault interface for EURe savings shares with optional synchronized yield from `IInterestDispatcher` and EIP-712 permit (EOA + ERC-1271).
/// @dev
/// Extends `IERC4626` with a bytes-based `permit` overload compatible with `SignatureChecker` (not only 65-byte ECDSA).
///
/// **`SavingsEURe` expectations:** immutable deployed `IInterestDispatcher` at construction (`InvalidInterestDispatcher`); native ETH rejected (`NoNativeDeposits`).
/// ERC-4626 functions below restate IERC4626 signatures with documentation inherited from ERC-4626 plus vault-specific notes in each NatSpec dev clause.
interface ISavingsEURe is IERC4626 {
    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    /// @notice Emitted when the configured dispatcher enables vault-side claim synchronization.
    event InterestClaimingEnabled();

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    /// @notice Interest dispatcher address is zero or not a deployed contract.
    error InvalidInterestDispatcher();

    /// @notice Caller is not the configured interest dispatcher.
    error NotInterestDispatcher();

    /// @notice Vault does not accept native token; use EURe / ERC-4626 paths.
    error NoNativeDeposits();

    /// @notice Permit deadline has expired.
    error PermitExpired();

    /// @notice Permit owner cannot be the zero address.
    error InvalidOwner();

    /// @notice Permit signature is invalid for the owner, spender, value, nonce, or deadline.
    error InvalidPermit();

    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @notice EIP-712 struct type hash for permit: `Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)`.
    function PERMIT_TYPEHASH() external view returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                          ERC-4626 — THIS VAULT
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc IERC4626
    /// @dev When `interestClaimingEnabled`, implementations MUST add `IInterestDispatcher.previewClaimable()` to EURe held by the vault. Mutating ERC-4626 functions MUST call `IInterestDispatcher.claim()` first so balances align with this measure.
    function totalAssets() external view returns (uint256 totalManagedAssets);

    /// @inheritdoc IERC4626
    /// @dev When `interestClaimingEnabled`, implementations MUST call `IInterestDispatcher.claim()` before the inherited deposit path.
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    /// @inheritdoc IERC4626
    /// @dev When `interestClaimingEnabled`, implementations MUST call `IInterestDispatcher.claim()` before the inherited mint path.
    function mint(uint256 shares, address receiver) external returns (uint256 assets);

    /// @inheritdoc IERC4626
    /// @dev When `interestClaimingEnabled`, implementations MUST call `IInterestDispatcher.claim()` before the inherited withdraw path.
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);

    /// @inheritdoc IERC4626
    /// @dev When `interestClaimingEnabled`, implementations MUST call `IInterestDispatcher.claim()` before the inherited redeem path.
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);

    /*//////////////////////////////////////////////////////////////
                                  VIEW
    //////////////////////////////////////////////////////////////*/

    /// @notice Address of the interest dispatcher this vault invokes before share-changing operations when enabled.
    /// @return dispatcher Immutable `InterestDispatcher` (proxy) configured at vault deployment.
    function interestDispatcher() external view returns (address);

    /// @notice Whether share-changing operations pull claimable EURe via the dispatcher before ERC-4626 math.
    /// @return enabled Set to true when the dispatcher calls `enableInterestClaiming` during `bootstrap`.
    function interestClaimingEnabled() external view returns (bool);

    /// @notice Next unconsumed EIP-712 permit nonce for `owner` (replay protection).
    /// @param owner Address whose permit nonce is queried.
    /// @return nonce Current nonce value before the next successful `permit`.
    function nonces(address owner) external view returns (uint256);

    /// @notice EIP-712 `DOMAIN_SEPARATOR` for this vault (`name` / `version` / chain id / verifying contract).
    /// @return separator Domain separator bytes32 used when hashing permit structs.
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /*//////////////////////////////////////////////////////////////
                                MUTATIVE
    //////////////////////////////////////////////////////////////*/

    /// @notice Enables dispatcher claim synchronization before vault share-changing operations.
    function enableInterestClaiming() external;

    /// @notice Sets `value` as `spender`'s allowance over `owner`'s shares using an EIP712 signature.
    /// @dev Accepts a standard 65-byte ECDSA signature for EOAs or arbitrary ERC1271 signature data for contract wallets.
    /// @param owner Share owner granting the allowance.
    /// @param spender Address receiving the allowance.
    /// @param value Allowance amount in SavingsEURe shares.
    /// @param deadline Last timestamp at which the signature is valid.
    /// @param signature EOA or ERC1271 signature authorizing the permit.
    function permit(address owner, address spender, uint256 value, uint256 deadline, bytes memory signature) external;

    /// @notice Sets `value` as `spender`'s allowance over `owner`'s shares using a standard ECDSA permit signature.
    /// @param owner Share owner granting the allowance.
    /// @param spender Address receiving the allowance.
    /// @param value Allowance amount in SavingsEURe shares.
    /// @param deadline Last timestamp at which the signature is valid.
    /// @param v Signature recovery id.
    /// @param r Signature r value.
    /// @param s Signature s value.
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;
}
