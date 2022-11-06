// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

import "./IPriceFeed.sol";

interface IPriceFeedV3 {
    /// @dev Returns the cached index price of the token.
    function cachePrice() external returns (uint256);
}
