pragma solidity 0.7.6;

import "forge-std/Test.sol";
import { TestAggregatorV3 } from "../../contracts/test/TestAggregatorV3.sol";
import { ChainlinkPriceFeedV3 } from "../../contracts/ChainlinkPriceFeedV3.sol";

contract AggregatorV3Broken is TestAggregatorV3 {
    function latestRoundData()
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
        revert();
    }

    function decimals() external view override returns (uint8) {
        revert();
    }
}

contract Setup is Test {
    uint256 internal _timeout = 40 * 60; // 40 mins
    uint80 internal _twapInterval = 30 * 60; // 30 mins

    TestAggregatorV3 internal _testAggregator;
    ChainlinkPriceFeedV3 internal _chainlinkPriceFeedV3;

    // for test_cachePrice_freezedReason_is_NoResponse()
    AggregatorV3Broken internal _aggregatorV3Broken;
    ChainlinkPriceFeedV3 internal _chainlinkPriceFeedV3Broken;

    function setUp() public virtual {
        _testAggregator = _create_TestAggregator();

        _aggregatorV3Broken = _create_AggregatorV3Broken();
        _chainlinkPriceFeedV3Broken = _create_ChainlinkPriceFeedV3(_aggregatorV3Broken);

        // s.t. _chainlinkPriceFeedV3Broken will revert on decimals()
        vm.clearMockedCalls();
    }

    function _create_TestAggregator() internal returns (TestAggregatorV3) {
        TestAggregatorV3 aggregator = new TestAggregatorV3();
        vm.mockCall(address(aggregator), abi.encodeWithSelector(aggregator.decimals.selector), abi.encode(8));
        return aggregator;
    }

    function _create_ChainlinkPriceFeedV3(TestAggregatorV3 aggregator) internal returns (ChainlinkPriceFeedV3) {
        return new ChainlinkPriceFeedV3(aggregator, _timeout, _twapInterval);
    }

    function _create_AggregatorV3Broken() internal returns (AggregatorV3Broken) {
        AggregatorV3Broken aggregator = new AggregatorV3Broken();
        vm.mockCall(address(aggregator), abi.encodeWithSelector(aggregator.decimals.selector), abi.encode(8));
        return aggregator;
    }
}
