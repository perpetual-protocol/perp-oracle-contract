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
        _update(latestPrice, latestUpdatedTimestamp);

        // if the requested interval is not the same as the one we have cached, call _getTwap() directly
        if (_interval != interval) {
            return _interval == 0 ? latestPrice : _getTwap(interval, latestPrice, latestUpdatedTimestamp);
        }

        // only calculate twap and cache it when there's a new timestamp
        if (_blockTimestamp() != _lastUpdatedAt) {
            _lastUpdatedAt = uint160(_blockTimestamp());
            _cachedTwap = _getTwap(interval, latestPrice, latestUpdatedTimestamp);
        }

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
        return _getTwap(interval, latestPrice, latestUpdatedTimestamp);
    }

    /// @dev since we're plugging this contract to an existing system, we cannot return 0 upon the first call
    ///      thus, return the latest price instead
    function _getTwap(
        uint256 interval,
        uint256 latestPrice,
        uint256 latestUpdatedTimestamp
    ) internal view returns (uint256) {
        uint256 twap = _calculateTwap(interval, latestPrice, latestUpdatedTimestamp);
        return twap == 0 ? latestPrice : twap;
    }
}
