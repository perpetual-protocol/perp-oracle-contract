// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

import { IPriceFeedV2 } from "../interface/IPriceFeedV2.sol";

contract TestPriceFeedV2 {
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
            IPriceFeedV2(chainlink).getPrice(interval);
        }
        currentPrice = IPriceFeedV2(chainlink).getPrice(interval);
    }

    function fetchBandProtocolPrice(uint256 interval) external {
        for (uint256 i = 0; i < 17; i++) {
            IPriceFeedV2(bandProtocol).getPrice(interval);
        }
        currentPrice = IPriceFeedV2(bandProtocol).getPrice(interval);
    }

    function cachedChainlinkPrice(uint256 interval) external {
        for (uint256 i = 0; i < 17; i++) {
            IPriceFeedV2(chainlink).cacheTwap(interval);
        }
        currentPrice = IPriceFeedV2(chainlink).cacheTwap(interval);
    }

    function cachedBandProtocolPrice(uint256 interval) external {
        for (uint256 i = 0; i < 17; i++) {
            IPriceFeedV2(bandProtocol).cacheTwap(interval);
        }
        currentPrice = IPriceFeedV2(bandProtocol).cacheTwap(interval);
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
