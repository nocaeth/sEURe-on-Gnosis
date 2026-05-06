// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {IERC4626} from "openzeppelin/interfaces/IERC4626.sol";

/// @title ISavingsEURe
/// @notice ERC4626 vault for EURe deposits with ERC2612-style permit support.
/// @dev Extends the standard ERC4626 vault interface with EURe-specific metadata and a bytes-based permit overload
/// that supports both EOA signatures and ERC1271 contract wallet signatures.
interface ISavingsEURe is IERC4626 {
    /// @notice Interest dispatcher address is zero or not a deployed contract.
    error InvalidInterestDispatcher();

    /// @notice Caller is not the configured interest dispatcher.
    error NotInterestDispatcher();

    /// @notice Interest claiming is not enabled yet.
    error InterestClaimingNotEnabled();

    /// @notice Emitted when the configured dispatcher enables vault-side claim synchronization.
    event InterestClaimingEnabled();

    /// @notice Permit deadline has expired.
    error PermitExpired();

    /// @notice Permit owner cannot be the zero address.
    error InvalidOwner();

    /// @notice Permit signature is invalid for the owner, spender, value, nonce, or deadline.
    error InvalidPermit();

    /// @notice EIP712 type hash used for permit signatures.
    function PERMIT_TYPEHASH() external view returns (bytes32);

    /// @notice Dispatcher claimed before deposit, mint, withdraw, and redeem paths.
    function interestDispatcher() external view returns (address);

    /// @notice Whether vault share-changing operations claim dispatcher yield before accounting.
    function interestClaimingEnabled() external view returns (bool);

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

    /// @notice Returns the next unused permit nonce for `owner`.
    function nonces(address owner) external view returns (uint256);

    /// @notice Returns the EIP712 domain separator used for permit signatures.
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
