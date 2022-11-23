// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

interface IPriceFeedDispatcherEvent {
    enum Status { Chainlink, UniswapV3 }
    event StatusUpdated(Status status);
}

interface IPriceFeedDispatcher is IPriceFeedDispatcherEvent {
    function dispatchPrice(uint256 interval) external;

    function setPriceFeedStatus(Status status) external;

    function getDispatchedPrice(uint256 interval) external returns (uint256);

    function getStatus() external returns (Status);

    function decimals() external returns (uint8);
}
