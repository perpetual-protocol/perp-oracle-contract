// SPDX-License-Identifier: MIT License
pragma solidity 0.7.6;

import { IPriceFeed } from "./IPriceFeed.sol";

interface ICachedPriceFeed is IPriceFeed {
    function cachePrice(uint256 interval) external returns (uint256);
}
