// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import { IChainlinkPriceFeed } from "./interface/IChainlinkPriceFeed.sol";
import { IPriceFeed } from "./interface/IPriceFeed.sol";
import { IChainlinkPriceFeedV3 } from "./interface/IChainlinkPriceFeedV3.sol";
import { IPriceFeedUpdate } from "./interface/IPriceFeedUpdate.sol";
import { BlockContext } from "./base/BlockContext.sol";
import { CachedTwap } from "./twap/CachedTwap.sol";

contract ChainlinkPriceFeedV3 is IPriceFeed, IChainlinkPriceFeedV3, IPriceFeedUpdate, BlockContext, CachedTwap {
    using SafeMath for uint256;
    using Address for address;

    //
    // STATE
    //

    uint8 internal immutable _decimals;
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
        uint80 twapInterval
    ) CachedTwap(twapInterval) {
        // CPF_ANC: Aggregator is not contract
        require(address(aggregator).isContract(), "CPF_ANC");
        _aggregator = aggregator;

        _timeout = timeout;
        _decimals = aggregator.decimals();
    }

    /// @inheritdoc IPriceFeedUpdate
    /// @notice anyone can help with updating
    /// @dev this function is used by PriceFeedUpdater for updating _lastValidPrice,
    ///      _lastValidTimestamp and observation arry.
    ///      The keeper can invoke callstatic on this function to check if those states nened to be updated.
    function update() external override {
        bool isUpdated = _cachePrice();
        // CPF_NU: not updated
        require(isUpdated, "CPF_NU");

        _update(_lastValidPrice, _lastValidTimestamp);
    }

    /// @inheritdoc IChainlinkPriceFeedV3
    function cacheTwap(uint256 interval) external override {
        _cachePrice();

        _cacheTwap(interval, _lastValidPrice, _lastValidTimestamp);
    }

    //
    // EXTERNAL VIEW
    //

    /// @inheritdoc IChainlinkPriceFeedV3
    function getLastValidPrice() external view override returns (uint256) {
        return _lastValidPrice;
    }

    /// @inheritdoc IChainlinkPriceFeedV3
    function getLastValidTimestamp() external view override returns (uint256) {
        return _lastValidTimestamp;
    }

    /// @inheritdoc IPriceFeed
    /// @dev This is the view version of cacheTwap().
    ///      If the interval is zero, returns the latest valid price.
    ///         Else, returns TWAP calculating with the latest valid price and timestamp.
    function getPrice(uint256 interval) external view override returns (uint256) {
        (uint256 latestValidPrice, uint256 latestValidTime) = _getLatestOrCachedPrice();

        if (interval == 0) {
            return latestValidPrice;
        }

        return _getCachedTwap(interval, latestValidPrice, latestValidTime);
    }

    /// @inheritdoc IChainlinkPriceFeedV3
    function getLatestOrCachedPrice() external view override returns (uint256, uint256) {
        return _getLatestOrCachedPrice();
    }

    /// @inheritdoc IChainlinkPriceFeedV3
    function isTimedOut() external view override returns (bool) {
        // Fetch the latest timstamp instead of _lastValidTimestamp is to prevent stale data
        // when the update() doesn't get triggered.
        (, uint256 lastestValidTimestamp) = _getLatestOrCachedPrice();
        return lastestValidTimestamp > 0 && lastestValidTimestamp.add(_timeout) < _blockTimestamp();
    }

    /// @inheritdoc IChainlinkPriceFeedV3
    function getFreezedReason() external view override returns (FreezedReason) {
        ChainlinkResponse memory response = _getChainlinkResponse();
        return _getFreezedReason(response);
    }

    /// @inheritdoc IChainlinkPriceFeedV3
    function getAggregator() external view override returns (address) {
        return address(_aggregator);
    }

    /// @inheritdoc IChainlinkPriceFeedV3
    function getTimeout() external view override returns (uint256) {
        return _timeout;
    }

    /// @inheritdoc IPriceFeed
    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    //
    // INTERNAL
    //

    function _cachePrice() internal returns (bool) {
        ChainlinkResponse memory response = _getChainlinkResponse();
        if (_isAlreadyLatestCache(response)) {
            return false;
        }

        bool isUpdated = false;
        FreezedReason freezedReason = _getFreezedReason(response);
        if (_isNotFreezed(freezedReason)) {
            _lastValidPrice = uint256(response.answer);
            _lastValidTimestamp = response.updatedAt;
            isUpdated = true;
        }

        emit ChainlinkPriceUpdated(_lastValidPrice, _lastValidTimestamp, freezedReason);
        return isUpdated;
    }

    function _getLatestOrCachedPrice() internal view returns (uint256, uint256) {
        ChainlinkResponse memory response = _getChainlinkResponse();
        if (_isAlreadyLatestCache(response)) {
            return (_lastValidPrice, _lastValidTimestamp);
        }

        FreezedReason freezedReason = _getFreezedReason(response);
        if (_isNotFreezed(freezedReason)) {
            return (uint256(response.answer), response.updatedAt);
        }

        // if freezed
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

    function _isAlreadyLatestCache(ChainlinkResponse memory response) internal view returns (bool) {
        return _lastValidTimestamp > 0 && _lastValidTimestamp == response.updatedAt;
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

        return FreezedReason.NotFreezed;
    }

    function _isNotFreezed(FreezedReason freezedReason) internal pure returns (bool) {
        return freezedReason == FreezedReason.NotFreezed;
    }
}
