// SPDX-License-Identifier: MIT License
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { BlockContext } from "./base/BlockContext.sol";
import { IPriceFeed } from "./interface/IPriceFeed.sol";
import { IStdReference } from "./interface/bandProtocol/IStdReference.sol";
import "hardhat/console.sol";

contract BandPriceFeed is IPriceFeed, BlockContext {
    using Address for address;

    //
    // STRUCT
    //

    struct Observation {
        uint256 price;
        uint256 priceCumulative;
        uint256 timestamp;
    }

    string public constant QUOTE_ASSET = "USD";

    string public baseAsset;
    IStdReference public stdRef;
    // let's use 15 mins and 1 hr twap as example
    // if the price is being updated 15 secs, then needs 60 and 240 historical data for 15mins and 1hr twap.
    Observation[256] public observations;

    uint8 public currentObservationIndex;
    // cache the lastest twap
    uint256 public latestUpdatedTimestamp;
    uint256 public latestUpdatedTwap;

    event PriceUpdated(string indexed baseAsset, uint256 price, uint256 timestamp, uint8 indexAt);

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

        Observation memory lastObservation;
        if (currentObservationIndex == 0) {
            lastObservation = Observation({
                price: bandData.rate,
                priceCumulative: 0,
                timestamp: bandData.lastUpdatedBase
            });
        } else {
            // BPF_IT: invalid timestamp
            lastObservation = observations[currentObservationIndex - 1];
            require(bandData.lastUpdatedBase > lastObservation.timestamp, "BPF_IT");
        }

        uint256 elapsedTime = bandData.lastUpdatedBase - lastObservation.timestamp;
        // overflow is desired
        observations[currentObservationIndex++] = Observation({
            priceCumulative: lastObservation.priceCumulative + (lastObservation.price * elapsedTime),
            timestamp: bandData.lastUpdatedBase,
            price: bandData.rate
        });

        emit PriceUpdated(baseAsset, bandData.rate, bandData.lastUpdatedBase, currentObservationIndex - 1);
    }

    //
    // EXTERNAL VIEW
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

            console.log("index: ", index);
            console.log("index timestamp: ", observations[index].timestamp);

            if (observations[index].timestamp <= targetTimestamp) {
                // if the next observation is empty, use the last one
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

        console.log("indexes : ", beforeOrAtIndex, atOrAfterIndex);
        beforeOrAt = observations[beforeOrAtIndex];
        atOrAfter = observations[atOrAfterIndex];
        // if the timestamp of right bound is earlier than the timestamp of left bound,
        // it means the left bound is the lastest observation.
        // Then we set the right bound to the left bound.
        if (atOrAfter.timestamp < beforeOrAt.timestamp) {
            atOrAfter = beforeOrAt;
        }
    }

    function getPrice(uint256 interval) external view override returns (uint256) {
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
        console.log("currentPriceCumulative", currentPriceCumulative);

        //
        //                   beforeOrAt                    atOrAfter
        //      ---------+---------+-------------+---------------+---------+---------
        //               |                       |                         |
        // case 1  targetTimestamp               |                         |
        // case 2                                |                   targetTimestamp
        // case 3                          targetTimestamp
        //
        uint256 targetPriceCumulative;
        // case1. not enough historical data
        if (targetTimestamp < beforeOrAt.timestamp) {
            console.log("case 1");
            targetTimestamp = beforeOrAt.timestamp;
            targetPriceCumulative = beforeOrAt.priceCumulative;
        }
        // case2. the latest data is older than requested
        else if (atOrAfter.timestamp <= targetTimestamp) {
            console.log("case 2");
            targetTimestamp = atOrAfter.timestamp;
            targetPriceCumulative = atOrAfter.priceCumulative;
        }
        // TODO figure it out. could be either case1 or case2
        else if (atOrAfter.timestamp == beforeOrAt.timestamp) {
            console.log("case 1 or case 2");
            targetPriceCumulative = beforeOrAt.priceCumulative;
        }
        // case3 at beforeOrAt or at atOrAfter or in the middle
        else {
            // we're at the left boundary
            if (targetTimestamp == beforeOrAt.timestamp) {
                targetPriceCumulative = beforeOrAt.priceCumulative;
                console.log("we're at the left boundary");
            }
            // we're at the right boundary
            else if (targetTimestamp == atOrAfter.timestamp) {
                targetPriceCumulative = atOrAfter.priceCumulative;
                console.log("we're at the right boundary");
            }
            // we're in the middle
            else {
                uint256 observationTimeDelta = atOrAfter.timestamp - beforeOrAt.timestamp;
                uint256 targetTimeDelta = targetTimestamp - beforeOrAt.timestamp;
                targetPriceCumulative =
                    beforeOrAt.priceCumulative +
                    ((atOrAfter.priceCumulative - beforeOrAt.priceCumulative) * targetTimeDelta) /
                    observationTimeDelta;

                console.log("targetPriceCumulative", targetPriceCumulative);
            }
        }

        console.log("currentPriceCumulative", currentPriceCumulative);
        console.log("targetPriceCumulative", targetPriceCumulative);

        return (currentPriceCumulative - targetPriceCumulative) / (currentTimestamp - targetTimestamp);
    }

    //
    // EXTERNAL PURE
    //

    function decimals() external pure override returns (uint8) {
        return 18;
    }
}
