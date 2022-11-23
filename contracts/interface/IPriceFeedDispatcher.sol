// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

interface IPriceFeedDispatcherEvent {
    enum Status { Chainlink, UniswapV3 }
    event StatusUpdated(Status status);
}

interface IPriceFeedDispatcher is IPriceFeedDispatcherEvent {
    /// @notice when Chainlink is down, switch priceFeed source to UniswapV3PriceFeed
    /// @param interval only useful when using Chainlink; UniswapV3PriceFeed has its own fixed interval
    function dispatchPrice(uint256 interval) external;

    function setPriceFeedStatus(Status status) external;

    /// @notice return price from Chainlink if Chainlink works as expected; else, price from UniswapV3PriceFeed
    /// @dev decimals of the return value is 18, which can be queried with the function decimals()
    /// @param interval only useful when using Chainlink; UniswapV3PriceFeed has its own fixed interval
    function getDispatchedPrice(uint256 interval) external returns (uint256);

    function getStatus() external returns (Status);

    function decimals() external returns (uint8);
}
