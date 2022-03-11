// SPDX-License-Identifier: MIT License
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import { CumulativeTwap } from "./CumulativeTwap.sol";

abstract contract CachedTwap is CumulativeTwap {
    uint256 internal _cachedTwap;
    uint256 internal _lastUpdatedAt;
    uint80 internal _interval;

    constructor(uint80 interval) {
        _interval = interval;
    }

    function _cacheTwap(
        uint256 interval,
        uint256 latestPrice,
        uint256 latestUpdatedTimestamp
    ) internal virtual returns (uint256) {
        // if requested interval is not the same as the one we have cached, then call _getPrice() directly
        if (_interval != interval) {
            return _getPrice(interval, latestPrice, latestUpdatedTimestamp);
        }

        // if twap has been calculated in this block, then return cached value directly
        if (_blockTimestamp() == _lastUpdatedAt) {
            return _cachedTwap;
        }

        _lastUpdatedAt = _blockTimestamp();
        _cachedTwap = _getPrice(interval, latestPrice, latestUpdatedTimestamp);

        return _cachedTwap;
    }

    function _getCachedTwap(
        uint256 interval,
        uint256 latestPrice,
        uint256 latestUpdatedTimestamp
    ) internal view returns (uint256) {
        if (_blockTimestamp() == _lastUpdatedAt) {
            return _cachedTwap;
        }
        return _getPrice(interval, latestPrice, latestUpdatedTimestamp);
    }
}
