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
}
