// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {ERC4626} from "openzeppelin/token/ERC20/extensions/ERC4626.sol";
import {ISavingsEURe} from "./interfaces/ISavingsEURe.sol";
import {EIP712} from "openzeppelin/utils/cryptography/EIP712.sol";
import {Nonces} from "openzeppelin/utils/Nonces.sol";
import {SignatureChecker} from "openzeppelin/utils/cryptography/SignatureChecker.sol";

contract SavingsEURe is ERC4626, ISavingsEURe, EIP712, Nonces {
    // --- EIP712 niceties ---
    /// @inheritdoc ISavingsEURe
    bytes32 public constant override PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    constructor()
        ERC20("Savings EURe", "sEURe")
        ERC4626(IERC20(0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430))
        EIP712("Savings EURe", "1")
    {}

    function _decimalsOffset() internal pure override returns (uint8) {
        return 3;
    }

    // --- Approve by signature ---

    function _isValidSignature(address signer, bytes32 digest, bytes memory signature) internal view returns (bool) {
        return SignatureChecker.isValidSignatureNow(signer, digest, signature);
    }

    /// @inheritdoc ISavingsEURe
    function permit(address owner, address spender, uint256 value, uint256 deadline, bytes memory signature)
        public
        override
    {
        if (block.timestamp > deadline) revert PermitExpired();
        if (owner == address(0)) revert InvalidOwner();

        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, _useNonce(owner), deadline));
        bytes32 digest = _hashTypedDataV4(structHash);

        if (!_isValidSignature(owner, digest, signature)) revert InvalidPermit();

        _approve(owner, spender, value);
    }

    /// @inheritdoc ISavingsEURe
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        override
    {
        permit(owner, spender, value, deadline, abi.encodePacked(r, s, v));
    }

    /// @inheritdoc ISavingsEURe
    function nonces(address owner) public view virtual override(ISavingsEURe, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

    /// @inheritdoc ISavingsEURe
    // solhint-disable-next-line func-name-mixedcase
    function DOMAIN_SEPARATOR() external view virtual override returns (bytes32) {
        return _domainSeparatorV4();
    }
}
