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

contract ChainlinkPriceFeedV3Broken is ChainlinkPriceFeedV3 {
    constructor(
        TestAggregatorV3 aggregator,
        uint256 timeout,
        uint24 maxOutlierDeviationRatio,
        uint256 outlierCoolDownPeriod
    ) ChainlinkPriceFeedV3(aggregator, timeout, maxOutlierDeviationRatio, outlierCoolDownPeriod) {}

    function getFreezedReason() public returns (FreezedReason) {
        return _getFreezedReason(_getChainlinkData());
    }
}

contract BaseSetup is Test {
    uint256 internal constant _TIMEOUT = 40 * 60;

    TestAggregatorV3 internal _testAggregator;
    ChainlinkPriceFeedV3 internal _chainlinkPriceFeedV3;

    AggregatorV3Broken internal _aggregatorV3Broken;
    ChainlinkPriceFeedV3Broken internal _chainlinkPriceFeedV3Broken;

    function setUp() public virtual {
        _testAggregator = _createTestAggregator();
        _chainlinkPriceFeedV3 = _createChainlinkPriceFeedV3();

        _aggregatorV3Broken = _createAggregatorBroken();
        _chainlinkPriceFeedV3Broken = __createChainlinkPriceFeedV3Broken();

        vm.clearMockedCalls();
    }

    //
    // INTERNAL VIEW
    //

    function _createTestAggregator() internal returns (TestAggregatorV3) {
        TestAggregatorV3 aggregator = new TestAggregatorV3();
        vm.mockCall(address(aggregator), abi.encodeWithSelector(aggregator.decimals.selector), abi.encode(8));
        return aggregator;
    }

    function _createChainlinkPriceFeedV3() internal returns (ChainlinkPriceFeedV3) {
        return new ChainlinkPriceFeedV3(_testAggregator, _TIMEOUT, 1e5, 10);
    }

    function _createAggregatorBroken() internal returns (AggregatorV3Broken) {
        AggregatorV3Broken aggregator = new AggregatorV3Broken();
        vm.mockCall(address(aggregator), abi.encodeWithSelector(aggregator.decimals.selector), abi.encode(8));
        return aggregator;
    }

    function __createChainlinkPriceFeedV3Broken() internal returns (ChainlinkPriceFeedV3Broken) {
        return new ChainlinkPriceFeedV3Broken(_aggregatorV3Broken, _TIMEOUT, 1e5, 10);
    }
}
