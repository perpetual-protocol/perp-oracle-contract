// SPDX-License-Identifier: MIT License
pragma solidity 0.7.6;

import { IPriceFeed } from "../interface/IPriceFeed.sol";

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
        currentPrice = IPriceFeed(chainlink).getPrice(interval);
    }

    function fetchBandProtocolPrice(uint256 interval) external {
        currentPrice = IPriceFeed(bandProtocol).getPrice(interval);
    }
}
