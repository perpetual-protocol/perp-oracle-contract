pragma solidity 0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";

import "./BaseSetup.sol";
import "../../contracts/interface/IPriceFeedV3.sol";

contract ChainlinkPriceFeedV3Test is IPriceFeedV3Event, BaseSetup {
    function setUp() public virtual override {
        BaseSetup.setUp();
    }

    function test_cachePrice_first_call_with_valid_price() public {
        uint256 price = 1000 * 1e8;
        uint256 timestamp = block.timestamp;
        vm.mockCall(
            address(testAggregator),
            abi.encodeWithSelector(testAggregator.latestRoundData.selector),
            abi.encode(1, price, timestamp, timestamp, 1)
        );

        vm.expectEmit(false, false, false, true, address(chainlinkPriceFeedV3));
        emit PriceUpdated(price, timestamp, FreezedReason.NotFreezed);
        assertEq(chainlinkPriceFeedV3.cachePrice(), price);
    }
}
