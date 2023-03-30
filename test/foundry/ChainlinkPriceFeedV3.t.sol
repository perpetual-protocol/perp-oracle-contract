pragma solidity 0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./Setup.sol";
import "../../contracts/interface/IChainlinkPriceFeedV3.sol";
import "../../contracts/test/TestAggregatorV3.sol";
import { CumulativeTwap } from "../../contracts/twap/CumulativeTwap.sol";

contract ChainlinkPriceFeedV3ConstructorTest is Setup {
    function test_CPF_ANC() public {
        vm.expectRevert(bytes("CPF_ANC"));
        _chainlinkPriceFeedV3 = new ChainlinkPriceFeedV3(TestAggregatorV3(0), _timeout, _twapInterval);
    }
}

contract ChainlinkPriceFeedV3Common is IChainlinkPriceFeedV3Event, Setup {
    using stdStorage for StdStorage;
    uint24 internal constant _ONE_HUNDRED_PERCENT_RATIO = 1e6;
    uint256 internal _timestamp = 10000000;
    uint256 internal _price = 1000 * 1e8;
    uint256 internal _prefilledPrice = _price - 5e8;
    uint256 internal _prefilledTimestamp = _timestamp - _twapInterval;
    uint256 internal _roundId = 5;

    function setUp() public virtual override {
        Setup.setUp();

        // we need Aggregator's decimals() function in the constructor of ChainlinkPriceFeedV3
        vm.mockCall(address(_testAggregator), abi.encodeWithSelector(_testAggregator.decimals.selector), abi.encode(8));
        _chainlinkPriceFeedV3 = _create_ChainlinkPriceFeedV3(_testAggregator);

        vm.warp(_timestamp);
        _mock_call_latestRoundData(_roundId, int256(_price), _timestamp);
    }

    function _chainlinkPriceFeedV3_prefill_observation_to_make_twap_calculatable() internal {
        // to make sure that twap price is calculatable
        uint256 roundId = _roundId - 1;

        _mock_call_latestRoundData(roundId, int256(_prefilledPrice), _prefilledTimestamp);
        vm.warp(_prefilledTimestamp);
        _chainlinkPriceFeedV3.update();

        vm.warp(_timestamp);
        _mock_call_latestRoundData(_roundId, int256(_price), _timestamp);
    }

    function _chainlinkPriceFeedV3_cacheTwap_and_assert_eq(uint256 interval, uint256 price) internal {
        _chainlinkPriceFeedV3.cacheTwap(interval);
        assertEq(_chainlinkPriceFeedV3.getPrice(interval), price);
    }

    function _getFreezedReason_and_assert_eq(ChainlinkPriceFeedV3 priceFeed, FreezedReason reason) internal {
        assertEq(uint256(priceFeed.getFreezedReason()), uint256(reason));
    }

    function _getLatestOrCachedPrice_and_assert_eq(
        ChainlinkPriceFeedV3 priceFeed,
        uint256 price,
        uint256 time
    ) internal {
        (uint256 p, uint256 t) = priceFeed.getLatestOrCachedPrice();
        assertEq(p, price);
        assertEq(t, time);
    }

    function _chainlinkPriceFeedV3Broken_cacheTwap_and_assert_eq(uint256 interval, uint256 price) internal {
        _chainlinkPriceFeedV3Broken.cacheTwap(interval);
        assertEq(_chainlinkPriceFeedV3Broken.getPrice(interval), price);
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

contract ChainlinkPriceFeedV3GetterTest is ChainlinkPriceFeedV3Common {
    function test_getAggregator() public {
        assertEq(_chainlinkPriceFeedV3.getAggregator(), address(_testAggregator));
    }

    function test_getTimeout() public {
        assertEq(_chainlinkPriceFeedV3.getTimeout(), _timeout);
    }

    function test_getLastValidPrice_is_0_when_initialized() public {
        assertEq(_chainlinkPriceFeedV3.getLastValidPrice(), 0);
    }

    function test_getLastValidTimestamp_is_0_when_initialized() public {
        assertEq(_chainlinkPriceFeedV3.getLastValidTimestamp(), 0);
    }

    function test_decimals() public {
        assertEq(uint256(_chainlinkPriceFeedV3.decimals()), uint256(_testAggregator.decimals()));
    }

    function test_isTimedOut_is_false_when_initialized() public {
        assertEq(_chainlinkPriceFeedV3.isTimedOut(), false);
    }

    function test_isTimedOut() public {
        _chainlinkPriceFeedV3_cacheTwap_and_assert_eq(0, _price);
        vm.warp(_timestamp + _timeout);
        assertEq(_chainlinkPriceFeedV3.isTimedOut(), false);
        vm.warp(_timestamp + _timeout + 1);
        assertEq(_chainlinkPriceFeedV3.isTimedOut(), true);
    }

    function test_isTimedOut_without_calling_update_and_with_chainlink_valid_data() public {
        _chainlinkPriceFeedV3_cacheTwap_and_assert_eq(0, _price);
        vm.warp(_timestamp + _timeout);
        assertEq(_chainlinkPriceFeedV3.isTimedOut(), false);
        // chain link get updated with a valid data but update doesn't get called
        _mock_call_latestRoundData(_roundId + 1, int256(_price + 1), _timestamp + _timeout);
        // time after the _lastValidTimestamp + timeout period
        vm.warp(_timestamp + _timeout + 1);
        assertEq(_chainlinkPriceFeedV3.isTimedOut(), false);
        // time after the last valid oracle price's updated time + timeout period
        vm.warp(_timestamp + _timeout + _timeout + 1);
        assertEq(_chainlinkPriceFeedV3.isTimedOut(), true);
    }

    function test_isTimedOut_without_calling_update_and_with_chainlink_invalid_data() public {
        _chainlinkPriceFeedV3_cacheTwap_and_assert_eq(0, _price);
        vm.warp(_timestamp + _timeout);
        assertEq(_chainlinkPriceFeedV3.isTimedOut(), false);
        // chain link get updated with an invalid data but update doesn't get called
        _mock_call_latestRoundData(_roundId + 1, int256(_price + 1), 0);
        vm.warp(_timestamp + _timeout + 1);
        // we should make sure that
        assertEq(_chainlinkPriceFeedV3.isTimedOut(), true);
    }

    function test_getLatestOrCachedPrice() public {
        (uint256 price, uint256 time) = _chainlinkPriceFeedV3.getLatestOrCachedPrice();
        assertEq(price, _price);
        assertEq(time, _timestamp);
    }
}

contract ChainlinkPriceFeedV3CacheTwapIntervalIsZeroTest is ChainlinkPriceFeedV3Common {
    using SafeMath for uint256;

    function test_cacheTwap_first_time_caching_with_valid_price() public {
        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(_price, _timestamp, FreezedReason.NotFreezed);

        _chainlinkPriceFeedV3_cacheTwap_and_assert_eq(0, _price);

        assertEq(_chainlinkPriceFeedV3.getLastValidPrice(), _price);
        assertEq(_chainlinkPriceFeedV3.getLastValidTimestamp(), _timestamp);
        _getFreezedReason_and_assert_eq(_chainlinkPriceFeedV3, FreezedReason.NotFreezed);
        _getLatestOrCachedPrice_and_assert_eq(_chainlinkPriceFeedV3, _price, _timestamp);
    }

    function test_getPrice_with_valid_price_after_a_second() public {
        uint256 latestPrice = _price + 1e8;
        _chainlinkPriceFeedV3.cacheTwap(0);
        vm.warp(_timestamp + 1);
        _mock_call_latestRoundData(_roundId + 1, int256(latestPrice), _timestamp + 1);
        assertEq(_chainlinkPriceFeedV3.getPrice(0), latestPrice);
        _getLatestOrCachedPrice_and_assert_eq(_chainlinkPriceFeedV3, latestPrice, _timestamp + 1);
    }

    function test_cacheTwap_wont_update_when_the_new_timestamp_is_the_same() public {
        _chainlinkPriceFeedV3_prefill_observation_to_make_twap_calculatable();
        _chainlinkPriceFeedV3.cacheTwap(0);

        uint256 t2 = _timestamp + 60;

        _mock_call_latestRoundData(_roundId, 2000 * 1e8, t2);
        vm.warp(t2);
        _chainlinkPriceFeedV3.cacheTwap(0);

        uint256 currentObservationIndexBefore = _chainlinkPriceFeedV3.currentObservationIndex();
        (uint256 priceBefore, , ) = _chainlinkPriceFeedV3.observations(currentObservationIndexBefore);
        uint256 twapBefore = _chainlinkPriceFeedV3.getPrice(_twapInterval);

        // giving a different price but the same old timestamp
        _mock_call_latestRoundData(_roundId, 2500 * 1e8, t2);
        vm.warp(t2 + 1);

        _chainlinkPriceFeedV3.cacheTwap(0);

        uint256 currentObservationIndexAfter = _chainlinkPriceFeedV3.currentObservationIndex();
        (uint256 priceAfter, , ) = _chainlinkPriceFeedV3.observations(currentObservationIndexAfter);
        uint256 twapAfter = _chainlinkPriceFeedV3.getPrice(_twapInterval);

        // latest price will not update
        assertEq(currentObservationIndexAfter, currentObservationIndexBefore);
        assertEq(priceAfter, priceBefore);
        _getLatestOrCachedPrice_and_assert_eq(_chainlinkPriceFeedV3, 2000 * 1e8, t2);

        // twap will be re-caulculated
        assertEq(twapAfter != twapBefore, true);
    }

    function test_cacheTwap_freezedReason_is_NoResponse() public {
        // note that it's _chainlinkPriceFeedV3Broken here, not _chainlinkPriceFeedV3
        vm.expectEmit(false, false, false, true, address(_chainlinkPriceFeedV3Broken));
        emit ChainlinkPriceUpdated(0, 0, FreezedReason.NoResponse);

        _chainlinkPriceFeedV3Broken_cacheTwap_and_assert_eq(0, 0);
        assertEq(_chainlinkPriceFeedV3Broken.getLastValidTimestamp(), 0);
        _getFreezedReason_and_assert_eq(_chainlinkPriceFeedV3Broken, FreezedReason.NoResponse);
        _getLatestOrCachedPrice_and_assert_eq(_chainlinkPriceFeedV3Broken, 0, 0);
    }

    function test_cacheTwap_freezedReason_is_IncorrectDecimals() public {
        vm.mockCall(address(_testAggregator), abi.encodeWithSelector(_testAggregator.decimals.selector), abi.encode(7));

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(0, 0, FreezedReason.IncorrectDecimals);
        _chainlinkPriceFeedV3_cacheTwap_and_assert_eq(0, 0);
        _getFreezedReason_and_assert_eq(_chainlinkPriceFeedV3, FreezedReason.IncorrectDecimals);
        _getLatestOrCachedPrice_and_assert_eq(_chainlinkPriceFeedV3, 0, 0);
    }

    function test_cacheTwap_freezedReason_is_NoRoundId() public {
        _mock_call_latestRoundData(0, int256(_price), _timestamp);

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(0, 0, FreezedReason.NoRoundId);
        _chainlinkPriceFeedV3.cacheTwap(0);

        _getFreezedReason_and_assert_eq(_chainlinkPriceFeedV3, FreezedReason.NoRoundId);
        _getLatestOrCachedPrice_and_assert_eq(_chainlinkPriceFeedV3, 0, 0);
    }

    function test_cacheTwap_freezedReason_is_InvalidTimestamp_with_zero_timestamp() public {
        // zero timestamp
        _mock_call_latestRoundData(_roundId, int256(_price), 0);

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(0, 0, FreezedReason.InvalidTimestamp);
        _chainlinkPriceFeedV3.cacheTwap(0);

        _getFreezedReason_and_assert_eq(_chainlinkPriceFeedV3, FreezedReason.InvalidTimestamp);
        _getLatestOrCachedPrice_and_assert_eq(_chainlinkPriceFeedV3, 0, 0);
    }

    function test_cacheTwap_freezedReason_is_InvalidTimestamp_with_future_timestamp() public {
        // future
        _mock_call_latestRoundData(_roundId, int256(_price), _timestamp + 1);

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(0, 0, FreezedReason.InvalidTimestamp);
        _chainlinkPriceFeedV3.cacheTwap(0);

        _getFreezedReason_and_assert_eq(_chainlinkPriceFeedV3, FreezedReason.InvalidTimestamp);
        _getLatestOrCachedPrice_and_assert_eq(_chainlinkPriceFeedV3, 0, 0);
    }

    function test_cacheTwap_freezedReason_is_InvalidTimestamp_with_past_timestamp() public {
        _chainlinkPriceFeedV3.cacheTwap(0);

        // < _lastValidTimestamp
        _mock_call_latestRoundData(_roundId, int256(_price), _timestamp - 1);
        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(_price, _timestamp, FreezedReason.InvalidTimestamp);
        _chainlinkPriceFeedV3.cacheTwap(_twapInterval);

        _getFreezedReason_and_assert_eq(_chainlinkPriceFeedV3, FreezedReason.InvalidTimestamp);
        _getLatestOrCachedPrice_and_assert_eq(_chainlinkPriceFeedV3, _price, _timestamp);
    }

    function test_cacheTwap_freezedReason_is_NonPositiveAnswer() public {
        _mock_call_latestRoundData(_roundId, -1, _timestamp);

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(0, 0, FreezedReason.NonPositiveAnswer);
        _chainlinkPriceFeedV3.cacheTwap(0);

        _getFreezedReason_and_assert_eq(_chainlinkPriceFeedV3, FreezedReason.NonPositiveAnswer);
        _getLatestOrCachedPrice_and_assert_eq(_chainlinkPriceFeedV3, 0, 0);
    }
}

contract ChainlinkPriceFeedV3CacheTwapIntervalIsNotZeroTest is ChainlinkPriceFeedV3Common {
    using SafeMath for uint256;

    function setUp() public virtual override {
        ChainlinkPriceFeedV3Common.setUp();

        _chainlinkPriceFeedV3_prefill_observation_to_make_twap_calculatable();
    }

    function test_cacheTwap_first_time_caching_with_valid_price() public {
        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(_price, _timestamp, FreezedReason.NotFreezed);

        _chainlinkPriceFeedV3_cacheTwap_and_assert_eq(_twapInterval, _prefilledPrice);
        _getFreezedReason_and_assert_eq(_chainlinkPriceFeedV3, FreezedReason.NotFreezed);
        _getLatestOrCachedPrice_and_assert_eq(_chainlinkPriceFeedV3, _price, _timestamp);
    }

    function test_getPrice_first_time_without_cacheTwap_yet() public {
        assertEq(_chainlinkPriceFeedV3.getPrice(_twapInterval), _prefilledPrice);
        _getLatestOrCachedPrice_and_assert_eq(_chainlinkPriceFeedV3, _price, _timestamp);
    }

    function test_getPrice_first_time_without_cacheTwap_yet_and_after_a_second() public {
        // make sure that even if there's no cache observation, CumulativeTwap won't calculate a TWAP
        vm.warp(_timestamp + 1);

        // (995 * 1799 + 1000 * 1) / 1800 = 995.00277777
        assertEq(_chainlinkPriceFeedV3.getPrice(_twapInterval), 995.00277777 * 1e8);
        _getLatestOrCachedPrice_and_assert_eq(_chainlinkPriceFeedV3, _price, _timestamp);
    }

    function test_getPrice_with_valid_price_after_a_second() public {
        _chainlinkPriceFeedV3.cacheTwap(_twapInterval);
        vm.warp(_timestamp + 1);
        // observation0 = 0 * 0 = 0
        // 0
        // observation1 = 995 * 1800 = 1,791,000
        // 1800

        // (995 * 1800 + 1000 * 1) / 1801 = 995.0027762354
        assertApproxEqAbs(_chainlinkPriceFeedV3.getPrice(_twapInterval), 995.00277 * 1e8, 1e6);
        _getLatestOrCachedPrice_and_assert_eq(_chainlinkPriceFeedV3, _price, _timestamp);
    }

    function test_getPrice_with_valid_price_after_several_seconds() public {
        _chainlinkPriceFeedV3.cacheTwap(_twapInterval);
        vm.warp(_timestamp + 1);
        _mock_call_latestRoundData(_roundId + 1, int256(_price + 1e8), _timestamp + 1);
        _chainlinkPriceFeedV3.cacheTwap(_twapInterval);
        vm.warp(_timestamp + 2);
        // (995 * 1800 + 1000 * 1 + 1001 * 1) / 1802 = 995.0061043285
        assertApproxEqAbs(_chainlinkPriceFeedV3.getPrice(_twapInterval), 995.0061 * 1e8, 1e6);
        _getLatestOrCachedPrice_and_assert_eq(_chainlinkPriceFeedV3, _price + 1e8, _timestamp + 1);
    }

    function test_getPrice_with_valid_price_after_several_seconds_without_cacheTwap() public {
        _chainlinkPriceFeedV3.cacheTwap(_twapInterval);
        vm.warp(_timestamp + 2);
        _mock_call_latestRoundData(_roundId + 1, int256(_price + 1e8), _timestamp + 1);
        // (995 * 1800 + 1000 * 1 + 1001 * 1) / 1802 = 995.0061043285
        assertApproxEqAbs(_chainlinkPriceFeedV3.getPrice(_twapInterval), 995.0061 * 1e8, 1e6);
        _getLatestOrCachedPrice_and_assert_eq(_chainlinkPriceFeedV3, _price + 1e8, _timestamp + 1);
    }

    function test_cacheTwap_wont_update_when_the_new_timestamp_is_the_same() public {
        uint256 t2 = _timestamp + 60;

        _mock_call_latestRoundData(_roundId, 2000 * 1e8, t2);
        vm.warp(t2);
        _chainlinkPriceFeedV3.cacheTwap(_twapInterval);

        uint256 currentObservationIndexBefore = _chainlinkPriceFeedV3.currentObservationIndex();
        (uint256 priceBefore, , ) = _chainlinkPriceFeedV3.observations(currentObservationIndexBefore);
        uint256 twapBefore = _chainlinkPriceFeedV3.getPrice(_twapInterval);

        // giving a different price but the same old timestamp
        _mock_call_latestRoundData(_roundId, 2500 * 1e8, t2);
        vm.warp(t2 + 1);

        // will update _cachedTwap
        _chainlinkPriceFeedV3.cacheTwap(_twapInterval);

        uint256 currentObservationIndexAfter = _chainlinkPriceFeedV3.currentObservationIndex();
        (uint256 priceAfter, , ) = _chainlinkPriceFeedV3.observations(currentObservationIndexAfter);
        uint256 twapAfter = _chainlinkPriceFeedV3.getPrice(_twapInterval);
        _getLatestOrCachedPrice_and_assert_eq(_chainlinkPriceFeedV3, 2000 * 1e8, t2);

        // latest price will not update
        assertEq(currentObservationIndexAfter, currentObservationIndexBefore);
        assertEq(priceAfter, priceBefore);

        assertEq(twapAfter != twapBefore, true);
    }

    function test_cacheTwap_freezedReason_is_NoResponse() public {
        // note that it's _chainlinkPriceFeedV3Broken here, not _chainlinkPriceFeedV3
        vm.expectEmit(false, false, false, true, address(_chainlinkPriceFeedV3Broken));
        emit ChainlinkPriceUpdated(0, 0, FreezedReason.NoResponse);

        _chainlinkPriceFeedV3Broken_cacheTwap_and_assert_eq(_twapInterval, 0);
        assertEq(_chainlinkPriceFeedV3Broken.getLastValidTimestamp(), 0);
        _getFreezedReason_and_assert_eq(_chainlinkPriceFeedV3Broken, FreezedReason.NoResponse);
        _getLatestOrCachedPrice_and_assert_eq(_chainlinkPriceFeedV3, _price, _timestamp);
    }

    function test_cacheTwap_freezedReason_is_IncorrectDecimals() public {
        vm.mockCall(address(_testAggregator), abi.encodeWithSelector(_testAggregator.decimals.selector), abi.encode(7));

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(_prefilledPrice, _prefilledTimestamp, FreezedReason.IncorrectDecimals);
        _chainlinkPriceFeedV3.cacheTwap(_twapInterval);
        _getFreezedReason_and_assert_eq(_chainlinkPriceFeedV3, FreezedReason.IncorrectDecimals);
        _getLatestOrCachedPrice_and_assert_eq(_chainlinkPriceFeedV3, _prefilledPrice, _prefilledTimestamp);
    }

    function test_cacheTwap_freezedReason_is_NoRoundId() public {
        _mock_call_latestRoundData(0, int256(_price), _timestamp);

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(_prefilledPrice, _prefilledTimestamp, FreezedReason.NoRoundId);
        _chainlinkPriceFeedV3.cacheTwap(_twapInterval);
        _getFreezedReason_and_assert_eq(_chainlinkPriceFeedV3, FreezedReason.NoRoundId);
        _getLatestOrCachedPrice_and_assert_eq(_chainlinkPriceFeedV3, _prefilledPrice, _prefilledTimestamp);
    }

    function test_cacheTwap_freezedReason_is_InvalidTimestamp_with_zero_timestamp() public {
        // zero timestamp
        _mock_call_latestRoundData(_roundId, int256(_price), 0);

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(_prefilledPrice, _prefilledTimestamp, FreezedReason.InvalidTimestamp);
        _chainlinkPriceFeedV3.cacheTwap(_twapInterval);
        _getFreezedReason_and_assert_eq(_chainlinkPriceFeedV3, FreezedReason.InvalidTimestamp);
        _getLatestOrCachedPrice_and_assert_eq(_chainlinkPriceFeedV3, _prefilledPrice, _prefilledTimestamp);
    }

    function test_cacheTwap_freezedReason_is_InvalidTimestamp_with_future_timestamp() public {
        // future
        _mock_call_latestRoundData(_roundId, int256(_price), _timestamp + 1);

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(_prefilledPrice, _prefilledTimestamp, FreezedReason.InvalidTimestamp);
        _chainlinkPriceFeedV3.cacheTwap(_twapInterval);
        _getFreezedReason_and_assert_eq(_chainlinkPriceFeedV3, FreezedReason.InvalidTimestamp);
        _getLatestOrCachedPrice_and_assert_eq(_chainlinkPriceFeedV3, _prefilledPrice, _prefilledTimestamp);
    }

    function test_cacheTwap_freezedReason_is_InvalidTimestamp_with_past_timestamp() public {
        _chainlinkPriceFeedV3.cacheTwap(0);

        // < _lastValidTimestamp
        _mock_call_latestRoundData(_roundId, int256(_price), _timestamp - 1);
        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(_price, _timestamp, FreezedReason.InvalidTimestamp);
        _chainlinkPriceFeedV3.cacheTwap(_twapInterval);

        _getFreezedReason_and_assert_eq(_chainlinkPriceFeedV3, FreezedReason.InvalidTimestamp);
        _getLatestOrCachedPrice_and_assert_eq(_chainlinkPriceFeedV3, _price, _timestamp);
    }

    function test_cacheTwap_freezedReason_is_NonPositiveAnswer() public {
        _mock_call_latestRoundData(_roundId, -1, _timestamp);

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(_prefilledPrice, _prefilledTimestamp, FreezedReason.NonPositiveAnswer);
        _chainlinkPriceFeedV3.cacheTwap(_twapInterval);

        _getFreezedReason_and_assert_eq(_chainlinkPriceFeedV3, FreezedReason.NonPositiveAnswer);
        _getLatestOrCachedPrice_and_assert_eq(_chainlinkPriceFeedV3, _prefilledPrice, _prefilledTimestamp);
    }
}

contract ChainlinkPriceFeedV3CacheTwapIntegrationTest is ChainlinkPriceFeedV3Common {
    using SafeMath for uint256;

    function test_integration_of_ChainlinkPriceFeedV3_CachedTwap_and_CumulativeTwap() public {
        _chainlinkPriceFeedV3_prefill_observation_to_make_twap_calculatable();

        _chainlinkPriceFeedV3.cacheTwap(_twapInterval);

        int256 price1 = 960 * 1e8;
        uint256 timestamp1 = _timestamp + 10;
        _mock_call_latestRoundData(_roundId + 1, price1, timestamp1);
        vm.warp(timestamp1);
        // (995*1790+1000*10)/1800=995.0276243094
        assertEq(_chainlinkPriceFeedV3.getPrice(_twapInterval), 995.02777777 * 1e8);
        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(uint256(price1), timestamp1, FreezedReason.NotFreezed);
        _chainlinkPriceFeedV3_cacheTwap_and_assert_eq(_twapInterval, 995.02777777 * 1e8);
        _getFreezedReason_and_assert_eq(_chainlinkPriceFeedV3, FreezedReason.NotFreezed);
        _getLatestOrCachedPrice_and_assert_eq(_chainlinkPriceFeedV3, uint256(price1), timestamp1);

        int256 price2 = 920 * 1e8;
        uint256 timestamp2 = timestamp1 + 20;
        _mock_call_latestRoundData(_roundId + 2, price2, timestamp2);
        vm.warp(timestamp2);
        // check interval = 0 is still cacheable
        // (995*1770+1000*10+960*20)/1800=994.6448087432
        assertEq(_chainlinkPriceFeedV3.getPrice(_twapInterval), 994.63888888 * 1e8);
        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(uint256(price2), timestamp2, FreezedReason.NotFreezed);
        _chainlinkPriceFeedV3_cacheTwap_and_assert_eq(0, uint256(price2));
        _getFreezedReason_and_assert_eq(_chainlinkPriceFeedV3, FreezedReason.NotFreezed);
        // and twap still calculable as the same as above one
        assertEq(_chainlinkPriceFeedV3.getPrice(_twapInterval), 994.63888888 * 1e8);
        vm.warp(timestamp2 + 10);
        // twap (by using latest price) = (995 * 1760 + 1000 * 10 + 960 * 20 + 920 * 10) / 1800 = 994.2222222222
        assertEq(_chainlinkPriceFeedV3.getPrice(_twapInterval), 994.22222222 * 1e8);
        _getLatestOrCachedPrice_and_assert_eq(_chainlinkPriceFeedV3, uint256(price2), timestamp2);

        int256 price3 = 900 * 1e8;
        uint256 timestamp3 = timestamp2 + 20;
        _mock_call_latestRoundData(_roundId + 3, price3, timestamp3);
        vm.warp(timestamp3);
        // twap = (995 * 1750 + 1000 * 10 + 960 * 20 + 920 * 20) / 1800 = 993.80555555
        assertEq(_chainlinkPriceFeedV3.getPrice(_twapInterval), 993.80555555 * 1e8);
        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(uint256(price3), timestamp3, FreezedReason.NotFreezed);
        _chainlinkPriceFeedV3_cacheTwap_and_assert_eq(_twapInterval, 993.80555555 * 1e8);
        _getFreezedReason_and_assert_eq(_chainlinkPriceFeedV3, FreezedReason.NotFreezed);
        _getLatestOrCachedPrice_and_assert_eq(_chainlinkPriceFeedV3, uint256(price3), timestamp3);

        uint256 timestamp4 = timestamp3 + _timeout;
        vm.warp(timestamp4);
        assertEq(_chainlinkPriceFeedV3.isTimedOut(), false);
        _getLatestOrCachedPrice_and_assert_eq(_chainlinkPriceFeedV3, uint256(price3), timestamp3);

        uint256 timestamp5 = timestamp4 + 1;
        vm.warp(timestamp5);
        assertEq(_chainlinkPriceFeedV3.isTimedOut(), true);
        _getLatestOrCachedPrice_and_assert_eq(_chainlinkPriceFeedV3, uint256(price3), timestamp3);
    }
}

contract ChainlinkPriceFeedV3UpdateTest is ChainlinkPriceFeedV3Common {
    using SafeMath for uint256;

    function test_update_first_time_caching_with_valid_price() public {
        // init price: 1000 * 1e8
        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(_price, _timestamp, FreezedReason.NotFreezed);

        _chainlinkPriceFeedV3.update();

        _assert_LastValidPrice_LastValidTimestamp_and_FreezedReason(
            _chainlinkPriceFeedV3,
            _price,
            _timestamp,
            FreezedReason.NotFreezed
        );

        vm.warp(_timestamp + 1);
        assertEq(_chainlinkPriceFeedV3.getPrice(_twapInterval), _price);
    }

    function test_update_when_the_diff_price_and_diff_timestamp() public {
        // init price: 1000 * 1e8
        _chainlinkPriceFeedV3.update();

        // second update: diff price and diff timestamp
        //           t1      t2     now
        //      -----+--------+-------+------
        //              1200s    600s
        // price:   1000     1010

        uint256 t2 = _timestamp + 1200;
        uint256 p2 = _price + 10 * 1e8;
        _mock_call_latestRoundData(_roundId + 1, int256(p2), t2);
        vm.warp(t2);
        _chainlinkPriceFeedV3.update();

        _assert_LastValidPrice_LastValidTimestamp_and_FreezedReason(
            _chainlinkPriceFeedV3,
            p2,
            t2,
            FreezedReason.NotFreezed
        );

        vm.warp(t2 + 600);

        // (1000*1200 + 1010*600) / 1800 = 1003.33333333
        assertEq(_chainlinkPriceFeedV3.getPrice(_twapInterval), 1003.33333333 * 1e8);
    }

    function test_update_when_the_same_price_and_diff_timestamp() public {
        // init price: 1000 * 1e8
        _chainlinkPriceFeedV3.update();

        // second update: same price and diff timestamp
        //           t1      t2     now
        //      -----+--------+-------+------
        //              1200s    600s
        // price:   1000     1000
        uint256 t2 = _timestamp + 1200;
        _mock_call_latestRoundData(_roundId + 1, int256(_price), t2);
        vm.warp(t2);
        _chainlinkPriceFeedV3.update();

        _assert_LastValidPrice_LastValidTimestamp_and_FreezedReason(
            _chainlinkPriceFeedV3,
            _price,
            t2,
            FreezedReason.NotFreezed
        );

        vm.warp(t2 + 600);
        assertEq(_chainlinkPriceFeedV3.getPrice(_twapInterval), _price);
    }

    function test_revert_update_when_same_price_and_same_timestamp() public {
        // init price: 1000 * 1e8
        _chainlinkPriceFeedV3.update();

        // second update: same price and same timestamp
        vm.warp(_timestamp + 1200);
        vm.expectRevert(bytes("CPF_NU"));
        _chainlinkPriceFeedV3.update();
    }

    function test_revert_update_when_the_diff_price_and_same_timestamp() public {
        // init price: 1000 * 1e8
        _chainlinkPriceFeedV3.update();

        // second update: diff price and same timestamp
        int256 p2 = int256(_price) + 10 * 1e8;
        _mock_call_latestRoundData(_roundId + 1, p2, _timestamp);
        vm.warp(_timestamp + 1200);
        vm.expectRevert(bytes("CPF_NU"));
        _chainlinkPriceFeedV3.update();
    }

    function test_revert_update_freezedReason_is_NoResponse() public {
        // note that it's _chainlinkPriceFeedV3Broken here, not _chainlinkPriceFeedV3
        vm.expectRevert(bytes("CPF_NU"));
        _chainlinkPriceFeedV3Broken.update();

        _assert_LastValidPrice_LastValidTimestamp_and_FreezedReason(
            _chainlinkPriceFeedV3Broken,
            0,
            0,
            FreezedReason.NoResponse
        );
    }

    function test_revert_update_freezedReason_is_IncorrectDecimals() public {
        vm.mockCall(address(_testAggregator), abi.encodeWithSelector(_testAggregator.decimals.selector), abi.encode(7));

        vm.expectRevert(bytes("CPF_NU"));
        _chainlinkPriceFeedV3.update();

        _assert_LastValidPrice_LastValidTimestamp_and_FreezedReason(
            _chainlinkPriceFeedV3,
            0,
            0,
            FreezedReason.IncorrectDecimals
        );
    }

    function test_revert_update_freezedReason_is_NoRoundId() public {
        _mock_call_latestRoundData(0, int256(_price), _timestamp);

        vm.expectRevert(bytes("CPF_NU"));
        _chainlinkPriceFeedV3.update();

        _assert_LastValidPrice_LastValidTimestamp_and_FreezedReason(
            _chainlinkPriceFeedV3,
            0,
            0,
            FreezedReason.NoRoundId
        );
    }

    function test_revert_update_freezedReason_is_InvalidTimestamp_with_zero_timestamp() public {
        // zero timestamp
        _mock_call_latestRoundData(_roundId, int256(_price), 0);

        vm.expectRevert(bytes("CPF_NU"));
        _chainlinkPriceFeedV3.update();

        _assert_LastValidPrice_LastValidTimestamp_and_FreezedReason(
            _chainlinkPriceFeedV3,
            0,
            0,
            FreezedReason.InvalidTimestamp
        );
    }

    function test_revert_update_freezedReason_is_InvalidTimestamp_with_future_timestamp() public {
        // future
        _mock_call_latestRoundData(_roundId, int256(_price), _timestamp + 1);

        vm.expectRevert(bytes("CPF_NU"));
        _chainlinkPriceFeedV3.update();

        _assert_LastValidPrice_LastValidTimestamp_and_FreezedReason(
            _chainlinkPriceFeedV3,
            0,
            0,
            FreezedReason.InvalidTimestamp
        );
    }

    function test_revert_update_freezedReason_is_InvalidTimestamp_with_past_timestamp() public {
        _chainlinkPriceFeedV3.update();

        // < _lastValidTimestamp
        _mock_call_latestRoundData(_roundId + 1, int256(_price), _timestamp - 1);

        vm.expectRevert(bytes("CPF_NU"));
        _chainlinkPriceFeedV3.update();

        _assert_LastValidPrice_LastValidTimestamp_and_FreezedReason(
            _chainlinkPriceFeedV3,
            _price,
            _timestamp,
            FreezedReason.InvalidTimestamp
        );
    }

    function test_revert_update_freezedReason_is_NonPositiveAnswer() public {
        _mock_call_latestRoundData(_roundId + 1, -1, _timestamp);

        vm.expectRevert(bytes("CPF_NU"));
        _chainlinkPriceFeedV3.update();

        _assert_LastValidPrice_LastValidTimestamp_and_FreezedReason(
            _chainlinkPriceFeedV3,
            0,
            0,
            FreezedReason.NonPositiveAnswer
        );
    }

    function _assert_LastValidPrice_LastValidTimestamp_and_FreezedReason(
        ChainlinkPriceFeedV3 priceFeed,
        uint256 price,
        uint256 timestamp,
        FreezedReason reason
    ) internal {
        assertEq(priceFeed.getLastValidPrice(), price);
        assertEq(priceFeed.getLastValidTimestamp(), timestamp);
        _getFreezedReason_and_assert_eq(priceFeed, reason);
        _getLatestOrCachedPrice_and_assert_eq(priceFeed, price, timestamp);
    }
}
