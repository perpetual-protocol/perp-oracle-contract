// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { BlockContext } from "./base/BlockContext.sol";
import { IPriceFeedV2 } from "./interface/IPriceFeedV2.sol";
import { IStdReference } from "./interface/bandProtocol/IStdReference.sol";
import { CachedTwap } from "./twap/CachedTwap.sol";

contract BandPriceFeed is IPriceFeedV2, BlockContext, CachedTwap {
    using Address for address;

    //
    // STATE
    //
    string public constant QUOTE_ASSET = "USD";

    string public baseAsset;
    IStdReference public stdRef;

    //
    // EXTERNAL NON-VIEW
    //

    constructor(
        IStdReference stdRefArg,
        string memory baseAssetArg,
        uint80 cacheTwapInterval
    ) CachedTwap(cacheTwapInterval) {
        // BPF_ANC: Reference address is not contract
        require(address(stdRefArg).isContract(), "BPF_ANC");

        stdRef = stdRefArg;
        baseAsset = baseAssetArg;
    }

    /// @dev anyone can help update it.
    function update() external {
        IStdReference.ReferenceData memory bandData = _getReferenceData();
        bool isUpdated = _update(bandData.rate, bandData.lastUpdatedBase);
        // BPF_NU: not updated
        require(isUpdated, "BPF_NU");
    }

    function cacheTwap(uint256 interval) external override returns (uint256) {
        IStdReference.ReferenceData memory latestBandData = _getReferenceData();
        if (interval == 0) {
            return latestBandData.rate;
        }
        return _cacheTwap(interval, latestBandData.rate, latestBandData.lastUpdatedBase);
    }

    //
    // EXTERNAL VIEW
    //

    function getPrice(uint256 interval) public view override returns (uint256) {
        IStdReference.ReferenceData memory latestBandData = _getReferenceData();
        if (interval == 0) {
            return latestBandData.rate;
        }
        return _getCachedTwap(interval, latestBandData.rate, latestBandData.lastUpdatedBase);
    }

    //
    // EXTERNAL PURE
    //

    function decimals() external pure override returns (uint8) {
        // We assume Band Protocol always has 18 decimals
        // https://docs.bandchain.org/band-standard-dataset/using-band-dataset/using-band-dataset-evm.html
        return 18;
    }

    //
    // INTERNAL VIEW
    //

    function _getReferenceData() internal view returns (IStdReference.ReferenceData memory) {
        IStdReference.ReferenceData memory bandData = stdRef.getReferenceData(baseAsset, QUOTE_ASSET);
        // BPF_TQZ: timestamp for quote is zero
        require(bandData.lastUpdatedQuote > 0, "BPF_TQZ");
        // BPF_TBZ: timestamp for base is zero
        require(bandData.lastUpdatedBase > 0, "BPF_TBZ");
        // BPF_IP: invalid price
        require(bandData.rate > 0, "BPF_IP");

        return bandData;
    }
}
