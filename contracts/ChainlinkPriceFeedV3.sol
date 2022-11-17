// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import { IChainlinkPriceFeed } from "./interface/IChainlinkPriceFeed.sol";
import { IPriceFeedV3 } from "./interface/IPriceFeedV3.sol";
import { BlockContext } from "./base/BlockContext.sol";
import { CachedTwap } from "./twap/CachedTwap.sol";

contract ChainlinkPriceFeedV3 is IPriceFeedV3, BlockContext, CachedTwap {
    using SafeMath for uint256;
    using Address for address;

    //
    // STATE
    //

    uint24 private constant _ONE_HUNDRED_PERCENT_RATIO = 1e6;
    uint8 internal immutable _decimals;
    uint24 internal immutable _maxOutlierDeviationRatio;
    uint256 internal immutable _outlierCoolDownPeriod;
    uint256 internal immutable _timeout;
    uint256 internal _lastValidPrice;
    uint256 internal _lastValidTime;
    AggregatorV3Interface internal immutable _aggregator;

    //
    // EXTERNAL NON-VIEW
    //

    constructor(
        AggregatorV3Interface aggregator,
        uint256 timeout,
        uint24 maxOutlierDeviationRatio,
        uint256 outlierCoolDownPeriod,
        uint80 twapInterval
    ) CachedTwap(twapInterval) {
        // CPF_ANC: Aggregator is not contract
        require(address(aggregator).isContract(), "CPF_ANC");
        _aggregator = aggregator;

        // CPF_IMODR: Invalid maxOutlierDeviationRatio
        require(maxOutlierDeviationRatio < _ONE_HUNDRED_PERCENT_RATIO, "CPF_IMODR");
        _maxOutlierDeviationRatio = maxOutlierDeviationRatio;

        _outlierCoolDownPeriod = outlierCoolDownPeriod;
        _timeout = timeout;
        _decimals = aggregator.decimals();
    }

    function cacheTwap(uint256 interval) external override returns (uint256) {
        uint256 lastValidTime = _lastValidTime;
        _cachePrice();

        // 1. if interval == 0, won't cache twap
        // 2. else if the price doesn't get updated (_lastValidTime == lastValidTime),
        //    return the previous cached value (_cachedTwap)
        // 3. else, cache twap
        return
            interval == 0 ? _lastValidPrice : _lastValidTime == lastValidTime
                ? _cachedTwap
                : _cacheTwap(interval, _lastValidPrice, _lastValidTime);
    }

    //
    // EXTERNAL VIEW
    //

    function getAggregator() external view returns (address) {
        return address(_aggregator);
    }

    function getLastValidPrice() external view override returns (uint256) {
        return _lastValidPrice;
    }

    function getLastValidTime() external view override returns (uint256) {
        return _lastValidTime;
    }

    function getCachedTwap(uint256 interval) external view override returns (uint256) {
        if (interval == 0) {
            return _lastValidPrice;
        }

        return _getCachedTwap(interval, _lastValidPrice, _lastValidTime);
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function isTimedOut() external view override returns (bool) {
        return _lastValidTime.add(_timeout) > _blockTimestamp();
    }

    //
    // INTERNAL
    //

    function _cachePrice() internal {
        ChainlinkResponse memory response = _getChainlinkData();
        if (_lastValidTime != 0 && _lastValidTime == response.updatedAt) {
            return;
        }

        FreezedReason freezedReason = _getFreezedReason(response);
        if (freezedReason == FreezedReason.NotFreezed) {
            _lastValidPrice = uint256(response.answer);
            _lastValidTime = response.updatedAt;
        } else if (
            freezedReason == FreezedReason.AnswerIsOutlier &&
            _blockTimestamp() > _lastValidTime.add(_outlierCoolDownPeriod)
        ) {
            uint24 deviationRatio =
                uint256(response.answer) > _lastValidPrice
                    ? _ONE_HUNDRED_PERCENT_RATIO + _maxOutlierDeviationRatio
                    : _ONE_HUNDRED_PERCENT_RATIO - _maxOutlierDeviationRatio;
            _lastValidPrice = _mulRatio(_lastValidPrice, deviationRatio);
            _lastValidTime = _blockTimestamp();
        }

        emit ChainlinkPriceUpdated(_lastValidPrice, _lastValidTime, freezedReason);
    }

    function _getChainlinkData() internal view returns (ChainlinkResponse memory chainlinkResponse) {
        try _aggregator.decimals() returns (uint8 decimals) {
            chainlinkResponse.decimals = decimals;
        } catch {
            return chainlinkResponse;
        }

        try _aggregator.latestRoundData() returns (
            uint80 roundId,
            int256 answer,
            uint256, // startedAt
            uint256 updatedAt,
            uint80 // answeredInRound
        ) {
            // If call to Chainlink succeeds, return the response and success = true
            chainlinkResponse.roundId = roundId;
            chainlinkResponse.answer = answer;
            chainlinkResponse.updatedAt = updatedAt;
            chainlinkResponse.success = true;
            return chainlinkResponse;
        } catch {
            // If call to Chainlink aggregator reverts, return a zero response with success = false
            return chainlinkResponse;
        }
    }

    function _getFreezedReason(ChainlinkResponse memory response) internal view returns (FreezedReason) {
        /*
        1. no response
        2. incorrect decimals
        3. no roundId
        4. no timestamp or it’s invalid (in the future)
        5. none positive price
        6. outlier
        */
        if (!response.success) {
            return FreezedReason.NoResponse;
        }
        if (response.decimals != _decimals) {
            return FreezedReason.IncorrectDecimals;
        }
        if (response.roundId == 0) {
            return FreezedReason.NoRoundId;
        }
        if (response.updatedAt == 0 || response.updatedAt < _lastValidTime || response.updatedAt > _blockTimestamp()) {
            return FreezedReason.InvalidTimestamp;
        }
        if (response.answer <= 0) {
            return FreezedReason.NonPositiveAnswer;
        }
        if (_lastValidPrice != 0 && _lastValidTime != 0 && _isOutlier(uint256(response.answer))) {
            return FreezedReason.AnswerIsOutlier;
        }

        return FreezedReason.NotFreezed;
    }

    function _isOutlier(uint256 price) internal view returns (bool) {
        uint256 diff = _lastValidPrice >= price ? _lastValidPrice - price : price - _lastValidPrice;
        uint256 deviationRatio = diff.mul(_ONE_HUNDRED_PERCENT_RATIO).div(_lastValidPrice);
        return deviationRatio >= _maxOutlierDeviationRatio;
    }

    function _mulRatio(uint256 value, uint24 ratio) internal pure returns (uint256) {
        return value.mul(ratio).div(_ONE_HUNDRED_PERCENT_RATIO);
    }
}
