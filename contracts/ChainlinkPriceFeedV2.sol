// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import { IPriceFeedV2 } from "./interface/IPriceFeedV2.sol";
import { BlockContext } from "./base/BlockContext.sol";
import { CachedTwap } from "./twap/CachedTwap.sol";

contract ChainlinkPriceFeedV2 is IPriceFeedV2, BlockContext, CachedTwap {
    using Address for address;

    AggregatorV3Interface private immutable _aggregator;

    constructor(AggregatorV3Interface aggregator, uint80 cacheTwapInterval) CachedTwap(cacheTwapInterval) {
        // CPF_ANC: Aggregator address is not contract
        require(address(aggregator).isContract(), "CPF_ANC");

        _aggregator = aggregator;
    }

    /// @dev anyone can help update it.
    function update() external {
        (, uint256 latestPrice, uint256 latestTimestamp) = _getLatestRoundData();
        _update(latestPrice, latestTimestamp);
    }

    function cacheTwap(uint256 interval) external override returns (uint256) {
        (uint80 round, uint256 latestPrice, uint256 latestTimestamp) = _getLatestRoundData();

        if (interval == 0 || round == 0) {
            return latestPrice;
        }
        return _cacheTwap(interval, latestPrice, latestTimestamp);
    }

    function decimals() external view override returns (uint8) {
        return _aggregator.decimals();
    }

    function getAggregator() external view returns (address) {
        return address(_aggregator);
    }

    function getPrice(uint256 interval) external view override returns (uint256) {
        (uint80 round, uint256 latestPrice, uint256 latestTimestamp) = _getLatestRoundData();

        if (interval == 0 || round == 0) {
            return latestPrice;
        }

        return _getCachedTwap(interval, latestPrice, latestTimestamp);
    }

    function _getLatestRoundData()
        private
        view
        returns (
            uint80,
            uint256 finalPrice,
            uint256
        )
    {
        (uint80 round, int256 latestPrice, , uint256 latestTimestamp, ) = _aggregator.latestRoundData();
        finalPrice = uint256(latestPrice);
        if (latestPrice < 0) {
            _requireEnoughHistory(round);
            (round, finalPrice, latestTimestamp) = _getRoundData(round - 1);
        }
        return (round, finalPrice, latestTimestamp);
    }

    function _getRoundData(uint80 _round)
        private
        view
        returns (
            uint80,
            uint256,
            uint256
        )
    {
        (uint80 round, int256 latestPrice, , uint256 latestTimestamp, ) = _aggregator.getRoundData(_round);
        while (latestPrice < 0) {
            _requireEnoughHistory(round);
            round = round - 1;
            (, latestPrice, , latestTimestamp, ) = _aggregator.getRoundData(round);
        }
        return (round, uint256(latestPrice), latestTimestamp);
    }

    function _requireEnoughHistory(uint80 _round) private pure {
        // CPF_NEH: no enough history
        require(_round > 0, "CPF_NEH");
    }
}
