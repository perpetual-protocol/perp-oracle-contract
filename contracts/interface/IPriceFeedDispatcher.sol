// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

import { ChainlinkPriceFeedV3 } from "../ChainlinkPriceFeedV3.sol";
import { UniswapV3PriceFeed } from "../UniswapV3PriceFeed.sol";

interface IPriceFeedDispatcherEvent {
    enum Status { Chainlink, UniswapV3 }
    event StatusUpdated(Status status);
    event ChainlinkPriceFeedV3Updated(ChainlinkPriceFeedV3 chainlinkPriceFeedV3);
    event UniswapV3PriceFeedUpdated(UniswapV3PriceFeed uniswapV3PriceFeed);
}

interface IPriceFeedDispatcher is IPriceFeedDispatcherEvent {
    function dispatchPrice(uint256 interval) external;

    function setChainlinkPriceFeedV3(ChainlinkPriceFeedV3 chainlinkPriceFeedV3) external;

    function setUniswapV3PriceFeed(UniswapV3PriceFeed uniswapV3PriceFeed) external;

    function setPriceFeedStatus(Status status) external;

    function getDispatchedPrice(uint256 interval) external returns (uint256);

    function getChainlinkPriceFeedV3() external returns (ChainlinkPriceFeedV3);

    function getUniswapV3PriceFeed() external returns (UniswapV3PriceFeed);

    function getStatus() external returns (Status);

    function decimals() external returns (uint8);
}
