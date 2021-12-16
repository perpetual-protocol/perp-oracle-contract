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
    Observation[] public observations; // TODO: restrict array size

    uint256 latestUpdatedTimestamp;
    uint256 latestUpdatedTwap;

    event PriceUpdated(string indexed baseAsset, uint256 price, uint256 timestamp);

    //
    // EXTERNAL NON-VIEW
    //

    constructor(IStdReference stdRefArg, string memory baseAssetArg) {
        // BPF_ANC: Reference address is not contract
        require(address(stdRefArg).isContract(), "BPF_ANC");

        stdRef = stdRefArg;
        baseAsset = baseAssetArg;
    }

    /// @dev will be called by a keeper
    function update() external {
        IStdReference.ReferenceData memory bandData = stdRef.getReferenceData(baseAsset, QUOTE_ASSET);
        // BPF_TQZ: timestamp for quote is zero
        require(bandData.lastUpdatedQuote > 0, "BPF_TQZ");
        // BPF_TBZ: timestamp for base is zero
        require(bandData.lastUpdatedBase > 0, "BPF_TBZ");
        // BPF_IP: invalid price
        require(bandData.rate > 0, "BPF_IP");

        Observation memory lastObservation;
        if (observations.length == 0) {
            lastObservation = Observation({
                price: bandData.rate,
                priceCumulative: 0,
                timestamp: bandData.lastUpdatedBase
            });
        } else {
            // BPF_IT: invalid timestamp
            require(bandData.lastUpdatedBase > lastObservation.timestamp, "BPF_IT");
            lastObservation = observations[observations.length - 1];
        }

        uint256 elapsedTime = bandData.lastUpdatedBase - lastObservation.timestamp;
        observations.push(
            Observation({
                priceCumulative: lastObservation.priceCumulative + (lastObservation.price * elapsedTime),
                timestamp: bandData.lastUpdatedBase,
                price: bandData.rate
            })
        );

        emit PriceUpdated(baseAsset, bandData.rate, bandData.lastUpdatedBase);
    }

    //
    // EXTERNAL VIEW
    //

    function getPrice(uint256 interval) external view override returns (uint256) {
        IStdReference.ReferenceData memory latestBandData = stdRef.getReferenceData(baseAsset, QUOTE_ASSET);
        // TODO add comment to explain why it's `<= 1`
        if (interval == 0 || observations.length <= 1) {
            return latestBandData.rate;
        }

        Observation memory lastObservation = observations[observations.length - 1];
        uint256 currentTimestamp = _blockTimestamp();
        uint256 currentPriceCumulative =
            lastObservation.priceCumulative +
                (lastObservation.price * (latestBandData.lastUpdatedBase - lastObservation.timestamp)) +
                (latestBandData.rate * (currentTimestamp - latestBandData.lastUpdatedBase));

        uint256 targetTimestamp = currentTimestamp - interval;
        uint256 index = observations.length - 1;
        uint256 beforeOrAtIndex;
        uint256 atOrAfterIndex;
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
                beforeOrAtIndex = index;
                atOrAfterIndex = beforeOrAtIndex + 1;
                // only happens when requested interval is later than the timestamp of the last observation
                if (atOrAfterIndex >= observations.length) {
                    atOrAfterIndex = beforeOrAtIndex;
                }
                break;
            }
            if (index == 0) {
                break;
            }
            index = index - 1;
        }

        console.log("indexes : ", beforeOrAtIndex, atOrAfterIndex);
        Observation memory beforeOrAtTarget = observations[beforeOrAtIndex];
        Observation memory atOrAfterTarget = observations[atOrAfterIndex];

        if (targetTimestamp < beforeOrAtTarget.timestamp) {
            // not enough historical data
            // targetTimestamp --- beforeOrAtTarget --- atOrAfterTarget
            targetTimestamp = beforeOrAtTarget.timestamp;
        } else if (targetTimestamp >= atOrAfterTarget.timestamp) {
            // historical data too old
            // beforeOrAtTarget --- atOrAfterTarget --- targetTimestamp
            targetTimestamp = atOrAfterTarget.timestamp;
        }

        uint256 targetPriceCumulative;
        if (beforeOrAtIndex == atOrAfterIndex) {
            console.log("beforeOrAtIndex == atOrAfterIndex");
            targetPriceCumulative = beforeOrAtTarget.priceCumulative;
        } else {
            if (targetTimestamp == beforeOrAtTarget.timestamp) {
                // we're at the left boundary
                targetPriceCumulative = beforeOrAtTarget.priceCumulative;
                console.log("we're at the left boundary");
            } else if (targetTimestamp == atOrAfterTarget.timestamp) {
                // we're at the right boundary
                targetPriceCumulative = atOrAfterTarget.priceCumulative;
                console.log("we're at the right boundary");
            } else {
                // we're in the middle
                uint256 observationTimeDelta = atOrAfterTarget.timestamp - beforeOrAtTarget.timestamp;
                uint256 targetTimeDelta = targetTimestamp - beforeOrAtTarget.timestamp;
                targetPriceCumulative =
                    beforeOrAtTarget.priceCumulative +
                    ((atOrAfterTarget.priceCumulative - beforeOrAtTarget.priceCumulative) * targetTimeDelta) /
                    observationTimeDelta;

                console.log("targetPriceCumulative", targetPriceCumulative);
            }
        }

        // TODO: if twap <= 0?
        // case 2 end == beforeOrAtTarget || end == atOrAfterTarget
        // twap = 0/123 --> case 1, return price at 2:10
        // twap = 123/0 --> latestBandData.price
        // twap = 123/-456 --> case 1

        if (currentPriceCumulative <= targetPriceCumulative) {
            return latestBandData.rate;
        }

        console.log("latestPriceCumulative", currentPriceCumulative);
        console.log("targetPriceCumulative", targetPriceCumulative);
        console.log("latestTimestamp", currentTimestamp);
        console.log("targetTimestamp", targetTimestamp);

        return (currentPriceCumulative - targetPriceCumulative) / (currentTimestamp - targetTimestamp);
    }

    //
    // EXTERNAL PURE
    //

    function decimals() external pure override returns (uint8) {
        return 18;
    }
}
