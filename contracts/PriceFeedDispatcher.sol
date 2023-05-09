// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import { BlockContext } from "./base/BlockContext.sol";
import { IPriceFeed } from "./interface/IPriceFeed.sol";
import { IPriceFeedDispatcher } from "./interface/IPriceFeedDispatcher.sol";
import { UniswapV3PriceFeed } from "./UniswapV3PriceFeed.sol";
import { ChainlinkPriceFeedV3 } from "./ChainlinkPriceFeedV3.sol";

contract PriceFeedDispatcher is IPriceFeed, IPriceFeedDispatcher, Ownable, BlockContext {
    using SafeMath for uint256;
    using Address for address;

    uint8 private constant _DECIMALS = 18;

    Status internal _status = Status.Chainlink;
    UniswapV3PriceFeed internal _uniswapV3PriceFeed;
    ChainlinkPriceFeedV3 internal immutable _chainlinkPriceFeedV3;

    //
    // EXTERNAL NON-VIEW
    //

    constructor(address chainlinkPriceFeedV3) {
        // PFD_CNC: ChainlinkPriceFeed is not contract
        require(chainlinkPriceFeedV3.isContract(), "PFD_CNC");

        _chainlinkPriceFeedV3 = ChainlinkPriceFeedV3(chainlinkPriceFeedV3);
    }

    /// @inheritdoc IPriceFeedDispatcher
    function dispatchPrice(uint256 interval) external override {
        if (isToUseUniswapV3PriceFeed()) {
            if (_status != Status.UniswapV3) {
                _status = Status.UniswapV3;
                emit StatusUpdated(_status);
            }
            return;
        }

        _chainlinkPriceFeedV3.cacheTwap(interval);
    }

    /// @dev can only be initialized once by the owner
    function setUniswapV3PriceFeed(address uniswapV3PriceFeed) external onlyOwner {
        // PFD_UCAU: UniswapV3PriceFeed (has to be) a contract and uninitialized
        require(address(_uniswapV3PriceFeed) == address(0) && uniswapV3PriceFeed.isContract(), "PFD_UCAU");

        _uniswapV3PriceFeed = UniswapV3PriceFeed(uniswapV3PriceFeed);
        emit UniswapV3PriceFeedUpdated(uniswapV3PriceFeed);
    }

    //
    // EXTERNAL VIEW
    //

    /// @inheritdoc IPriceFeed
    function getPrice(uint256 interval) external view override returns (uint256) {
        return getDispatchedPrice(interval);
    }

    /// @inheritdoc IPriceFeedDispatcher
    function getChainlinkPriceFeedV3() external view override returns (address) {
        return address(_chainlinkPriceFeedV3);
    }

    /// @inheritdoc IPriceFeedDispatcher
    function getUniswapV3PriceFeed() external view override returns (address) {
        return address(_uniswapV3PriceFeed);
    }

    //
    // EXTERNAL PURE
    //

    /// @inheritdoc IPriceFeed
    function decimals() external pure override(IPriceFeed, IPriceFeedDispatcher) returns (uint8) {
        return _DECIMALS;
    }

    //
    // PUBLIC
    //

    /// @inheritdoc IPriceFeedDispatcher
    function getDispatchedPrice(uint256 interval) public view override returns (uint256) {
        if (isToUseUniswapV3PriceFeed()) {
            return _formatFromDecimalsToX10_18(_uniswapV3PriceFeed.getPrice(), _uniswapV3PriceFeed.decimals());
        }

        return _formatFromDecimalsToX10_18(_chainlinkPriceFeedV3.getPrice(interval), _chainlinkPriceFeedV3.decimals());
    }

    function isToUseUniswapV3PriceFeed() public view returns (bool) {
        return
            address(_uniswapV3PriceFeed) != address(0) &&
            (_chainlinkPriceFeedV3.isTimedOut() || _status == Status.UniswapV3);
    }

    //
    // INTERNAL
    //

    function _formatFromDecimalsToX10_18(uint256 value, uint8 fromDecimals) internal pure returns (uint256) {
        uint8 toDecimals = _DECIMALS;

        if (fromDecimals == toDecimals) {
            return value;
        }

        return
            fromDecimals > toDecimals
                ? value.div(10**(fromDecimals - toDecimals))
                : value.mul(10**(toDecimals - fromDecimals));
    }
}
