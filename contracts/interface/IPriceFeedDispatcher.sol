// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

interface IPriceFeedDispatcherEvent {
    enum Status { Chainlink, UniswapV3 }
    event StatusUpdated(Status status);
    event UniswapV3PriceFeedUpdated(address uniswapV3PriceFeed);
}

interface IPriceFeedDispatcher is IPriceFeedDispatcherEvent {
    /// @notice when Chainlink is down, switch priceFeed source to UniswapV3PriceFeed
    /// @dev this method is called by every tx that settles funding in Exchange.settleFunding() -> BaseToken.cacheTwap()
    /// @param interval only useful when using Chainlink; UniswapV3PriceFeed has its own fixed interval
    function dispatchPrice(uint256 interval) external;

    /// @notice return price from UniswapV3PriceFeed if _uniswapV3PriceFeed is ready to be switched to AND
    ///         1. _status is already UniswapV3PriceFeed OR
    ///         2. ChainlinkPriceFeedV3.isTimedOut()
    ///         else, return price from ChainlinkPriceFeedV3
    /// @dev decimals of the return value is 18, which can be queried with the function decimals()
    /// @param interval only useful when using Chainlink; UniswapV3PriceFeed has its own fixed interval
    function getDispatchedPrice(uint256 interval) external view returns (uint256);

    function getChainlinkPriceFeedV3() external view returns (address);

    function getUniswapV3PriceFeed() external view returns (address);

    function decimals() external pure returns (uint8);
}
