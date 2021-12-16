// SPDX-License-Identifier: MIT License
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { BlockContext } from "./base/BlockContext.sol";
import { IPriceFeed } from "./interface/IPriceFeed.sol";
import { IStdReference } from "./interface/bandProtocol/IStdReference.sol";

contract BandPriceFeed is IPriceFeed, BlockContext {
    using Address for address;

    //
    // STRUCT
    //

    struct Observation {
        uint256 priceCumulative;
        uint256 timestamp;
    }

    string public constant QUOTE_ASSET = "USD";

    string public baseAsset;
    IStdReference public stdRef;
    Observation[] public observations; // TODO: restrict array size

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

    /// @dev should be called by a keeper
    function updateLatestPriceData() external {
        Observation memory lastObservation = observations[observations.length - 1];

        IStdReference.ReferenceData memory bandData = stdRef.getReferenceData(baseAsset, QUOTE_ASSET);
        // BPF_ITQ: invalid timestamp for quote
        require(bandData.lastUpdatedQuote > 0, "BPF_ITQ");
        // BPF_ITB: invalid timestamp for base
        require(bandData.lastUpdatedBase > lastObservation.timestamp, "BPF_ITB");
        // BPF_IP: invalid price
        require(bandData.rate >= 0, "BPF_IP");

        uint256 elapsedTime = bandData.lastUpdatedBase - lastObservation.timestamp;
        observations.push(
            Observation({
                priceCumulative: lastObservation.priceCumulative + (bandData.rate * elapsedTime),
                timestamp: bandData.lastUpdatedBase
            })
        );

        emit PriceUpdated(baseAsset, bandData.rate, bandData.lastUpdatedBase);
    }

    //
    // EXTERNAL VIEW
    //

    function getPrice(uint256 interval) external view override returns (uint256) {
        if (interval == 0) {
            IStdReference.ReferenceData memory bandData = stdRef.getReferenceData(baseAsset, QUOTE_ASSET);
            return bandData.rate;
        }

        // TODO: not enough history data
        uint256 targetTimestamp = _blockTimestamp() - interval;
        uint256 index = observations.length - 1;
        uint256 beforeOrAtIndex;
        uint256 atOrAfterIndex;
        while (true) {
            if (observations[index].timestamp <= targetTimestamp) {
                beforeOrAtIndex = index;
                atOrAfterIndex = beforeOrAtIndex + 1;
                if (atOrAfterIndex >= observations.length) {
                    atOrAfterIndex = beforeOrAtIndex;
                }
                break;
            }
            index = index - 1;
        }

        // TODO: if end == beforeOrAtTarget == atOrAfterTarget
        // TODO: should we query bandData to calculate end?
        Observation memory end = observations[observations.length - 1];
        Observation memory beforeOrAtTarget = observations[beforeOrAtIndex];
        Observation memory atOrAfterTarget = observations[atOrAfterIndex];

        uint256 targetPriceCumulative;
        if (targetTimestamp == beforeOrAtTarget.timestamp) {
            // we're at the left boundary
            targetPriceCumulative = beforeOrAtTarget.priceCumulative;
        } else if (targetTimestamp == atOrAfterTarget.timestamp) {
            // we're at the right boundary
            targetPriceCumulative = atOrAfterTarget.priceCumulative;
        } else {
            // we're in the middle
            uint256 observationTimeDelta = atOrAfterTarget.timestamp - beforeOrAtTarget.timestamp;
            uint256 targetTimeDelta = targetTimestamp - beforeOrAtTarget.timestamp;
            targetPriceCumulative =
                beforeOrAtTarget.priceCumulative +
                ((atOrAfterTarget.priceCumulative - beforeOrAtTarget.priceCumulative) / observationTimeDelta) *
                targetTimeDelta;
        }

        // TODO: if twap <= 0?
        uint256 twap = (end.priceCumulative - targetPriceCumulative) / (end.timestamp - targetTimestamp);
        return twap;
    }

    //
    // EXTERNAL PURE
    //

    function decimals() external pure override returns (uint8) {
        return 18;
    }

    //
    // INTERNAL
    //
}
