// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

interface ICumulativeEvent {
    event PriceUpdated(uint256 price, uint256 timestamp, uint8 indexAt);
}
