// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

import "./IPriceFeed.sol";

interface IChainlinkPriceFeedV3Event {
    enum FreezedReason {
        NotFreezed,
        NoResponse,
        IncorrectDecimals,
        NoRoundId,
        InvalidTimestamp,
        NonPositiveAnswer,
        AnswerIsOutlier
    }

    event ChainlinkPriceUpdated(uint256 price, uint256 timestamp, FreezedReason freezedReason);
}

interface IChainlinkPriceFeedV3 is IChainlinkPriceFeedV3Event {
    struct ChainlinkResponse {
        uint80 roundId;
        int256 answer;
        uint256 updatedAt;
        bool success;
        uint8 decimals;
    }

    /// @dev Returns the cached index price of the token.
    function cacheTwap(uint256 interval) external;

    function decimals() external view returns (uint8);

    function getLastValidPrice() external view returns (uint256);

    function getCachedTwap(uint256 interval) external view returns (uint256);

    function getLastValidTime() external view returns (uint256);

    function isTimedOut() external view returns (bool);
}
