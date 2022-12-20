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
    /// @notice when Chainlink is down, switch priceFeed source to UniswapV3PriceFeed
    /// @dev this method is called by every tx that settles funding in Exchange.settleFunding() -> BaseToken.cacheTwap()
    /// @param interval only useful when using Chainlink; UniswapV3PriceFeed has its own fixed interval
    function dispatchPrice(uint256 interval) external;

    function setChainlinkPriceFeedV3(ChainlinkPriceFeedV3 chainlinkPriceFeedV3) external;

    function setUniswapV3PriceFeed(UniswapV3PriceFeed uniswapV3PriceFeed) external;

    /// @dev once the destination of dispatchPrice() is fallen back to UniswapV3PriceFeed,
    ///      admin has to call this function to switch back to ChainlinkPriceFeedV3; it won't recover automatically
    function setPriceFeedStatus(Status status) external;

    /// @notice return price from Chainlink if Chainlink works as expected; else, price from UniswapV3PriceFeed
    /// @dev decimals of the return value is 18, which can be queried with the function decimals()
    /// @param interval only useful when using Chainlink; UniswapV3PriceFeed has its own fixed interval
    function getDispatchedPrice(uint256 interval) external view returns (uint256);

    function getChainlinkPriceFeedV3() external view returns (address);

    function getUniswapV3PriceFeed() external view returns (address);

    function getStatus() external view returns (Status);

    function decimals() external pure returns (uint8);
}