// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

interface IChainlinkPriceFeed {
    function getAggregator() external view returns (address);

    /// @param roundId The roundId that fed into Chainlink aggregator.
    function getRoundData(uint80 roundId) external view returns (uint256, uint256);
}
