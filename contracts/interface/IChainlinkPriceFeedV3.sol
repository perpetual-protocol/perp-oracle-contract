// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

interface IChainlinkPriceFeedV3Event {
    /// @param NotFreezed default state: Chainlink is working as expected
    /// @param NoResponse fails to call Chainlink
    /// @param InvalidTimestamp no timestamp or it’s invalid, either outdated or in the future
    enum FreezedReason { NotFreezed, NoResponse, IncorrectDecimals, NoRoundId, InvalidTimestamp, NonPositiveAnswer }

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

    /// @param interval twap interval
    ///        when 0, cache price only, without twap; else, cache price & twap
    /// @dev this is the non-view version of cacheTwap() without return value
    function cacheTwap(uint256 interval) external;

    /// @notice Get the last cached valid price
    function getLastValidPrice() external view returns (uint256);

    /// @notice Get the last cached valid timestamp
    function getLastValidTimestamp() external view returns (uint256);

    /// @notice If the interval is zero, returns the latest valid price.
    ///         Else, returns TWAP calculating with the latest valid price and timestamp.
    /// @param interval twap interval
    /// @dev this is the view version of cacheTwap()
    function getPrice(uint256 interval) external view returns (uint256);

    /// @notice Retrieve the latest price and timestamp from Chainlink aggregator,
    ///         or return the last cached valid price and timestamp if the aggregator hasn't been updated or is frozen.
    function getLatestOrCachedPrice() external view returns (uint256, uint256);

    function isTimedOut() external view returns (bool);

    function getFreezedReason() external view returns (FreezedReason);

    function getAggregator() external view returns (address);

    function getTimeout() external view returns (uint256);

    function decimals() external view returns (uint8);
}
