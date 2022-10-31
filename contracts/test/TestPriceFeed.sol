// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

import { IPriceFeedV2 } from "../interface/IPriceFeedV2.sol";
import { IPriceFeed } from "../interface/IPriceFeed.sol";

contract TestPriceFeed {
    address public chainlinkV1;
    address public chainlinkV2;
    address public bandProtocol;

    uint256 public currentPrice;

    constructor(address _chainlinkV1, address _chainlinkV2, address _bandProtocol) {
        chainlinkV1 = _chainlinkV1;
        chainlinkV2 = _chainlinkV2;
        bandProtocol = _bandProtocol;
        currentPrice = 10;
    }

    //
    // for gas usage testing
    //
    function fetchChainlinkV2Price(uint256 interval) external {
        currentPrice = IPriceFeedV2(chainlinkV2).getPrice(interval);
    }

    function fetchChainlinkV1Price(uint256 interval) external {
        currentPrice = IPriceFeed(chainlinkV1).getPrice(interval);
    }

    function fetchBandProtocolPrice(uint256 interval) external {
        currentPrice = IPriceFeedV2(bandProtocol).getPrice(interval);
    }

    function cachedChainlinkV2Price(uint256 interval) external {
        try IPriceFeedV2(chainlinkV2).cacheTwap(interval) {} catch {}
    }

    function cachedChainlinkV2PriceWithoutTry(uint256 interval) external {
        IPriceFeedV2(chainlinkV2).cacheTwap(interval);
    }

    function cachedBandProtocolPrice(uint256 interval) external {
        try IPriceFeedV2(bandProtocol).cacheTwap(interval) {} catch {}
    }

    //
    // for cached twap testing
    //

    // having this function for testing getPrice() and cacheTwap()
    // timestamp moves if any txs happen in hardhat env and which causes cacheTwap() will recalculate all the time
    function getPrice(uint256 interval) external returns (uint256 twap, uint256 cachedTwap) {
        twap = IPriceFeedV2(bandProtocol).getPrice(interval);
        cachedTwap = IPriceFeedV2(bandProtocol).cacheTwap(interval);
    }
}
