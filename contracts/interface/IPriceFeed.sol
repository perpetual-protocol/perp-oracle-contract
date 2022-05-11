// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

interface IPriceFeed {
    /// @dev Returns the cached index price of the token.
    /// @param interval The interval represents twap interval.
    function cacheTwap(uint256 interval) external returns (uint256);

    function decimals() external view returns (uint8);

    /// @dev Returns the index price of the token.
    /// @param interval The interval represents twap interval.
    function getPrice(uint256 interval) external view returns (uint256);

    /// @dev Returns true if
    ///      latest timestamp of external price feed is greater than latest timestamp of Observation[].
    function isUpdatable() external view returns (bool);
}
