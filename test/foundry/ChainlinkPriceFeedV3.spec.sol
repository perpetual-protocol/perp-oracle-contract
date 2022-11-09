pragma solidity 0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";

import "./BaseSetup.sol";
import "../../contracts/interface/IPriceFeedV3.sol";

contract ChainlinkPriceFeedV3Test is IPriceFeedV3Event, BaseSetup {
    uint256 internal _timestamp = 10000000;

    function setUp() public virtual override {
        BaseSetup.setUp();
        vm.warp(_timestamp);
        vm.mockCall(address(_testAggregator), abi.encodeWithSelector(_testAggregator.decimals.selector), abi.encode(8));
    }

    function test_getAggregator() public {
        assertEq(_chainlinkPriceFeedV3.getAggregator(), address(_testAggregator));
    }

    function test_getLastValidPrice_is_0_when_initialized() public {
        assertEq(_chainlinkPriceFeedV3.getLastValidPrice(), 0);
    }

    function test_getLastValidTime_is_0_when_initialized() public {
        assertEq(_chainlinkPriceFeedV3.getLastValidTime(), 0);
    }

    function test_decimals() public {
        assertEq(uint256(_chainlinkPriceFeedV3.decimals()), uint256(_testAggregator.decimals()));
    }

    function test_isTimedOut_is_false_when_initialized() public {
        assertEq(_chainlinkPriceFeedV3.isTimedOut(), false);
    }

    function test_isTimedOut() public {
        vm.warp(_TIMEOUT - 1);
        assertEq(_chainlinkPriceFeedV3.isTimedOut(), true);
    }

    function test_cachePrice_first_call_with_valid_price() public {
        uint256 price = 1000 * 1e8;
        uint256 roundId = 1;
        vm.mockCall(
            address(_testAggregator),
            abi.encodeWithSelector(_testAggregator.latestRoundData.selector),
            abi.encode(roundId, price, _timestamp, _timestamp, roundId)
        );

        vm.expectEmit(false, false, false, true, address(_chainlinkPriceFeedV3));
        emit PriceUpdated(price, _timestamp, FreezedReason.NotFreezed);
        assertEq(_chainlinkPriceFeedV3.cachePrice(), price);
        assertEq(_chainlinkPriceFeedV3.getLastValidPrice(), price);
    }

    function test_cachePrice_should_return__lastValidPrice() public {
        uint256 price1 = 1000 * 1e8;
        uint256 price2 = 2000 * 1e8;
        uint256 roundId = 1;
        vm.mockCall(
            address(_testAggregator),
            abi.encodeWithSelector(_testAggregator.latestRoundData.selector),
            abi.encode(roundId, price1, _timestamp, _timestamp, roundId)
        );
        _chainlinkPriceFeedV3.cachePrice();

        vm.mockCall(
            address(_testAggregator),
            abi.encodeWithSelector(_testAggregator.latestRoundData.selector),
            abi.encode(roundId, price2, _timestamp, _timestamp, roundId)
        );
        assertEq(_chainlinkPriceFeedV3.cachePrice(), price1);
    }

    function test_cachePrice_freezedReason_is_NoResponse() public {
        // cannot expect event here bc of foundry's bug
        // vm.expectEmit(false, false, false, false, address(_chainlinkPriceFeedV3Broken));
        // emit PriceUpdated(0, 0, FreezedReason.NoResponse);

        assertEq(_chainlinkPriceFeedV3Broken.cachePrice(), 0);
        assertEq(_chainlinkPriceFeedV3Broken.getLastValidTime(), 0);
        assertEq(int256(_chainlinkPriceFeedV3Broken.getFreezedReason()), int256(FreezedReason.NoResponse));
    }
}
