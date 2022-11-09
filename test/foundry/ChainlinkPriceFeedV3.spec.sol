pragma solidity 0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";

import "./BaseSetup.sol";
import "../../contracts/interface/IPriceFeedV3.sol";

contract ChainlinkPriceFeedV3Test is IPriceFeedV3Event, BaseSetup {
    function setUp() public virtual override {
        BaseSetup.setUp();
    }

    function test_getAggregator() public {
        assertEq(chainlinkPriceFeedV3.getAggregator(), address(testAggregator));
    }

    function test_getLastValidPrice_is_0_when_initialized() public {
        assertEq(chainlinkPriceFeedV3.getLastValidPrice(), 0);
    }

    function test_getLastValidTime_is_0_when_initialized() public {
        assertEq(chainlinkPriceFeedV3.getLastValidTime(), 0);
    }

    function test_decimals() public {
        assertEq(uint256(chainlinkPriceFeedV3.decimals()), uint256(testAggregator.decimals()));
    }

    function test_cachePrice_first_call_with_valid_price() public {
        uint256 price = 1000 * 1e8;
        uint256 timestamp = block.timestamp;
        uint256 roundId = 1;
        vm.mockCall(
            address(testAggregator),
            abi.encodeWithSelector(testAggregator.latestRoundData.selector),
            abi.encode(roundId, price, timestamp, timestamp, roundId)
        );

        vm.expectEmit(false, false, false, true, address(chainlinkPriceFeedV3));
        emit PriceUpdated(price, timestamp, FreezedReason.NotFreezed);
        assertEq(chainlinkPriceFeedV3.cachePrice(), price);
        assertEq(chainlinkPriceFeedV3.getLastValidPrice(), price);
    }
}
