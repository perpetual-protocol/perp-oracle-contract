// SPDX-License-Identifier: MIT License
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import { CumulativeTwap } from "./CumulativeTwap.sol";

contract Cached15MinTwap is CumulativeTwap {
    uint256 cached15MinsTwap;
    uint256 lastUpdatedAt;

    function cacheTwap(uint256 latestPrice, uint256 latestUpdatedTimestamp) public returns (uint256) {
        // if twap has been calculated in this block, then return cached value directly
        if (_blockTimestamp() == lastUpdatedAt) {
            return cached15MinsTwap;
        }

        lastUpdatedAt = _blockTimestamp();
        cached15MinsTwap = _getPrice(900, latestPrice, latestUpdatedTimestamp);
        return cached15MinsTwap;
    }
}
