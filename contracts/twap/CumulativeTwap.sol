// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

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
    uint16 internal constant UINT16_MAX = 65535;
    // let's use 15 mins and 1 hr twap as example
    // if the price is updated every 15 secs, then we need 60 and 240 historical data for 15mins and 1hr twap
    Observation[UINT16_MAX + 1] public observations;

    //
    // INTERNAL
    //

    function _update(uint256 price, uint256 lastUpdatedTimestamp) internal {
        // for the first time updating
        if (currentObservationIndex == 0 && observations[0].timestamp == 0) {
            observations[0] = Observation({ price: price, priceCumulative: 0, timestamp: lastUpdatedTimestamp });
            return;
        }

        Observation memory lastObservation = observations[currentObservationIndex];
        // CT_IT: invalid timestamp
        require(lastUpdatedTimestamp > lastObservation.timestamp, "CT_IT");

        // if the price remains still, there's no need for update
        if (price == lastObservation.price) {
            return;
        }

        // overflow of currentObservationIndex is expected since currentObservationIndex is uint16 (0 - 65535),
        // so 65535 + 1 will be 0
        currentObservationIndex++;

        uint256 timestampDiff = lastUpdatedTimestamp - lastObservation.timestamp;
        observations[currentObservationIndex] = Observation({
            priceCumulative: lastObservation.priceCumulative + (lastObservation.price * timestampDiff),
            timestamp: lastUpdatedTimestamp,
            price: price
        });
    }

    function _calculateTwap(
        uint256 interval,
        uint256 price,
        uint256 latestUpdatedTimestamp
    ) internal view returns (uint256) {
        // for the first time calculating
        if (currentObservationIndex == 0 && observations[0].timestamp == 0) {
            return 0;
        }

        Observation memory latestObservation = observations[currentObservationIndex];

        uint256 currentTimestamp = _blockTimestamp();
        uint256 targetTimestamp = currentTimestamp.sub(interval);
        uint256 currentCumulativePrice =
            latestObservation.priceCumulative.add(
                (latestObservation.price.mul(latestUpdatedTimestamp.sub(latestObservation.timestamp))).add(
                    price.mul(currentTimestamp.sub(latestUpdatedTimestamp))
                )
            );

        //
        //                   beforeOrAt                    atOrAfter
        //      ------------------+-------------+---------------+------------------
        //                <-------|             |               |
        // case 1       targetTimestamp         |               |------->
        // case 2                               |              targetTimestamp
        // case 3                          targetTimestamp

        (Observation memory beforeOrAt, Observation memory atOrAfter) = _getSurroundingObservations(targetTimestamp);
        uint256 targetCumulativePrice;

        // case1. not enough historical data or just enough (`==` case)
        if (targetTimestamp <= beforeOrAt.timestamp) {
            targetTimestamp = beforeOrAt.timestamp;
            targetCumulativePrice = beforeOrAt.priceCumulative;
        }
        // case2. the latest data is older than or equal the request
        else if (atOrAfter.timestamp <= targetTimestamp) {
            targetTimestamp = atOrAfter.timestamp;
            targetCumulativePrice = atOrAfter.priceCumulative;
        }
        // case3. in the middle
        else {
            uint256 observationTimeDelta = atOrAfter.timestamp - beforeOrAt.timestamp;
            uint256 targetTimeDelta = targetTimestamp - beforeOrAt.timestamp;
            targetCumulativePrice = beforeOrAt.priceCumulative.add(
                ((atOrAfter.priceCumulative.sub(beforeOrAt.priceCumulative)).mul(targetTimeDelta)).div(
                    observationTimeDelta
                )
            );
        }

        // 1. if observation has no data / only one data, _calculateTwap returns 0 (above case 1)
        // 2. if not enough data, _calculateTwap returns timestampDiff twap price (above case 1)
        // 3. if exceed the observations' length, _getSurroundingObservations will get reverted

        uint256 timestampDiff = currentTimestamp - targetTimestamp;
        return timestampDiff == 0 ? 0 : currentCumulativePrice.sub(targetCumulativePrice).div(timestampDiff);
    }

    function _getSurroundingObservations(uint256 targetTimestamp)
        internal
        view
        returns (Observation memory beforeOrAt, Observation memory atOrAfter)
    {
        uint16 index = currentObservationIndex;
        uint16 beforeOrAtIndex = index;
        uint16 atOrAfterIndex;

        // if the target is chronologically at or after the newest observation, we can early return
        if (observations[index].timestamp <= targetTimestamp) {
            atOrAfterIndex = beforeOrAtIndex;

            return (observations[beforeOrAtIndex], observations[atOrAfterIndex]);
        }

        // now, set before to the oldest observation
        beforeOrAtIndex = (index + 1);
        if (observations[beforeOrAtIndex].timestamp == 0) {
            beforeOrAtIndex = 0;
        }

        // ensure that the target is chronologically at or after the oldest observation
        // CT_NEH: no enough historical data
        require(observations[beforeOrAtIndex].timestamp <= targetTimestamp, "CT_NEH");

        return binarySearch(targetTimestamp);
    }

    function binarySearch(uint256 targetTimestamp)
        private
        view
        returns (Observation memory beforeOrAt, Observation memory atOrAfter)
    {
        uint256 l = currentObservationIndex + 1; // oldest observation
        uint256 r = l + UINT16_MAX; // newest observation
        uint256 i;

        while (true) {
            i = (l + r) / 2;

            beforeOrAt = observations[i % UINT16_MAX];

            // we've landed on an uninitialized observation, keep searching higher (more recently)
            if (beforeOrAt.timestamp == 0) {
                l = i + 1;
                continue;
            }

            atOrAfter = observations[(i + 1) % UINT16_MAX];

            bool targetAtOrAfter = beforeOrAt.timestamp <= targetTimestamp;

            // check if we've found the answer!
            if (targetAtOrAfter && targetTimestamp <= atOrAfter.timestamp) break;

            if (!targetAtOrAfter) r = i - 1;
            else l = i + 1;
        }
    }
}
