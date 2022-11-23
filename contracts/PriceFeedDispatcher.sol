// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import { BlockContext } from "./base/BlockContext.sol";
import { Ownable } from "./base/Ownable.sol";
import { IPriceFeedDispatcher } from "./interface/IPriceFeedDispatcher.sol";
import { UniswapV3PriceFeed } from "./UniswapV3PriceFeed.sol";
import { ChainlinkPriceFeedV3 } from "./ChainlinkPriceFeedV3.sol";

contract PriceFeedDispatcher is IPriceFeedDispatcher, Ownable, BlockContext {
    using SafeMath for uint256;
    using Address for address;

    uint8 private constant _DECIMALS = 18;

    Status internal _status = Status.Chainlink;
    UniswapV3PriceFeed internal immutable _uniswapV3PriceFeed;
    ChainlinkPriceFeedV3 internal immutable _chainlinkPriceFeedV3;

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

    function dispatchPrice(uint256 interval) external override {
        if (_isToUseUniswapV3PriceFeed()) {
            if (_status != Status.UniswapV3) {
                _status = Status.UniswapV3;
                emit StatusUpdated(_status);
            }
        }

        _chainlinkPriceFeedV3.cacheTwap(interval);
    }

    function setPriceFeedStatus(Status status) external override onlyOwner {
        if (status == Status.UniswapV3) {
            // PFD_UU: UniswapV3PriceFeed uninitialized
            require(address(_uniswapV3PriceFeed) != address(0), "PFD_UU");
        }

        _status = status;
        emit StatusUpdated(_status);
    }

    //
    // EXTERNAL VIEW
    //

    function getDispatchedPrice(uint256 interval) external view override returns (uint256) {
        if (_isToUseUniswapV3PriceFeed()) {
            return _formatFromDecimalsToX10_18(_uniswapV3PriceFeed.getPrice(), _uniswapV3PriceFeed.decimals());
        }

        return
            _formatFromDecimalsToX10_18(
                _chainlinkPriceFeedV3.getCachedTwap(interval),
                _chainlinkPriceFeedV3.decimals()
            );
    }

    function getStatus() external view override returns (Status) {
        return _status;
    }

    function decimals() external pure override returns (uint8) {
        return _DECIMALS;
    }

    //
    // INTERNAL
    //

    function _isToUseUniswapV3PriceFeed() internal view returns (bool) {
        return
            address(_uniswapV3PriceFeed) != address(0) &&
            (_chainlinkPriceFeedV3.isTimedOut() || _status == Status.UniswapV3);
    }

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
