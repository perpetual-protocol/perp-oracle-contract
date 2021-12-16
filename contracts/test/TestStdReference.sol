// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import { IStdReference } from "../interface/bandProtocol/IStdReference.sol";

contract TestStdReference is IStdReference {
    constructor() {}

    function getReferenceData(string memory _base, string memory _quote)
        external
        view
        override
        returns (ReferenceData memory)
    {
        revert();
    }

    function getReferenceDataBulk(string[] memory _bases, string[] memory _quotes)
        external
        view
        override
        returns (ReferenceData[] memory)
    {
        revert();
    }
}
