pragma solidity 0.7.6;

import "forge-std/Test.sol";
import { TestAggregatorV3 } from "../../contracts/test/TestAggregatorV3.sol";
import { ChainlinkPriceFeedV3 } from "../../contracts/ChainlinkPriceFeedV3.sol";

contract BaseSetup is Test {
    uint256 internal constant _timeout = 40 * 60;
    TestAggregatorV3 internal testAggregator;
    ChainlinkPriceFeedV3 internal chainlinkPriceFeedV3;

    function setUp() public virtual {
        testAggregator = createTestAggregator();
        chainlinkPriceFeedV3 = createChainlinkPriceFeedV3();
    }

    //
    // INTERNAL VIEW
    //

    function createTestAggregator() internal returns (TestAggregatorV3) {
        TestAggregatorV3 aggregator = new TestAggregatorV3();
        vm.mockCall(address(aggregator), abi.encodeWithSelector(aggregator.decimals.selector), abi.encode(8));
        return aggregator;
    }

    function createChainlinkPriceFeedV3() internal returns (ChainlinkPriceFeedV3) {
        return new ChainlinkPriceFeedV3(testAggregator, _timeout, 1e5, 10);
    }
}
