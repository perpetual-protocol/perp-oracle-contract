pragma solidity 0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";

import "./BaseSetup.sol";

contract ChainlinkPriceFeedV3Test is BaseSetup {
    function setUp() public virtual override {
        BaseSetup.setUp();
    }

    function test_cachePrice_first_call_with_valid_price() public {
        vm.mockCall(
            address(testAggregator),
            abi.encodeWithSelector(testAggregator.latestRoundData.selector),
            abi.encode(1, 1000 * 1e8, block.timestamp, block.timestamp, 1)
        );

        assertEq(chainlinkPriceFeedV3.cachePrice(), 1000 * 1e8);
    }
}
