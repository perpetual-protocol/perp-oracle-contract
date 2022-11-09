// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

import "./IPriceFeed.sol";

interface IPriceFeedV3Event {
    enum FreezedReason {
        NotFreezed,
        NoResponse,
        IncorrectDecimals,
        NoRoundId,
        InvalidTimestamp,
        NonPositiveAnswer,
        PotentialOutlier
    }

    event PriceUpdated(uint256 price, uint256 timestamp, FreezedReason freezedReason);
}

interface IPriceFeedV3 is IPriceFeedV3Event {
    struct ChainlinkResponse {
        uint80 roundId;
        int256 answer;
        uint256 updatedAt;
        bool success;
        uint8 decimals;
    }

    /// @dev Returns the cached index price of the token.
    function cachePrice() external returns (uint256);

    function decimals() external view returns (uint8);

    function getLastValidPrice() external view returns (uint256);

    function isTimedOut() external view returns (bool);
}
