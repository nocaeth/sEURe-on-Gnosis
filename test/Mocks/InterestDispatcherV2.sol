// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.35;

import {InterestDispatcher} from "src/InterestDispatcher.sol";

/// @dev Stand-in “V2” implementation for UUPS upgrade tests (adds a probe function; storage layout unchanged).
contract InterestDispatcherV2 is InterestDispatcher {
    function version() external pure returns (uint256) {
        return 2;
    }
}
