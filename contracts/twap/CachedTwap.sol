// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import { CumulativeTwap } from "./CumulativeTwap.sol";

abstract contract CachedTwap is CumulativeTwap {
    uint256 internal _cachedTwap;
    uint160 internal _lastUpdatedAt;
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
            return _calculateTwapPrice(interval, latestPrice, latestUpdatedTimestamp);
        }

        // if twap has been calculated in this block, then return cached value directly
        if (_blockTimestamp() == _lastUpdatedAt) {
            return _cachedTwap;
        }

        _update(latestPrice, latestUpdatedTimestamp);
        _lastUpdatedAt = uint160(_blockTimestamp());
        _cachedTwap = _calculateTwapPrice(interval, latestPrice, latestUpdatedTimestamp);

        return _cachedTwap;
    }

    function _getCachedTwap(
        uint256 interval,
        uint256 latestPrice,
        uint256 latestUpdatedTimestamp
    ) internal view returns (uint256) {
        if (_blockTimestamp() == _lastUpdatedAt && interval == _interval) {
            return _cachedTwap;
        }
        return _calculateTwapPrice(interval, latestPrice, latestUpdatedTimestamp);
    }
}
