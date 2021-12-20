// SPDX-License-Identifier: MIT License
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { BlockContext } from "./base/BlockContext.sol";
import { ICachedPriceFeed } from "./interface/ICachedPriceFeed.sol";
import { IStdReference } from "./interface/bandProtocol/IStdReference.sol";

contract BandPriceFeed is ICachedPriceFeed, BlockContext {
    using Address for address;

    //
    // STRUCT
    //
    struct Observation {
        uint256 price;
        uint256 priceCumulative;
        uint256 timestamp;
    }

    struct CachedTwap {
        uint256 timestamp;
        uint256 twap;
    }

    //
    // EVENT
    //

    event PriceUpdated(string indexed baseAsset, uint256 price, uint256 timestamp, uint8 indexAt);

    //
    // STATE
    //
    string public constant QUOTE_ASSET = "USD";

    string public baseAsset;
    // let's use 15 mins and 1 hr twap as example
    // if the price is being updated 15 secs, then needs 60 and 240 historical data for 15mins and 1hr twap.
    Observation[256] public observations;

    IStdReference public stdRef;
    uint8 public currentObservationIndex;
    // cache the lastest twap
    mapping(uint256 => CachedTwap) public cachedTwapMap;

    //
    // EXTERNAL NON-VIEW
    //

    constructor(IStdReference stdRefArg, string memory baseAssetArg) {
        // BPF_ANC: Reference address is not contract
        require(address(stdRefArg).isContract(), "BPF_ANC");

        stdRef = stdRefArg;
        baseAsset = baseAssetArg;
    }

    /// @dev anyone can help update it.
    function update() external {
        IStdReference.ReferenceData memory bandData = stdRef.getReferenceData(baseAsset, QUOTE_ASSET);
        // BPF_TQZ: timestamp for quote is zero
        require(bandData.lastUpdatedQuote > 0, "BPF_TQZ");
        // BPF_TBZ: timestamp for base is zero
        require(bandData.lastUpdatedBase > 0, "BPF_TBZ");
        // BPF_IP: invalid price
        require(bandData.rate > 0, "BPF_IP");

        // for the first time update
        if (currentObservationIndex == 0 && observations[0].timestamp == 0) {
            observations[0] = Observation({
                price: bandData.rate,
                priceCumulative: 0,
                timestamp: bandData.lastUpdatedBase
            });
            currentObservationIndex++;
            emit PriceUpdated(baseAsset, bandData.rate, bandData.lastUpdatedBase, 0);
            return;
        }

        // BPF_IT: invalid timestamp
        Observation memory lastObservation = observations[currentObservationIndex - 1];
        require(bandData.lastUpdatedBase > lastObservation.timestamp, "BPF_IT");

        uint256 elapsedTime = bandData.lastUpdatedBase - lastObservation.timestamp;
        // overflow of currentObservationIndex is desired since currentObservationIndex is uint8 (0-255),
        // so 255 + 1 will be 0
        observations[currentObservationIndex++] = Observation({
            priceCumulative: lastObservation.priceCumulative + (lastObservation.price * elapsedTime),
            timestamp: bandData.lastUpdatedBase,
            price: bandData.rate
        });

        emit PriceUpdated(baseAsset, bandData.rate, bandData.lastUpdatedBase, currentObservationIndex - 1);
    }

    // TODO: naming cachePriceAndGetPrice?
    function cachePrice(uint256 interval) external override returns (uint256) {
        if (interval == 0) {
            return getPrice(interval);
        }

        uint256 currentTimestamp = _blockTimestamp();

        CachedTwap storage cachedTwapStorage = cachedTwapMap[interval];
        if (cachedTwapStorage.timestamp == currentTimestamp) {
            return cachedTwapStorage.twap;
        }

        // update cache
        cachedTwapStorage.timestamp = currentTimestamp;
        cachedTwapStorage.twap = getPrice(interval);

        return cachedTwapStorage.twap;
    }

    //
    // EXTERNAL VIEW
    //

    function getPrice(uint256 interval) public view override returns (uint256) {
        IStdReference.ReferenceData memory latestBandData = stdRef.getReferenceData(baseAsset, QUOTE_ASSET);
        if (interval == 0) {
            return latestBandData.rate;
        }

        uint256 currentTimestamp = _blockTimestamp();
        uint256 targetTimestamp = currentTimestamp - interval;
        (Observation memory beforeOrAt, Observation memory atOrAfter) = getSurroundingObservations(targetTimestamp);

        Observation memory lastestObservation = observations[currentObservationIndex - 1];
        uint256 currentPriceCumulative =
            lastestObservation.priceCumulative +
                (lastestObservation.price * (latestBandData.lastUpdatedBase - lastestObservation.timestamp)) +
                (latestBandData.rate * (currentTimestamp - latestBandData.lastUpdatedBase));

        //
        //                   beforeOrAt                    atOrAfter
        //      ---------+---------+-------------+---------------+---------+---------
        //               |<------->|             |               |         |
        // case 1       targetTimestamp          |               |<------->|
        // case 2                                |              targetTimestamp
        // case 3                          targetTimestamp
        //
        uint256 targetPriceCumulative;
        // case1. not enough historical data or just enough (`==` case)
        if (targetTimestamp <= beforeOrAt.timestamp) {
            targetTimestamp = beforeOrAt.timestamp;
            targetPriceCumulative = beforeOrAt.priceCumulative;
        }
        // case2. the latest data is older than or equal the request
        else if (atOrAfter.timestamp <= targetTimestamp) {
            targetTimestamp = atOrAfter.timestamp;
            targetPriceCumulative = atOrAfter.priceCumulative;
        }
        // case3. in the middle
        else {
            uint256 observationTimeDelta = atOrAfter.timestamp - beforeOrAt.timestamp;
            uint256 targetTimeDelta = targetTimestamp - beforeOrAt.timestamp;
            targetPriceCumulative =
                beforeOrAt.priceCumulative +
                ((atOrAfter.priceCumulative - beforeOrAt.priceCumulative) * targetTimeDelta) /
                observationTimeDelta;
        }

        return (currentPriceCumulative - targetPriceCumulative) / (currentTimestamp - targetTimestamp);
    }

    //
    // EXTERNAL PURE
    //

    function decimals() external pure override returns (uint8) {
        return 18;
    }

    //
    // INTERNAL VIEW
    //

    function getSurroundingObservations(uint256 targetTimestamp)
        internal
        view
        returns (Observation memory beforeOrAt, Observation memory atOrAfter)
    {
        uint8 index = currentObservationIndex - 1;
        uint8 beforeOrAtIndex;
        uint8 atOrAfterIndex;
        while (true) {
            // == case 1 ==
            // now: 3:45
            // target: 3:30
            // index 0: 2:00
            // index 1: 2:10 --> chosen
            // beforeOrAtIndex = 1
            // atOrAfterIndex = 1

            // == case 2 ==
            // now: 3:45
            // target: 3:30
            // index 0: 3:40  --> chosen
            // index 1: 3:50
            // beforeOrAtIndex = 0
            // atOrAfterIndex = 0

            // == case 3 ==
            // now: 3:45
            // target: 3:01
            // index 0: 3:00  --> chosen
            // index 1: 3:15
            // index 1: 3:30
            // beforeOrAtIndex = 0
            // atOrAfterIndex = 1

            if (observations[index].timestamp <= targetTimestamp) {
                // if the next observation is empty, using the last one
                // it implies the historical data is not enough
                if (observations[index].timestamp == 0) {
                    atOrAfterIndex = beforeOrAtIndex = index + 1;
                    break;
                }
                beforeOrAtIndex = index;
                atOrAfterIndex = beforeOrAtIndex + 1;
                break;
            }
            index--;
        }

        beforeOrAt = observations[beforeOrAtIndex];
        atOrAfter = observations[atOrAfterIndex];
        // if timestamp of the right bound is earlier than timestamp of the left bound,
        // it means the left bound is the lastest observation.
        // It implies the latest observation is older than requested
        // Then we set the right bound to the left bound.
        if (atOrAfter.timestamp < beforeOrAt.timestamp) {
            atOrAfter = beforeOrAt;
        }
    }
}
