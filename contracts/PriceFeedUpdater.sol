// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IPriceFeedUpdate } from "./interface/IPriceFeedUpdate.sol";

contract PriceFeedUpdater {
    using Address for address;

    address[] public priceFeeds;

    constructor(address[] memory priceFeedsArg) {
        // PFU_PFANC: price feed address is not contract
        for (uint256 i = 0; i < priceFeedsArg.length; i++) {
            require(priceFeedsArg[i].isContract(), "PFU_PFANC");
        }

        priceFeeds = priceFeedsArg;
    }

    fallback() external {}
}
