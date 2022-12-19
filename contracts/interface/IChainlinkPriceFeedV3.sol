// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

interface IChainlinkPriceFeedV3Event {
    /// @param NotFreezed default state: Chainlink is working as expected
    /// @param NoResponse fails to call Chainlink
    /// @param InvalidTimestamp no timestamp or it’s invalid, either outdated or in the future
    /// @param AnswerIsOutlier if the answer deviates more than _maxOutlierDeviationRatio
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

    /// @param interval twap interval
    ///        when 0, cache price only, without twap; else, cache price & twap
    /// @dev this is the non-view version of cacheTwap() without return value
    function cacheTwap(uint256 interval) external;

    function getLastValidPrice() external view returns (uint256);

    function getLastValidTimestamp() external view returns (uint256);

    /// @param interval twap interval
    /// @dev this is the view version of cacheTwap()
    function getCachedTwap(uint256 interval) external view returns (uint256);

    function isTimedOut() external view returns (bool);

    function getFreezedReason() external view returns (FreezedReason);

    function getAggregator() external view returns (address);

    function decimals() external view returns (uint8);
}
