// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import { IChainlinkPriceFeed } from "./interface/IChainlinkPriceFeed.sol";
import { IChainlinkPriceFeedV3 } from "./interface/IChainlinkPriceFeedV3.sol";
import { BlockContext } from "./base/BlockContext.sol";
import { CachedTwap } from "./twap/CachedTwap.sol";

contract ChainlinkPriceFeedV3 is IChainlinkPriceFeedV3, BlockContext, CachedTwap {
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
    uint256 internal _lastValidTimestamp;
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

    /// @inheritdoc IChainlinkPriceFeedV3
    function cacheTwap(uint256 interval) external override {
        _cachePrice();

        if (interval != 0) {
            _cacheTwap(interval, _lastValidPrice, _lastValidTimestamp);
        }
    }

    //
    // EXTERNAL VIEW
    //

    function getLastValidPrice() external view override returns (uint256) {
        return _lastValidPrice;
    }

    function getLastValidTimestamp() external view override returns (uint256) {
        return _lastValidTimestamp;
    }

    /// @inheritdoc IChainlinkPriceFeedV3
    function getCachedTwap(uint256 interval) external view override returns (uint256) {
        (uint256 latestValidPrice, uint256 latestValidTime) = _getCachePrice();

        if (interval == 0) {
            return latestValidPrice;
        }

        return _getCachedTwap(interval, latestValidPrice, latestValidTime);
    }

    function getAggregator() external view override returns (address) {
        return address(_aggregator);
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function isTimedOut() external view override returns (bool) {
        return _lastValidTimestamp.add(_timeout) > _blockTimestamp();
    }

    //
    // INTERNAL
    //

    function _cachePrice() internal {
        ChainlinkResponse memory response = _getChainlinkResponse();
        if (_lastValidTimestamp != 0 && _lastValidTimestamp == response.updatedAt) {
            return;
        }

        FreezedReason freezedReason = _getFreezedReason(response);
        if (freezedReason == FreezedReason.NotFreezed) {
            _lastValidPrice = uint256(response.answer);
            _lastValidTimestamp = response.updatedAt;
        } else if (
            freezedReason == FreezedReason.AnswerIsOutlier &&
            _blockTimestamp() > _lastValidTimestamp.add(_outlierCoolDownPeriod)
        ) {
            (_lastValidPrice, _lastValidTimestamp) = _getPriceAndTimestampAfterOutlierCoolDown(response.answer);
        }

        emit ChainlinkPriceUpdated(_lastValidPrice, _lastValidTimestamp, freezedReason);
    }

    function _getCachePrice() internal view returns (uint256, uint256) {
        ChainlinkResponse memory response = _getChainlinkResponse();
        if (_lastValidTimestamp != 0 && _lastValidTimestamp == response.updatedAt) {
            return (_lastValidPrice, _lastValidTimestamp);
        }

        FreezedReason freezedReason = _getFreezedReason(response);
        if (freezedReason == FreezedReason.NotFreezed) {
            return (uint256(response.answer), response.updatedAt);
        } else if (
            freezedReason == FreezedReason.AnswerIsOutlier &&
            _blockTimestamp() > _lastValidTimestamp.add(_outlierCoolDownPeriod)
        ) {
            return (_getPriceAndTimestampAfterOutlierCoolDown(response.answer));
        }

        return (_lastValidPrice, _lastValidTimestamp);
    }

    function _getChainlinkResponse() internal view returns (ChainlinkResponse memory chainlinkResponse) {
        try _aggregator.decimals() returns (uint8 decimals) {
            chainlinkResponse.decimals = decimals;
        } catch {
            // if the call fails, return an empty response with success = false
            return chainlinkResponse;
        }

        try _aggregator.latestRoundData() returns (
            uint80 roundId,
            int256 answer,
            uint256, // startedAt
            uint256 updatedAt,
            uint80 // answeredInRound
        ) {
            chainlinkResponse.roundId = roundId;
            chainlinkResponse.answer = answer;
            chainlinkResponse.updatedAt = updatedAt;
            chainlinkResponse.success = true;
            return chainlinkResponse;
        } catch {
            // if the call fails, return an empty response with success = false
            return chainlinkResponse;
        }
    }

    /// @dev see IChainlinkPriceFeedV3Event.FreezedReason for each FreezedReason
    function _getFreezedReason(ChainlinkResponse memory response) internal view returns (FreezedReason) {
        if (!response.success) {
            return FreezedReason.NoResponse;
        }
        if (response.decimals != _decimals) {
            return FreezedReason.IncorrectDecimals;
        }
        if (response.roundId == 0) {
            return FreezedReason.NoRoundId;
        }
        if (
            response.updatedAt == 0 ||
            response.updatedAt < _lastValidTimestamp ||
            response.updatedAt > _blockTimestamp()
        ) {
            return FreezedReason.InvalidTimestamp;
        }
        if (response.answer <= 0) {
            return FreezedReason.NonPositiveAnswer;
        }
        if (_lastValidPrice != 0 && _lastValidTimestamp != 0 && _isOutlier(uint256(response.answer))) {
            return FreezedReason.AnswerIsOutlier;
        }

        return FreezedReason.NotFreezed;
    }

    function _isOutlier(uint256 price) internal view returns (bool) {
        uint256 diff = _lastValidPrice >= price ? _lastValidPrice - price : price - _lastValidPrice;
        uint256 deviationRatio = diff.mul(_ONE_HUNDRED_PERCENT_RATIO).div(_lastValidPrice);
        return deviationRatio >= _maxOutlierDeviationRatio;
    }

    /// @dev after freezing for _outlierCoolDownPeriod, we gradually update _lastValidPrice by _maxOutlierDeviationRatio
    ///      e.g.
    ///      input: 300 -> 500 -> 630
    ///      output: 300 -> 300 (wait for _outlierCoolDownPeriod) -> 330 (assuming _maxOutlierDeviationRatio = 10%)
    function _getPriceAndTimestampAfterOutlierCoolDown(int256 answer) internal view returns (uint256, uint256) {
        uint24 deviationRatio =
            uint256(answer) > _lastValidPrice
                ? _ONE_HUNDRED_PERCENT_RATIO + _maxOutlierDeviationRatio
                : _ONE_HUNDRED_PERCENT_RATIO - _maxOutlierDeviationRatio;

        return (_mulRatio(_lastValidPrice, deviationRatio), _blockTimestamp());
    }

    function _mulRatio(uint256 value, uint24 ratio) internal pure returns (uint256) {
        return value.mul(ratio).div(_ONE_HUNDRED_PERCENT_RATIO);
    }
}
