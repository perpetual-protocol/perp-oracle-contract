// SPDX-License-Identifier: MIT License
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { BlockContext } from "./base/BlockContext.sol";
import { IPriceFeed } from "./interface/IPriceFeed.sol";
import { IStdReference } from "./interface/bandProtocol/IStdReference.sol";

contract BandPriceFeed is IPriceFeed, BlockContext {
    using Address for address;

    string public constant QUOTE_ASSET = "USD";

    IStdReference public priceFeedRef;
    string public baseAsset;
    uint256 public latestTimestamp;

    event PriceUpdated(uint256 price, uint256 timestamp);

    //
    // FUNCTIONS
    //
    constructor(IStdReference ref, string memory baseAssetArg) {
        // BPF_ANC: Reference address is not contract
        require(address(ref).isContract(), "BPF_ANC");

        priceFeedRef = ref;
        baseAsset = baseAssetArg;
    }

    function decimals() external pure override returns (uint8) {
        return 18;
    }

    function getPrice(uint256 interval) external view override returns (uint256) {
    }

    // EXTERNAL

    function updateLatestRoundData() external {
        IStdReference.ReferenceData memory data = priceFeedRef.getReferenceData(baseAsset, QUOTE_ASSET);
        require(data.lastUpdatedQuote > 0, "BPF_ITQ");
        require(data.lastUpdatedBase > latestTimestamp, "BPF_ITB");
        require(data.rate >= 0, "negative price");

        emit PriceUpdated(data.rate, data.lastUpdatedBase);

        latestTimestamp = data.lastUpdatedBase;
    }

    //
    // INTERNAL
    //
}
