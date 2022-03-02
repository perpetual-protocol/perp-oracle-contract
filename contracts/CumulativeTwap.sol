// SPDX-License-Identifier: MIT License
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import { BlockContext } from "./base/BlockContext.sol";
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
    // EVENT
    //
    event PriceUpdated(uint256 price, uint256 timestamp, uint8 indexAt);

    //
    // STATE
    //
    // let's use 15 mins and 1 hr twap as example
    // if the price is being updated 15 secs, then needs 60 and 240 historical data for 15mins and 1hr twap.
    Observation[256] public observations;

    uint8 public currentObservationIndex;

    function _update(uint256 price, uint256 lastUpdatedTimestamp) internal {
        // for the first time update
        if (currentObservationIndex == 0 && observations[0].timestamp == 0) {
            observations[0] = Observation({ price: price, priceCumulative: 0, timestamp: lastUpdatedTimestamp });
            emit PriceUpdated(price, lastUpdatedTimestamp, 0);
            return;
        }

        // CT_IT: invalid timestamp
        // add `==` in the require statement in case that two or more price with the same timestamp
        // this might happen on Optimism bcs their timestamp is not up-to-date
        Observation memory lastObservation = observations[currentObservationIndex];
        require(lastUpdatedTimestamp >= lastObservation.timestamp, "CT_IT");

        // overflow of currentObservationIndex is desired since currentObservationIndex is uint8 (0 - 255),
        // so 255 + 1 will be 0
        currentObservationIndex++;

        uint256 elapsedTime = lastUpdatedTimestamp - lastObservation.timestamp;
        observations[currentObservationIndex] = Observation({
            priceCumulative: lastObservation.priceCumulative + (lastObservation.price * elapsedTime),
            timestamp: lastUpdatedTimestamp,
            price: price
        });

        emit PriceUpdated(price, lastUpdatedTimestamp, currentObservationIndex);
    }

    function _getPrice(
        uint256 interval,
        uint256 latestPrice,
        uint256 latestUpdatedTimestamp
    ) internal view returns (uint256) {
        Observation memory lastestObservation = observations[currentObservationIndex];
        if (lastestObservation.price == 0) {
            // CT_ND: no data
            revert("CT_ND");
        }

        uint256 currentTimestamp = _blockTimestamp();
        uint256 targetTimestamp = currentTimestamp.sub(interval);
        (Observation memory beforeOrAt, Observation memory atOrAfter) = _getSurroundingObservations(targetTimestamp);
        uint256 currentCumulativePrice =
            lastestObservation.priceCumulative.add(
                (lastestObservation.price.mul(latestUpdatedTimestamp.sub(lastestObservation.timestamp))).add(
                    latestPrice.mul(currentTimestamp.sub(latestUpdatedTimestamp))
                )
            );

        //
        //                   beforeOrAt                    atOrAfter
        //      ------------------+-------------+---------------+------------------
        //                <-------|             |               |
        // case 1       targetTimestamp         |               |------->
        // case 2                               |              targetTimestamp
        // case 3                          targetTimestamp
        //
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

        return currentCumulativePrice.sub(targetCumulativePrice).div(currentTimestamp - targetTimestamp);
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

        // if timestamp of the right bound is earlier than timestamp of the left bound,
        // it means the left bound is the lastest observation.
        // It implies the latest observation is older than requested
        // Then we set the right bound to the left bound.
        if (atOrAfter.timestamp < beforeOrAt.timestamp) {
            atOrAfter = beforeOrAt;
        }
    }
}
