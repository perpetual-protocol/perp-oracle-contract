// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

import { BlockContext } from "../base/BlockContext.sol";
import { SafeMath } from "@openzeppelin/contracts/math/SafeMath.sol";

contract CumulativeTwap is BlockContext {
    using SafeMath for uint256;

    //
    // STRUCT
    //

    struct Observation {
        uint256 price;
        uint256 priceCumulative;
        uint256 timestamp;
    }

    //
    // STATE
    //

    uint16 public currentObservationIndex;
    uint16 internal constant MAX_OBSERVATION = 1800;
    // let's use 15 mins and 1 hr twap as example
    // if the price is updated every 2 secs, 1hr twap Observation should have 60 / 2 * 60 = 1800 slots
    Observation[MAX_OBSERVATION] public observations;

    //
    // INTERNAL
    //

    function _update(uint256 price, uint256 lastUpdatedTimestamp) internal returns (bool) {
        // for the first time updating
        if (currentObservationIndex == 0 && observations[0].timestamp == 0) {
            observations[0] = Observation({ price: price, priceCumulative: 0, timestamp: lastUpdatedTimestamp });
            return true;
        }

        Observation memory lastObservation = observations[currentObservationIndex];

        // CT_IT: invalid timestamp
        require(lastUpdatedTimestamp >= lastObservation.timestamp, "CT_IT");

        // DO NOT accept same timestamp and different price
        // CT_IPWU: invalid price when update
        if (lastUpdatedTimestamp == lastObservation.timestamp) {
            require(price == lastObservation.price, "CT_IPWU");
        }

        // if the price remains still, there's no need for update
        if (price == lastObservation.price) {
            return false;
        }

        // ring buffer index, make sure the currentObservationIndex is less than MAX_OBSERVATION
        currentObservationIndex = (currentObservationIndex + 1) % MAX_OBSERVATION;

        uint256 timestampDiff = lastUpdatedTimestamp - lastObservation.timestamp;
        observations[currentObservationIndex] = Observation({
            priceCumulative: lastObservation.priceCumulative + (lastObservation.price * timestampDiff),
            timestamp: lastUpdatedTimestamp,
            price: price
        });
        return true;
    }

    /// @dev This function will return 0 in following cases:
    /// 1. Not enough historical data (0 observation)
    /// 2. Not enough historical data (not enough observation)
    /// 3. interval == 0
    function _calculateTwap(
        uint256 interval,
        uint256 price,
        uint256 latestUpdatedTimestamp
    ) internal view returns (uint256) {
        // for the first time calculating
        if ((currentObservationIndex == 0 && observations[0].timestamp == 0) || interval == 0) {
            return 0;
        }

        Observation memory latestObservation = observations[currentObservationIndex];

        // DO NOT accept same timestamp and different price
        // CT_IPWCT: invalid price when calculating twap
        // it's to be consistent with the logic of _update
        if (latestObservation.timestamp == latestUpdatedTimestamp) {
            require(price == latestObservation.price, "CT_IPWCT");
        }

        uint256 currentTimestamp = _blockTimestamp();
        uint256 targetTimestamp = currentTimestamp.sub(interval);
        uint256 currentCumulativePrice =
            latestObservation.priceCumulative.add(
                (latestObservation.price.mul(latestUpdatedTimestamp.sub(latestObservation.timestamp))).add(
                    price.mul(currentTimestamp.sub(latestUpdatedTimestamp))
                )
            );

        // case 1
        //                                 beforeOrAt     (it doesn't matter)
        //                              targetTimestamp   atOrAfter
        //      ------------------+-------------+---------------+----------------->

        // case 2
        //          (it doesn't matter)     atOrAfter
        //                   beforeOrAt   targetTimestamp
        //      ------------------+-------------+--------------------------------->

        // case 3
        //                   beforeOrAt   targetTimestamp   atOrAfter
        //      ------------------+-------------+---------------+----------------->

        //                                  atOrAfter
        //                   beforeOrAt   targetTimestamp
        //      ------------------+-------------+---------------+----------------->

        (Observation memory beforeOrAt, Observation memory atOrAfter) = _getSurroundingObservations(targetTimestamp);
        uint256 targetCumulativePrice;

        // case1. left boundary
        if (targetTimestamp == beforeOrAt.timestamp) {
            targetCumulativePrice = beforeOrAt.priceCumulative;
        }
        // case2. right boundary
        else if (atOrAfter.timestamp == targetTimestamp) {
            targetCumulativePrice = atOrAfter.priceCumulative;
        }
        // not enough historical data
        else if (beforeOrAt.timestamp == atOrAfter.timestamp) {
            return 0;
        }
        // case3. in the middle
        else {
            // atOrAfter.timestamp == 0 implies beforeOrAt = observations[currentObservationIndex]
            // which means there's no atOrAfter from _getSurroundingObservations
            // and atOrAfter.priceCumulative should eaual to targetCumulativePrice
            if (atOrAfter.timestamp == 0) {
                targetCumulativePrice =
                    beforeOrAt.priceCumulative +
                    (beforeOrAt.price * (targetTimestamp - beforeOrAt.timestamp));
            } else {
                uint256 targetTimeDelta = targetTimestamp - beforeOrAt.timestamp;
                uint256 observationTimeDelta = atOrAfter.timestamp - beforeOrAt.timestamp;

                targetCumulativePrice = beforeOrAt.priceCumulative.add(
                    ((atOrAfter.priceCumulative.sub(beforeOrAt.priceCumulative)).mul(targetTimeDelta)).div(
                        observationTimeDelta
                    )
                );
            }
        }

        return currentCumulativePrice.sub(targetCumulativePrice).div(interval);
    }

    function _getSurroundingObservations(uint256 targetTimestamp)
        internal
        view
        returns (Observation memory beforeOrAt, Observation memory atOrAfter)
    {
        beforeOrAt = observations[currentObservationIndex];

        // if the target is chronologically at or after the newest observation, we can early return
        if (observations[currentObservationIndex].timestamp <= targetTimestamp) {
            // if the observation is the same as the targetTimestamp
            // atOrAfter doesn't matter
            // if the observation is less than the targetTimestamp
            // simply return empty atOrAfter
            // atOrAfter repesents latest price and timestamp
            return (beforeOrAt, atOrAfter);
        }

        // now, set before to the oldest observation
        beforeOrAt = observations[(currentObservationIndex + 1) % MAX_OBSERVATION];
        if (beforeOrAt.timestamp == 0) {
            beforeOrAt = observations[0];
        }

        // ensure that the target is chronologically at or after the oldest observation
        // if no enough historical data, simply return two beforeOrAt and return 0 at _calculateTwap
        if (beforeOrAt.timestamp > targetTimestamp) {
            return (beforeOrAt, beforeOrAt);
        }

        return _binarySearch(targetTimestamp);
    }

    function _binarySearch(uint256 targetTimestamp)
        private
        view
        returns (Observation memory beforeOrAt, Observation memory atOrAfter)
    {
        uint256 l = (currentObservationIndex + 1) % MAX_OBSERVATION; // oldest observation
        uint256 r = l + MAX_OBSERVATION - 1; // newest observation
        uint256 i;

        while (true) {
            i = (l + r) / 2;

            beforeOrAt = observations[i % MAX_OBSERVATION];

            // we've landed on an uninitialized observation, keep searching higher (more recently)
            if (beforeOrAt.timestamp == 0) {
                l = i + 1;
                continue;
            }

            atOrAfter = observations[(i + 1) % MAX_OBSERVATION];

            bool targetAtOrAfter = beforeOrAt.timestamp <= targetTimestamp;

            // check if we've found the answer!
            if (targetAtOrAfter && targetTimestamp <= atOrAfter.timestamp) break;

            if (!targetAtOrAfter) r = i - 1;
            else l = i + 1;
        }
    }
}
