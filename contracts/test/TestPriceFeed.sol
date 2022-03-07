// SPDX-License-Identifier: MIT License
pragma solidity 0.7.6;

import { IPriceFeed } from "../interface/IPriceFeed.sol";
import { ICachedTwap } from "../interface/ICachedTwap.sol";

contract TestPriceFeed {
    address public chainlink;
    address public bandProtocol;

    uint256 public currentPrice;

    constructor(address _chainlink, address _bandProtocol) {
        chainlink = _chainlink;
        bandProtocol = _bandProtocol;
        currentPrice = 10;
    }

    //
    // for gas usage testing
    //
    function fetchChainlinkPrice(uint256 interval) external {
        for (uint256 i = 0; i < 17; i++) {
            IPriceFeed(chainlink).getPrice(interval);
        }
        currentPrice = IPriceFeed(chainlink).getPrice(interval);
    }

    function fetchBandProtocolPrice(uint256 interval) external {
        for (uint256 i = 0; i < 17; i++) {
            IPriceFeed(bandProtocol).getPrice(interval);
        }
        currentPrice = IPriceFeed(bandProtocol).getPrice(interval);
    }

    function cachedChainlinkPrice(uint256 interval) external {
        for (uint256 i = 0; i < 17; i++) {
            ICachedTwap(chainlink).cacheTwap(interval);
        }
        currentPrice = ICachedTwap(chainlink).cacheTwap(interval);
    }

    function cachedBandProtocolPrice(uint256 interval) external {
        for (uint256 i = 0; i < 17; i++) {
            ICachedTwap(bandProtocol).cacheTwap(interval);
        }
        currentPrice = ICachedTwap(bandProtocol).cacheTwap(interval);
    }

    //
    // for cached twap testing
    //

    // having this function for testing getPrice() and cacheTwap()
    // timestamp moves if any txs happen in hardhat env and which causes cacheTwap() will recalculate all the time
    function getPrice(uint256 interval) external returns (uint256 twap, uint256 cachedTwap) {
        twap = IPriceFeed(bandProtocol).getPrice(interval);
        cachedTwap = ICachedTwap(bandProtocol).cacheTwap(interval);
    }
}
