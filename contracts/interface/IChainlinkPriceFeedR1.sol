// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

import "./IChainlinkPriceFeed.sol";

interface IChainlinkPriceFeedR1 is IChainlinkPriceFeed {
    function getSequencerUptimeFeed() external view returns (address);
}
