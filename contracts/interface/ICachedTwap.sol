// SPDX-License-Identifier: MIT License
pragma solidity 0.7.6;

interface ICachedTwap {
    function cacheTwap(uint256 interval) external returns (uint256);
}
