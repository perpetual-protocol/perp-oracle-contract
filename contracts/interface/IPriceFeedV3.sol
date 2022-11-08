// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

import "./IPriceFeed.sol";

interface IPriceFeedV3 {
    struct ChainlinkResponse {
        uint80 roundId;
        int256 answer;
        uint256 updatedAt;
        bool success;
        uint8 decimals;
    }

    /// @dev Returns the cached index price of the token.
    function cachePrice() external returns (uint256);

    function getLastValidPrice() external view returns (uint256);

    function isTimedOut() external view returns (bool);
}
