// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import { IChainlinkPriceFeed } from "./interface/IChainlinkPriceFeed.sol";
import { IChainlinkPriceFeedV3 } from "./interface/IChainlinkPriceFeedV3.sol";
import { IPriceFeedUpdate } from "./interface/IPriceFeedUpdate.sol";
import { BlockContext } from "./base/BlockContext.sol";
import { CachedTwap } from "./twap/CachedTwap.sol";

contract ChainlinkPriceFeedV3 is IChainlinkPriceFeedV3, IPriceFeedUpdate, BlockContext, CachedTwap {
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

    /// @notice anyone can help with updating
    /// @dev keep this function for PriceFeedUpdater for updating, since multiple updates
    ///      with the same timestamp will get reverted in CumulativeTwap._update()
    function update() external override {
        _cachePrice();

        (bool isUpdated, ) = _cacheTwap(0, _lastValidPrice, _lastValidTimestamp);
        // CPF_NU: not updated
        require(isUpdated, "CPF_NU");
    }

    /// @inheritdoc IChainlinkPriceFeedV3
    function cacheTwap(uint256 interval) external override {
        _cachePrice();

        _cacheTwap(interval, _lastValidPrice, _lastValidTimestamp);
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

    function isTimedOut() external view override returns (bool) {
        // Fetch the latest timstamp instead of _lastValidTimestamp is to prevent stale data
        // when the update() doesn't get triggered.
        (, uint256 lastestValidTimestamp) = _getCachePrice();
        return lastestValidTimestamp > 0 && lastestValidTimestamp.add(_timeout) < _blockTimestamp();
    }

    function getFreezedReason() external view override returns (FreezedReason) {
        ChainlinkResponse memory response = _getChainlinkResponse();
        return _getFreezedReason(response);
    }

    function getAggregator() external view override returns (address) {
        return address(_aggregator);
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    //
    // INTERNAL
    //

    function _cachePrice() internal {
        ChainlinkResponse memory response = _getChainlinkResponse();
        if (_isAlreadyLatestCache(response)) {
            return;
        }

        FreezedReason freezedReason = _getFreezedReason(response);
        if (_isNotFreezed(freezedReason)) {
            _lastValidPrice = uint256(response.answer);
            _lastValidTimestamp = response.updatedAt;
        }

        emit ChainlinkPriceUpdated(_lastValidPrice, _lastValidTimestamp, freezedReason);
    }

    function _getCachePrice() internal view returns (uint256, uint256) {
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
