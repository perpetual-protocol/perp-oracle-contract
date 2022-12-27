// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

import "./IPriceFeed.sol";

interface IPriceFeedV2 is IPriceFeed {
    /// @dev Returns the cached index price of the token.
    /// @param interval The interval represents twap interval.
    function cacheTwap(uint256 interval) external returns (uint256);
}
