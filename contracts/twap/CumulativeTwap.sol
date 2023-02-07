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

    uint8 public currentObservationIndex;
    // let's use 15 mins and 1 hr twap as example
    // if the price is updated every 15 secs, then we need 60 and 240 historical data for 15mins and 1hr twap
    Observation[256] public observations;

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

        // No need to update, if the latest timestamp is equal to last oberservation
        if (lastUpdatedTimestamp == lastObservation.timestamp) {
            return false;
        }

        // if the price remains still, there's no need for update
        if (price == lastObservation.price) {
            return false;
        }

        // overflow of currentObservationIndex is expected since currentObservationIndex is uint8 (0 - 255),
        // so 255 + 1 will be 0
        currentObservationIndex++;

        uint256 timestampDiff = lastUpdatedTimestamp - lastObservation.timestamp;
        observations[currentObservationIndex] = Observation({
            priceCumulative: lastObservation.priceCumulative + (lastObservation.price * timestampDiff),
            timestamp: lastUpdatedTimestamp,
            price: price
        });
        return true;
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

        // Use latestObservation instead, if the latest updated timestamp is equal to latestObservation's timestamp
        // it's to be consistent with the logic of _update
        if (latestObservation.timestamp == latestUpdatedTimestamp) {
            price = latestObservation.price;
            latestUpdatedTimestamp = latestObservation.timestamp;
        }

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
        uint8 index = currentObservationIndex;
        uint8 beforeOrAtIndex;
        uint8 atOrAfterIndex;

        // run at most 256 times
        uint256 observationLen = observations.length;
        uint256 i;
        for (i = 0; i < observationLen; i++) {
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

        // not enough historical data to query
        if (i == observationLen) {
            // CT_NEH: no enough historical data
            revert("CT_NEH");
        }

        beforeOrAt = observations[beforeOrAtIndex];
        atOrAfter = observations[atOrAfterIndex];

        // if the timestamp of the right bound is earlier than timestamp of the left bound,
        // either there's only one record, or atOrAfterIndex overflows
        // in these cases, we set the right bound the same as the left bound.
        if (atOrAfter.timestamp < beforeOrAt.timestamp) {
            atOrAfter = beforeOrAt;
        }
    }
}
