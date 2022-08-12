// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.7.6;

import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { IPriceFeedUpdate } from "./interface/IPriceFeedUpdate.sol";
import { SafeOwnableNonUpgradable } from "./base/SafeOwnableNonUpgradable.sol";

contract PriceFeedUpdater is SafeOwnableNonUpgradable {
    using Address for address;

    address[] internal _priceFeeds;

    constructor(address[] memory priceFeedsArg) {
        setPriceFeeds(priceFeedsArg);
    }

    //
    // EXTERNAL NON-VIEW
    //

    /* solhint-disable payable-fallback */
    fallback() external {
        for (uint256 i = 0; i < _priceFeeds.length; i++) {
            // Updating PriceFeed might be failed because of price not changed,
            // Add try-catch here to update all markets anyway
            /* solhint-disable no-empty-blocks */
            try IPriceFeedUpdate(_priceFeeds[i]).update() {} catch {}
        }
    }

    //
    // EXTERNAL VIEW
    //

    function getPriceFeeds() external view returns (address[] memory) {
        return _priceFeeds;
    }

    //
    // PUBLIC NON-VIEW
    //

    function setPriceFeeds(address[] memory priceFeedsArg) public onlyOwner {
        // PFU_PFANC: price feed address is not contract
        for (uint256 i = 0; i < priceFeedsArg.length; i++) {
            require(priceFeedsArg[i].isContract(), "PFU_PFANC");
        }

        _priceFeeds = priceFeedsArg;
    }
}
