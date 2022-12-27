// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import { BlockContext } from "./base/BlockContext.sol";
import { IPriceFeedDispatcher } from "./interface/IPriceFeedDispatcher.sol";
import { UniswapV3PriceFeed } from "./UniswapV3PriceFeed.sol";
import { ChainlinkPriceFeedV3 } from "./ChainlinkPriceFeedV3.sol";

contract PriceFeedDispatcher is IPriceFeedDispatcher, BlockContext {
    using SafeMath for uint256;
    using Address for address;

    uint8 private constant _DECIMALS = 18;

    Status internal _status = Status.Chainlink;
    UniswapV3PriceFeed internal _uniswapV3PriceFeed;
    ChainlinkPriceFeedV3 internal _chainlinkPriceFeedV3;

    //
    // EXTERNAL NON-VIEW
    //

    constructor(UniswapV3PriceFeed uniswapV3PriceFeed, ChainlinkPriceFeedV3 chainlinkPriceFeedV3) {
        // PFD_UECOU: UniswapV3PriceFeed (has to be) either contract or uninitialized
        require(address(uniswapV3PriceFeed) == address(0) || address(uniswapV3PriceFeed).isContract(), "PFD_UECOU");
        // PFD_CNC: ChainlinkPriceFeed is not contract
        require(address(chainlinkPriceFeedV3).isContract(), "PFD_CNC");

        _uniswapV3PriceFeed = uniswapV3PriceFeed;
        _chainlinkPriceFeedV3 = chainlinkPriceFeedV3;
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

    //
    // EXTERNAL VIEW
    //

    /// @inheritdoc IPriceFeedDispatcher
    function getDispatchedPrice(uint256 interval) external view override returns (uint256) {
        if (isToUseUniswapV3PriceFeed()) {
            return _formatFromDecimalsToX10_18(_uniswapV3PriceFeed.getPrice(), _uniswapV3PriceFeed.decimals());
        }

        return
            _formatFromDecimalsToX10_18(
                _chainlinkPriceFeedV3.getCachedTwap(interval),
                _chainlinkPriceFeedV3.decimals()
            );
    }

    function getChainlinkPriceFeedV3() external view override returns (address) {
        return address(_chainlinkPriceFeedV3);
    }

    function getUniswapV3PriceFeed() external view override returns (address) {
        return address(_uniswapV3PriceFeed);
    }

    function decimals() external pure override returns (uint8) {
        return _DECIMALS;
    }

    //
    // PUBLIC
    //

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
