// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.20;

import {IERC20} from "openzeppelin/token/ERC20/IERC20.sol";
import {IERC4626} from "openzeppelin/interfaces/IERC4626.sol";
import {ERC20} from "openzeppelin/token/ERC20/ERC20.sol";
import {ERC4626} from "openzeppelin/token/ERC20/extensions/ERC4626.sol";
import {IInterestDispatcher} from "./interfaces/IInterestDispatcher.sol";
import {ISavingsEURe} from "./interfaces/ISavingsEURe.sol";
import {EIP712} from "openzeppelin/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "openzeppelin/utils/cryptography/SignatureChecker.sol";
import {Nonces} from "openzeppelin/utils/Nonces.sol";

contract SavingsEURe is ERC4626, ISavingsEURe, EIP712, Nonces {
    /// @inheritdoc ISavingsEURe
    bytes32 public constant override PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    /// @inheritdoc ISavingsEURe
    address public immutable override interestDispatcher;

    /// @inheritdoc ISavingsEURe
    bool public override interestClaimingEnabled;

    constructor(address interestDispatcher_)
        ERC20("Savings EURe", "sEURe")
        ERC4626(IERC20(0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430))
        EIP712("Savings EURe", "1")
    {
        if (interestDispatcher_ == address(0) || interestDispatcher_.code.length == 0) {
            revert ISavingsEURe.InvalidInterestDispatcher();
        }

        interestDispatcher = interestDispatcher_;
    }

    /// @inheritdoc ISavingsEURe
    function enableInterestClaiming() external override {
        if (msg.sender != interestDispatcher) revert ISavingsEURe.NotInterestDispatcher();

        interestClaimingEnabled = true;

        emit InterestClaimingEnabled();
    }

    function _claimInterest() internal {
        if (!interestClaimingEnabled) {
            return;
        }

        IInterestDispatcher(interestDispatcher).claim();
    }

    /// @inheritdoc ERC4626
    function totalAssets() public view override(ERC4626, IERC4626) returns (uint256) {
        if (!interestClaimingEnabled) return super.totalAssets();
        return super.totalAssets() + IInterestDispatcher(interestDispatcher).previewClaimable();
    }

    /// @inheritdoc ERC4626
    function deposit(uint256 assets, address receiver) public override(ERC4626, IERC4626) returns (uint256) {
        _claimInterest();
        return super.deposit(assets, receiver);
    }

    /// @inheritdoc ERC4626
    function mint(uint256 shares, address receiver) public override(ERC4626, IERC4626) returns (uint256) {
        _claimInterest();
        return super.mint(shares, receiver);
    }

    /// @inheritdoc ERC4626
    function withdraw(uint256 assets, address receiver, address owner)
        public
        override(ERC4626, IERC4626)
        returns (uint256)
    {
        _claimInterest();
        return super.withdraw(assets, receiver, owner);
    }

    /// @inheritdoc ERC4626
    function redeem(uint256 shares, address receiver, address owner)
        public
        override(ERC4626, IERC4626)
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

        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, _useNonce(owner), deadline));
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

    /// @inheritdoc ISavingsEURe
    function nonces(address owner) public view virtual override(ISavingsEURe, Nonces) returns (uint256) {
        return super.nonces(owner);
    }

    /// @inheritdoc ISavingsEURe
    function DOMAIN_SEPARATOR() external view virtual override returns (bytes32) {
        return _domainSeparatorV4();
    }

    function _decimalsOffset() internal pure override returns (uint8) {
        return 3;
    }
}
