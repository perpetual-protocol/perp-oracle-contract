// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

interface IChainlinkPriceFeedV3Event {
    /// @param NotFreezed Default state: Chainlink is working as expected
    /// @param NoResponse Fails to call Chainlink
    /// @param IncorrectDecimals Inconsistent decimals between aggregator and price feed
    /// @param NoRoundId Zero round Id
    /// @param InvalidTimestamp No timestamp or it’s invalid, either outdated or in the future
    /// @param NonPositiveAnswer Price is zero or negative
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

    /// @param interval TWAP interval
    ///        when 0, cache price only, without TWAP; else, cache price & twap
    /// @dev This is the non-view version of cacheTwap() without return value
    function cacheTwap(uint256 interval) external;

    /// @notice Get the last cached valid price
    /// @return price The last cached valid price
    function getLastValidPrice() external view returns (uint256 price);

    /// @notice Get the last cached valid timestamp
    /// @return timestamp The last cached valid timestamp
    function getLastValidTimestamp() external view returns (uint256 timestamp);

    /// @notice Retrieve the latest price and timestamp from Chainlink aggregator,
    ///         or return the last cached valid price and timestamp if the aggregator hasn't been updated or is frozen.
    /// @return price The latest valid price
    /// @return timestamp The latest valid timestamp
    function getLatestOrCachedPrice() external view returns (uint256 price, uint256 timestamp);

    function isTimedOut() external view returns (bool isTimedOut);

    /// @return reason The freezen reason
    function getFreezedReason() external view returns (FreezedReason reason);

    /// @return aggregator The address of Chainlink price feed aggregator
    function getAggregator() external view returns (address aggregator);

    /// @return period The timeout period
    function getTimeout() external view returns (uint256 period);
}
