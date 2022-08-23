// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

interface IPriceFeedUpdate {
    /// @dev Update latest price.
    function update() external;
}
