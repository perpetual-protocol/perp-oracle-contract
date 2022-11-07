// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import { IChainlinkPriceFeed } from "./interface/IChainlinkPriceFeed.sol";
import { IPriceFeedV3 } from "./interface/IPriceFeedV3.sol";
import { BlockContext } from "./base/BlockContext.sol";

contract PriceFeedDispatcher is BlockContext {
    using SafeMath for uint256;
    using Address for address;

    enum Status { Chainlink, UniswapV3 }

    Status internal _status = Status.Chainlink;

    address internal immutable _uniswapV3PriceFeed;

    address internal immutable _chainlinkPriceFeed;

    constructor(address uniswapV3PriceFeed, address chainlinkPriceFeed) {
        // PFD_UNC: uniswapV3 price feed address is not contract
        require(address(uniswapV3PriceFeed).isContract(), "CPF_UNC");
        // PFD_CNC: chainlink price feed address is not contract
        require(address(chainlinkPriceFeed).isContract(), "CPF_CNC");

        _uniswapV3PriceFeed = uniswapV3PriceFeed;

        _chainlinkPriceFeed = chainlinkPriceFeed;
    }

    function dispatchPrice() external returns (uint256) {
        uint256 chainlinkPrice = IPriceFeedV3(_chainlinkPriceFeed).cachePrice();
        if (!IPriceFeedV3(_chainlinkPriceFeed).isBroken() && _status == Status.Chainlink) {
            return chainlinkPrice;
        } else if (_uniswapV3PriceFeed != address(0)) {
            _status = Status.UniswapV3;
            return IPriceFeedV3(_uniswapV3PriceFeed).getLastValidPrice();
        }
        return chainlinkPrice; // if no emergencyPriceFeed (collateral usage)
    }

    function getDispatchedPrice() external view returns (uint256) {
        uint256 chainlinkPrice = IPriceFeedV3(_chainlinkPriceFeed).getLastValidPrice();
        if (!IPriceFeedV3(_chainlinkPriceFeed).isBroken() && _status == Status.Chainlink) {
            return chainlinkPrice;
        } else if (_uniswapV3PriceFeed != address(0)) {
            return IPriceFeedV3(_uniswapV3PriceFeed).getLastValidPrice();
        }
        return chainlinkPrice; // if no emergencyPriceFeed (collateral usage)
    }
}
