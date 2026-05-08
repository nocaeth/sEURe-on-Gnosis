// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.35;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {ERC4626} from "openzeppelin/token/ERC20/extensions/ERC4626.sol";
import {Gnosis} from "./constants/Gnosis.sol";
import {IInterestDispatcher} from "./interfaces/IInterestDispatcher.sol";
import {ISavingsEURe} from "./interfaces/ISavingsEURe.sol";
import {EIP712} from "openzeppelin/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "openzeppelin/utils/cryptography/SignatureChecker.sol";
import {Nonces} from "openzeppelin/utils/Nonces.sol";

/// @title SavingsEURe
/// @notice ERC-4626 vault for Monerium EURe on Gnosis (`ISavingsEURe`).
/// @dev Behavioral contract: see documented expectations on `ISavingsEURe` (dispatcher binding, claim ordering, `totalAssets`, native ETH).
contract SavingsEURe is ERC4626, ISavingsEURe, EIP712, Nonces {
    /*//////////////////////////////////////////////////////////////
                                CONSTANTS
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISavingsEURe
    bytes32 public constant override PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    /*//////////////////////////////////////////////////////////////
                               IMMUTABLES
    //////////////////////////////////////////////////////////////*/

    address private immutable INTEREST_DISPATCHER;

    /*//////////////////////////////////////////////////////////////
                                 STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISavingsEURe
    bool public override interestClaimingEnabled;

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/

    /// @param interestDispatcher_ Deployed `IInterestDispatcher` (typically ERC-1967 proxy); MUST be non-zero with bytecode (`InvalidInterestDispatcher`).
    constructor(address interestDispatcher_)
        ERC20("Savings EURe", "sEURe")
        ERC4626(IERC20(Gnosis.EURe))
        EIP712("Savings EURe", "1")
    {
        if (interestDispatcher_ == address(0) || interestDispatcher_.code.length == 0) {
            revert ISavingsEURe.InvalidInterestDispatcher();
        }

        INTEREST_DISPATCHER = interestDispatcher_;
    }

    /*//////////////////////////////////////////////////////////////
                                MUTATIVE
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISavingsEURe
    function enableInterestClaiming() external override {
        if (msg.sender != INTEREST_DISPATCHER) revert ISavingsEURe.NotInterestDispatcher();

        interestClaimingEnabled = true;

        emit InterestClaimingEnabled();
    }

    /// @inheritdoc ISavingsEURe
    function deposit(uint256 assets, address receiver) public override(ERC4626, ISavingsEURe) returns (uint256) {
        _claimInterest();
        return super.deposit(assets, receiver);
    }

    /// @inheritdoc ISavingsEURe
    function mint(uint256 shares, address receiver) public override(ERC4626, ISavingsEURe) returns (uint256) {
        _claimInterest();
        return super.mint(shares, receiver);
    }

    /// @inheritdoc ISavingsEURe
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override(ERC4626, ISavingsEURe)
        returns (uint256)
    {
        _claimInterest();
        return super.withdraw(assets, receiver, owner);
    }

    /// @inheritdoc ISavingsEURe
    function redeem(uint256 shares, address receiver, address owner)
        public
        override(ERC4626, ISavingsEURe)
        returns (uint256)
    {
        _claimInterest();
        return super.redeem(shares, receiver, owner);
    }

    /// @inheritdoc ISavingsEURe
    function permit(address owner, address spender, uint256 value, uint256 deadline, bytes memory signature)
        public
        override
    {
        if (block.timestamp > deadline) {
            revert ISavingsEURe.PermitExpired();
        }
        if (owner == address(0)) {
            revert ISavingsEURe.InvalidOwner();
        }

        uint256 nonce = _useNonce(owner);
        bytes32 typeHash = PERMIT_TYPEHASH;
        bytes32 structHash;
        assembly ("memory-safe") {
            let ptr := mload(0x40)
            mstore(ptr, typeHash)
            mstore(add(ptr, 0x20), and(owner, 0xffffffffffffffffffffffffffffffffffffffff))
            mstore(add(ptr, 0x40), and(spender, 0xffffffffffffffffffffffffffffffffffffffff))
            mstore(add(ptr, 0x60), value)
            mstore(add(ptr, 0x80), nonce)
            mstore(add(ptr, 0xa0), deadline)
            structHash := keccak256(ptr, 0xc0)
            mstore(0x40, add(ptr, 0xc0))
        }
        bytes32 digest = _hashTypedDataV4(structHash);

        if (!SignatureChecker.isValidSignatureNow(owner, digest, signature)) {
            revert ISavingsEURe.InvalidPermit();
        }

        _approve(owner, spender, value);
    }

    /// @inheritdoc ISavingsEURe
    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external
        override
    {
        permit(owner, spender, value, deadline, abi.encodePacked(r, s, v));
    }

    /// @notice Reverts with `NoNativeDeposits`; EURe / ERC-4626 paths only (`ISavingsEURe`).
    receive() external payable {
        revert ISavingsEURe.NoNativeDeposits();
    }

    /*//////////////////////////////////////////////////////////////
                                  VIEW
    //////////////////////////////////////////////////////////////*/

    /// @inheritdoc ISavingsEURe
    function totalAssets() public view override(ERC4626, ISavingsEURe) returns (uint256) {
        if (!interestClaimingEnabled) return super.totalAssets();
        return super.totalAssets() + IInterestDispatcher(INTEREST_DISPATCHER).previewClaimable();
    }

    /// @inheritdoc ISavingsEURe
    function nonces(address owner) public view virtual override(ISavingsEURe, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

    /// @inheritdoc ISavingsEURe
    function DOMAIN_SEPARATOR() external view virtual override returns (bytes32) {
        return _domainSeparatorV4();
    }

    /// @inheritdoc ISavingsEURe
    function interestDispatcher() external view override returns (address) {
        return INTEREST_DISPATCHER;
    }

    /*//////////////////////////////////////////////////////////////
                                INTERNAL
    //////////////////////////////////////////////////////////////*/

    /// @dev Invokes `IInterestDispatcher.claim()` when `interestClaimingEnabled` is true; no-op otherwise.
    function _claimInterest() internal {
        if (!interestClaimingEnabled) {
            return;
        }

        IInterestDispatcher(INTEREST_DISPATCHER).claim();
    }

    /// @dev Overrides the ERC-4626 default offset (`0`) with `3`, so share decimals are three less than the underlying EURe (18 → 15).
    function _decimalsOffset() internal pure override returns (uint8) {
        return 3;
    }
}
