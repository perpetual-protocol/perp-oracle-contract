// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.7.6;

import { AggregatorV3Interface } from "@chainlink/contracts/src/v0.6/interfaces/AggregatorV3Interface.sol";

contract TestAggregatorV3 is AggregatorV3Interface {
    struct RoundData {
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }

    mapping(uint80 => RoundData) public roundData;

    uint80 public latestRound;

    constructor() {}

    function decimals() external view virtual override returns (uint8) {
        return 18;
    }

    function description() external view override returns (string memory) {
        revert();
    }

    function version() external view override returns (uint256) {
        revert();
    }

    function setRoundData(
        uint80 roundId,
        int256 answer,
        uint256 startedAt,
        uint256 updatedAt,
        uint80 answeredInRound
    ) external {
        roundData[roundId] = RoundData({
            answer: answer,
            startedAt: startedAt,
            updatedAt: updatedAt,
            answeredInRound: answeredInRound
        });
        latestRound = roundId;
    }

    function getRoundData(uint80 _roundId)
        external
        view
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (
            _roundId,
            roundData[_roundId].answer,
            roundData[_roundId].startedAt,
            roundData[_roundId].updatedAt,
            roundData[_roundId].answeredInRound
        );
    }

    function latestRoundData()
        external
        view
        virtual
        override
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (
            latestRound,
            roundData[latestRound].answer,
            roundData[latestRound].startedAt,
            roundData[latestRound].updatedAt,
            roundData[latestRound].answeredInRound
        );
    }

    // won't use in production, just for knowing how roundId works
    // https://docs.chain.link/docs/historical-price-data/#roundid-in-proxy
    function computeRoundId(uint16 phaseId, uint64 aggregatorRoundId) external pure returns (uint80) {
        return uint80((uint256(phaseId) << 64) | aggregatorRoundId);
    }
}
