// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.35;

/// @title Gnosis
/// @notice Canonical Gnosis Chain addresses referenced by this project.
/// @dev Values target chiado/mainnet-style deployments used in scripts and tests; verify before production use on other networks.
library Gnosis {
    /// @notice Monerium EURe ERC-20 on Gnosis mainnet (also used as the default asset address in tests).
    address internal constant EURe = 0x420CA0f9B9b604cE0fd9C18EF134C705e5Fa3430;
}
