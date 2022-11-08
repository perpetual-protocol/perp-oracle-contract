// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;
pragma abicoder v2;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";
import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";
import { IChainlinkPriceFeed } from "./interface/IChainlinkPriceFeed.sol";
import { IPriceFeedV3 } from "./interface/IPriceFeedV3.sol";
import { BlockContext } from "./base/BlockContext.sol";

contract ChainlinkPriceFeedV3 is IPriceFeedV3, BlockContext {
    using SafeMath for uint256;
    using Address for address;

    enum FreezeReason {
        Normal,
        NoResponse,
        IncorrectDecimals,
        NoRound,
        IncorrectTime,
        LessThanEqualToZero,
        PotentialOutlier
    }

    //
    // STATE
    //

    uint24 private constant _ONE_HUNDRED_PERCENT_RATIO = 1e6;
    uint8 internal immutable _decimals;
    uint24 internal immutable _outlierDeviationRatio;
    uint256 internal immutable _outlierCoolDownPeriod;
    uint256 internal immutable _timeout;
    uint256 internal _lastValidPrice;
    uint256 internal _lastValidTime;
    AggregatorV3Interface internal immutable _aggregator;

    //
    // EXTERNAL NON-VIEW
    //

    constructor(
        AggregatorV3Interface aggregator,
        uint256 timeout,
        uint24 outlierDeviationRatio,
        uint256 outlierCoolDownPeriod
    ) {
        // CPF_ANC: Aggregator address is not contract
        require(address(aggregator).isContract(), "CPF_ANC");
        _aggregator = aggregator;

        // CPF_IODR: Invalid outlier deviation ratio
        require(outlierDeviationRatio < _ONE_HUNDRED_PERCENT_RATIO, "CPF_IORD");
        _outlierDeviationRatio = outlierDeviationRatio;

        _outlierCoolDownPeriod = outlierCoolDownPeriod;
        _timeout = timeout;
        _decimals = aggregator.decimals();
    }

    function cachePrice() external override returns (uint256) {
        ChainlinkResponse memory response = _getChainlinkData();

        if (_lastValidTime == response.updatedAt) {
            return _lastValidPrice;
        }

        FreezeReason freezeReason = _getFreezedReason(response);
        if (freezeReason != FreezeReason.Normal) {
            if (freezeReason == FreezeReason.PotentialOutlier) {
                if (_lastValidTime.add(_outlierCoolDownPeriod) > _blockTimestamp()) {
                    uint256 latestPrice = uint256(response.answer);
                    if (latestPrice > _lastValidPrice) {
                        _lastValidPrice = _mulRatio(
                            _lastValidPrice,
                            _ONE_HUNDRED_PERCENT_RATIO + _outlierDeviationRatio
                        );
                    } else {
                        _lastValidPrice = _mulRatio(
                            _lastValidPrice,
                            _ONE_HUNDRED_PERCENT_RATIO - _outlierDeviationRatio
                        );
                    }
                    _lastValidTime = _blockTimestamp();
                }
            }
            return _lastValidPrice;
        }

        _lastValidPrice = uint256(response.answer);
        _lastValidTime = response.updatedAt;

        return _lastValidPrice;
    }

    //
    // EXTERNAL VIEW
    //

    function getAggregator() external view returns (address) {
        return address(_aggregator);
    }

    function getLastValidPrice() external view override returns (uint256) {
        return _lastValidPrice;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function isTimedOut() external view override returns (bool) {
        return _lastValidTime.add(_timeout) > _blockTimestamp();
    }

    //
    // INTERNAL VIEW
    //

    function _getChainlinkData() internal view returns (ChainlinkResponse memory chainlinkResponse) {
        try _aggregator.decimals() returns (uint8 decimals) {
            chainlinkResponse.decimals = decimals;
        } catch {
            return chainlinkResponse;
        }

        try _aggregator.latestRoundData() returns (
            uint80 roundId,
            int256 answer,
            uint256, // startedAt
            uint256 updatedAt,
            uint80 // answeredInRound
        ) {
            // If call to Chainlink succeeds, return the response and success = true
            chainlinkResponse.roundId = roundId;
            chainlinkResponse.answer = answer;
            chainlinkResponse.updatedAt = updatedAt;
            chainlinkResponse.success = true;
            return chainlinkResponse;
        } catch {
            // If call to Chainlink aggregator reverts, return a zero response with success = false
            return chainlinkResponse;
        }
    }

    function _getFreezedReason(ChainlinkResponse memory response) internal view returns (FreezeReason) {
        /*
        1. no response
        2. incorrect decimals
        3. no round
        4. no timestamp or it’s future time
        5. no positive or 0 price
        6. outlier
        */
        if (!response.success) {
            return FreezeReason.NoResponse;
        }
        if (response.decimals != _decimals) {
            return FreezeReason.IncorrectDecimals;
        }
        if (response.roundId == 0) {
            return FreezeReason.NoRound;
        }
        if (response.updatedAt == 0 || response.updatedAt > _blockTimestamp()) {
            return FreezeReason.IncorrectTime;
        }
        if (response.answer <= 0) {
            return FreezeReason.LessThanEqualToZero;
        }
        if (_lastValidPrice != 0 && _lastValidTime != 0 && _isOutlier(uint256(response.answer))) {
            return FreezeReason.PotentialOutlier;
        }

        return FreezeReason.Normal;
    }

    function _isOutlier(uint256 price) internal view returns (bool) {
        uint256 diff = _lastValidPrice >= price ? _lastValidPrice - price : price - _lastValidPrice;
        uint256 deviation = diff.div(_lastValidPrice);
        return deviation > _outlierDeviationRatio;
    }

    function _mulRatio(uint256 value, uint24 ratio) internal pure returns (uint256) {
        return value.mul(ratio).div(1e6);
    }
}
