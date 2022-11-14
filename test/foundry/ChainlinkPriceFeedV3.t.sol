pragma solidity 0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./Setup.sol";
import "../../contracts/interface/IPriceFeedV3.sol";
import "./interface/ICumulativeEvent.sol";

contract ChainlinkPriceFeedV3Test is IPriceFeedV3Event, ICumulativeEvent, BaseSetup {
    using SafeMath for uint256;

    uint24 internal constant _ONE_HUNDRED_PERCENT_RATIO = 1e6;
    uint256 internal _timestamp = 10000000;
    uint256 internal _price = 1000 * 1e8;
    uint256 internal _roundId = 1;
    uint256 internal _timestampAfterOutlierCoolDownPeriod = _timestamp + _outlierCoolDownPeriod + 1;

    function setUp() public virtual override {
        BaseSetup.setUp();
        vm.warp(_timestamp);
        vm.mockCall(address(_testAggregator), abi.encodeWithSelector(_testAggregator.decimals.selector), abi.encode(8));

        _mock_call_latestRoundData(_roundId, int256(_price), _timestamp);
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
        vm.warp(_timeout - 1);
        assertEq(_chainlinkPriceFeedV3.isTimedOut(), true);
    }

    function test_cacheTwap_first_time_caching_with_valid_price() public {
        // TODO: when price is zero interval, there's no event
        // _expect_emit_event_from_ChainlinkPriceFeedV3();
        // emit PriceUpdated(_price, _timestamp, 1);

        assertEq(_chainlinkPriceFeedV3.cacheTwap(0), _price);
        assertEq(_chainlinkPriceFeedV3.getLastValidPrice(), _price);
        assertEq(_chainlinkPriceFeedV3.getLastValidTime(), _timestamp);
    }

    function test_cacheTwap_wont_update_when_the_new_timestamp_is_the_same() public {
        _chainlinkPriceFeedV3.cacheTwap(0);

        // giving a different price but the same timestamp
        _mock_call_latestRoundData(_roundId, 2000 * 1e8, _timestamp);

        // price won't get updated; still the existing _lastValidPrice
        assertEq(_chainlinkPriceFeedV3.cacheTwap(0), _price);
    }

    function test_cacheTwap_freezedReason_is_NoResponse() public {
        // cannot expect event here bc of foundry's bug
        // vm.expectEmit(false, false, false, false, address(_chainlinkPriceFeedV3Broken));
        // emit PriceUpdated(0, 0, FreezedReason.NoResponse);

        assertEq(_chainlinkPriceFeedV3Broken.cacheTwap(0), 0);
        assertEq(_chainlinkPriceFeedV3Broken.getLastValidTime(), 0);
        assertEq(int256(_chainlinkPriceFeedV3Broken.getFreezedReason()), int256(FreezedReason.NoResponse));
    }

    function test_cacheTwap_freezedReason_is_IncorrectDecimals() public {
        vm.mockCall(address(_testAggregator), abi.encodeWithSelector(_testAggregator.decimals.selector), abi.encode(7));

        // TODO: when price is zero interval, there's no event
        // _expect_emit_event_from_ChainlinkPriceFeedV3();
        // emit PriceUpdated(0, 0, 1);

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit Freezed(FreezedReason.IncorrectDecimals);
        _chainlinkPriceFeedV3.cacheTwap(0);
    }

    function test_cacheTwap_freezedReason_is_NoRoundId() public {
        _mock_call_latestRoundData(0, int256(_price), _timestamp);

        // TODO: when price is zero interval, there's no event
        // _expect_emit_event_from_ChainlinkPriceFeedV3();
        // emit PriceUpdated(0, 0, 1);
        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit Freezed(FreezedReason.NoRoundId);
        _chainlinkPriceFeedV3.cacheTwap(0);
    }

    function test_cacheTwap_freezedReason_is_InvalidTimestamp_with_zero_timestamp() public {
        // zero timestamp
        _mock_call_latestRoundData(_roundId, int256(_price), 0);

        // TODO: when price is zero interval, there's no event
        // _expect_emit_event_from_ChainlinkPriceFeedV3();
        // emit PriceUpdated(0, 0, 1);
        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit Freezed(FreezedReason.InvalidTimestamp);
        _chainlinkPriceFeedV3.cacheTwap(0);
    }

    function test_cacheTwap_freezedReason_is_InvalidTimestamp_with_future_timestamp() public {
        // future
        _mock_call_latestRoundData(_roundId, int256(_price), _timestamp + 1);

        // TODO: when price is zero interval, there's no event
        // _expect_emit_event_from_ChainlinkPriceFeedV3();
        // emit PriceUpdated(0, 0, 1);
        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit Freezed(FreezedReason.InvalidTimestamp);
        _chainlinkPriceFeedV3.cacheTwap(0);
    }

    function test_cacheTwap_freezedReason_is_InvalidTimestamp_with_past_timestamp() public {
        _chainlinkPriceFeedV3.cacheTwap(0);

        // < _lastValidTime
        _mock_call_latestRoundData(_roundId, int256(_price), _timestamp - 1);

        // TODO: when price is zero interval, there's no event
        // _expect_emit_event_from_ChainlinkPriceFeedV3();
        // emit PriceUpdated(_price, _timestamp, 2);
        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit Freezed(FreezedReason.InvalidTimestamp);
        _chainlinkPriceFeedV3.cacheTwap(0);
    }

    function test_cacheTwap_freezedReason_is_NonPositiveAnswer() public {
        _mock_call_latestRoundData(_roundId, -1, _timestamp);

        // TODO: when price is zero interval, there's no event
        // _expect_emit_event_from_ChainlinkPriceFeedV3();
        // emit PriceUpdated(0, 0, 1);
        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit Freezed(FreezedReason.NonPositiveAnswer);
        _chainlinkPriceFeedV3.cacheTwap(0);
    }

    function test_cacheTwap_freezedReason_is_AnswerIsOutlier_outlier_larger_than__lastValidPrice() public {
        _chainlinkPriceFeedV3.cacheTwap(0);

        int256 outlier = 2000 * 1e8;
        _mock_call_latestRoundData(_roundId + 1, outlier, _timestampAfterOutlierCoolDownPeriod);
        vm.warp(_timestampAfterOutlierCoolDownPeriod);

        uint256 maxDeviatedPrice =
            _price.mul(_ONE_HUNDRED_PERCENT_RATIO + _maxOutlierDeviationRatio).div(_ONE_HUNDRED_PERCENT_RATIO);
        // TODO: when price is zero interval, there's no event
        // _expect_emit_event_from_ChainlinkPriceFeedV3();
        // emit PriceUpdated(maxDeviatedPrice, _timestampAfterOutlierCoolDownPeriod, 2);
        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit Freezed(FreezedReason.AnswerIsOutlier);
        _chainlinkPriceFeedV3.cacheTwap(0);
    }

    function test_cacheTwap_freezedReason_is_AnswerIsOutlier_outlier_smaller_than__lastValidPrice() public {
        _chainlinkPriceFeedV3.cacheTwap(0);

        int256 outlier = 500 * 1e8;
        _mock_call_latestRoundData(_roundId + 1, outlier, _timestampAfterOutlierCoolDownPeriod);
        vm.warp(_timestampAfterOutlierCoolDownPeriod);

        uint256 maxDeviatedPrice =
            _price.mul(_ONE_HUNDRED_PERCENT_RATIO - _maxOutlierDeviationRatio).div(_ONE_HUNDRED_PERCENT_RATIO);
        // TODO: when price is zero interval, there's no event
        // _expect_emit_event_from_ChainlinkPriceFeedV3();
        // emit PriceUpdated(maxDeviatedPrice, _timestampAfterOutlierCoolDownPeriod, 2);
        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit Freezed(FreezedReason.AnswerIsOutlier);
        _chainlinkPriceFeedV3.cacheTwap(0);
    }

    function test_cacheTwap_freezedReason_is_AnswerIsOutlier_but_before__outlierCoolDownPeriod() public {
        _chainlinkPriceFeedV3.cacheTwap(0);

        uint256 timestampBeforeOutlierCoolDownPeriod = _timestampAfterOutlierCoolDownPeriod - 2;
        _mock_call_latestRoundData(_roundId + 1, 500 * 1e8, timestampBeforeOutlierCoolDownPeriod);
        vm.warp(timestampBeforeOutlierCoolDownPeriod);

        // TODO: when price is zero interval, there's no event
        // _expect_emit_event_from_ChainlinkPriceFeedV3();
        // FreezedReason will be emitted while price & timestamp remain as _lastValidPrice & _lastValidTime
        // emit PriceUpdated(_price, _timestamp, 2);
        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit Freezed(FreezedReason.AnswerIsOutlier);
        _chainlinkPriceFeedV3.cacheTwap(0);
    }

    function test_cacheTwap_no_outlier_but_timestamp_is_after__outlierCoolDownPeriod() public {
        _chainlinkPriceFeedV3.cacheTwap(0);

        int256 price = 950 * 1e8;
        _mock_call_latestRoundData(_roundId + 1, price, _timestampAfterOutlierCoolDownPeriod);
        vm.warp(_timestampAfterOutlierCoolDownPeriod);

        // TODO: when price is zero interval, there's no event
        // _expect_emit_event_from_ChainlinkPriceFeedV3();
        // emit PriceUpdated(uint256(price), _timestampAfterOutlierCoolDownPeriod, 2);
        _chainlinkPriceFeedV3.cacheTwap(0);
    }

    function _mock_call_latestRoundData(
        uint256 roundId,
        int256 answer,
        uint256 timestamp
    ) internal {
        vm.mockCall(
            address(_testAggregator),
            abi.encodeWithSelector(_testAggregator.latestRoundData.selector),
            abi.encode(roundId, answer, timestamp, timestamp, roundId)
        );
    }

    function _expect_emit_event_from_ChainlinkPriceFeedV3() internal {
        vm.expectEmit(false, false, false, true, address(_chainlinkPriceFeedV3));
    }
}
