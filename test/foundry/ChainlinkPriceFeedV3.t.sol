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
        assertEq(_chainlinkPriceFeedV3.getCachedTwap(interval), price);
    }

    function _getFreezedReason_and_assert_eq(ChainlinkPriceFeedV3 priceFeed, FreezedReason reason) internal {
        assertEq(uint256(priceFeed.getFreezedReason()), uint256(reason));
    }

    function _chainlinkPriceFeedV3Broken_cacheTwap_and_assert_eq(uint256 interval, uint256 price) internal {
        _chainlinkPriceFeedV3Broken.cacheTwap(interval);
        assertEq(_chainlinkPriceFeedV3Broken.getCachedTwap(interval), price);
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
}

// this test also covers update() since it's essentially cacheTwap(0)
contract ChainlinkPriceFeedV3CacheTwapIntervalIsZeroTest is ChainlinkPriceFeedV3Common {
    using SafeMath for uint256;

    function test_cacheTwap_first_time_caching_with_valid_price() public {
        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(_price, _timestamp, FreezedReason.NotFreezed);

        _chainlinkPriceFeedV3_cacheTwap_and_assert_eq(0, _price);

        assertEq(_chainlinkPriceFeedV3.getLastValidPrice(), _price);
        assertEq(_chainlinkPriceFeedV3.getLastValidTimestamp(), _timestamp);
        _getFreezedReason_and_assert_eq(_chainlinkPriceFeedV3, FreezedReason.NotFreezed);
    }

    function test_getCachedTwap_with_valid_price_after_a_second() public {
        uint256 latestPrice = _price + 1e8;
        _chainlinkPriceFeedV3.cacheTwap(0);
        vm.warp(_timestamp + 1);
        _mock_call_latestRoundData(_roundId + 1, int256(latestPrice), _timestamp + 1);
        assertEq(_chainlinkPriceFeedV3.getCachedTwap(0), latestPrice);
    }

    function test_cacheTwap_wont_update_when_the_new_timestamp_is_the_same() public {
        _chainlinkPriceFeedV3.cacheTwap(0);

        uint256 t2 = _timestamp + 60;

        _mock_call_latestRoundData(_roundId, 2000 * 1e8, t2);
        vm.warp(t2);
        _chainlinkPriceFeedV3.cacheTwap(0);

        uint256 currentObservationIndexBefore = _chainlinkPriceFeedV3.currentObservationIndex();
        (uint256 priceBefore, , ) = _chainlinkPriceFeedV3.observations(currentObservationIndexBefore);
        uint256 twapBefore = _chainlinkPriceFeedV3.getCachedTwap(_twapInterval);

        // giving a different price but the same old timestamp
        _mock_call_latestRoundData(_roundId, 2500 * 1e8, t2);
        vm.warp(t2 + 1);

        _chainlinkPriceFeedV3.cacheTwap(0);

        uint256 currentObservationIndexAfter = _chainlinkPriceFeedV3.currentObservationIndex();
        (uint256 priceAfter, , ) = _chainlinkPriceFeedV3.observations(currentObservationIndexAfter);
        uint256 twapAfter = _chainlinkPriceFeedV3.getCachedTwap(_twapInterval);

        // latest price will not update
        assertEq(currentObservationIndexAfter, currentObservationIndexBefore);
        assertEq(priceAfter, priceBefore);

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
    }

    function test_cacheTwap_freezedReason_is_IncorrectDecimals() public {
        vm.mockCall(address(_testAggregator), abi.encodeWithSelector(_testAggregator.decimals.selector), abi.encode(7));

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(0, 0, FreezedReason.IncorrectDecimals);
        _chainlinkPriceFeedV3_cacheTwap_and_assert_eq(0, 0);
        _getFreezedReason_and_assert_eq(_chainlinkPriceFeedV3, FreezedReason.IncorrectDecimals);
    }

    function test_cacheTwap_freezedReason_is_NoRoundId() public {
        _mock_call_latestRoundData(0, int256(_price), _timestamp);

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(0, 0, FreezedReason.NoRoundId);
        _chainlinkPriceFeedV3.cacheTwap(0);

        _getFreezedReason_and_assert_eq(_chainlinkPriceFeedV3, FreezedReason.NoRoundId);
    }

    function test_cacheTwap_freezedReason_is_InvalidTimestamp_with_zero_timestamp() public {
        // zero timestamp
        _mock_call_latestRoundData(_roundId, int256(_price), 0);

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(0, 0, FreezedReason.InvalidTimestamp);
        _chainlinkPriceFeedV3.cacheTwap(0);

        _getFreezedReason_and_assert_eq(_chainlinkPriceFeedV3, FreezedReason.InvalidTimestamp);
    }

    function test_cacheTwap_freezedReason_is_InvalidTimestamp_with_future_timestamp() public {
        // future
        _mock_call_latestRoundData(_roundId, int256(_price), _timestamp + 1);

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(0, 0, FreezedReason.InvalidTimestamp);
        _chainlinkPriceFeedV3.cacheTwap(0);

        _getFreezedReason_and_assert_eq(_chainlinkPriceFeedV3, FreezedReason.InvalidTimestamp);
    }

    function test_cacheTwap_freezedReason_is_InvalidTimestamp_with_past_timestamp() public {
        _chainlinkPriceFeedV3.cacheTwap(0);

        // < _lastValidTimestamp
        _mock_call_latestRoundData(_roundId, int256(_price), _timestamp - 1);
        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(_price, _timestamp, FreezedReason.InvalidTimestamp);
        _chainlinkPriceFeedV3.cacheTwap(_twapInterval);

        _getFreezedReason_and_assert_eq(_chainlinkPriceFeedV3, FreezedReason.InvalidTimestamp);
    }

    function test_cacheTwap_freezedReason_is_NonPositiveAnswer() public {
        _mock_call_latestRoundData(_roundId, -1, _timestamp);

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(0, 0, FreezedReason.NonPositiveAnswer);
        _chainlinkPriceFeedV3.cacheTwap(0);

        _getFreezedReason_and_assert_eq(_chainlinkPriceFeedV3, FreezedReason.NonPositiveAnswer);
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
    }

    function test_getCachedTwap_first_time_without_cacheTwap_yet() public {
        assertEq(_chainlinkPriceFeedV3.getCachedTwap(_twapInterval), _prefilledPrice);
    }

    function test_getCachedTwap_first_time_without_cacheTwap_yet_and_after_a_second() public {
        // make sure that even if there's no cache observation, CumulativeTwap won't calculate a TWAP
        vm.warp(_timestamp + 1);

        // (995 * 1799 + 1000 * 1) / 1800 = 995.00277777
        assertEq(_chainlinkPriceFeedV3.getCachedTwap(_twapInterval), 995.00277777 * 1e8);
    }

    function test_getCachedTwap_with_valid_price_after_a_second() public {
        _chainlinkPriceFeedV3.cacheTwap(_twapInterval);
        vm.warp(_timestamp + 1);
        // observation0 = 0 * 0 = 0
        // 0
        // observation1 = 995 * 1800 = 1,791,000
        // 1800

        // (995 * 1800 + 1000 * 1) / 1801 = 995.0027762354
        assertApproxEqAbs(_chainlinkPriceFeedV3.getCachedTwap(_twapInterval), 995.00277 * 1e8, 1e6);
    }

    function test_getCachedTwap_with_valid_price_after_several_seconds() public {
        _chainlinkPriceFeedV3.cacheTwap(_twapInterval);
        vm.warp(_timestamp + 1);
        _mock_call_latestRoundData(_roundId + 1, int256(_price + 1e8), _timestamp + 1);
        _chainlinkPriceFeedV3.cacheTwap(_twapInterval);
        vm.warp(_timestamp + 2);
        // (995 * 1800 + 1000 * 1 + 1001 * 1) / 1802 = 995.0061043285
        assertApproxEqAbs(_chainlinkPriceFeedV3.getCachedTwap(_twapInterval), 995.0061 * 1e8, 1e6);
    }

    function test_getCachedTwap_with_valid_price_after_several_seconds_without_cacheTwap() public {
        _chainlinkPriceFeedV3.cacheTwap(_twapInterval);
        vm.warp(_timestamp + 2);
        _mock_call_latestRoundData(_roundId + 1, int256(_price + 1e8), _timestamp + 1);
        // (995 * 1800 + 1000 * 1 + 1001 * 1) / 1802 = 995.0061043285
        assertApproxEqAbs(_chainlinkPriceFeedV3.getCachedTwap(_twapInterval), 995.0061 * 1e8, 1e6);
    }

    function test_cacheTwap_wont_update_when_the_new_timestamp_is_the_same() public {
        _chainlinkPriceFeedV3_cacheTwap_and_assert_eq(_twapInterval, _price);

        uint256 t2 = _timestamp + 60;

        _mock_call_latestRoundData(_roundId, 2000 * 1e8, t2);
        vm.warp(t2);
        _chainlinkPriceFeedV3.cacheTwap(_twapInterval);

        uint256 currentObservationIndexBefore = _chainlinkPriceFeedV3.currentObservationIndex();
        (uint256 priceBefore, , ) = _chainlinkPriceFeedV3.observations(currentObservationIndexBefore);
        uint256 twapBefore = _chainlinkPriceFeedV3.getCachedTwap(_twapInterval);

        // giving a different price but the same old timestamp
        _mock_call_latestRoundData(_roundId, 2500 * 1e8, t2);
        vm.warp(t2 + 1);

        // will update _cachedTwap
        _chainlinkPriceFeedV3.cacheTwap(_twapInterval);

        uint256 currentObservationIndexAfter = _chainlinkPriceFeedV3.currentObservationIndex();
        (uint256 priceAfter, , ) = _chainlinkPriceFeedV3.observations(currentObservationIndexAfter);
        uint256 twapAfter = _chainlinkPriceFeedV3.getCachedTwap(_twapInterval);

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
    }

    function test_cacheTwap_freezedReason_is_IncorrectDecimals() public {
        vm.mockCall(address(_testAggregator), abi.encodeWithSelector(_testAggregator.decimals.selector), abi.encode(7));

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(_prefilledPrice, _prefilledTimestamp, FreezedReason.IncorrectDecimals);

        _getFreezedReason_and_assert_eq(_chainlinkPriceFeedV3, FreezedReason.IncorrectDecimals);
    }

    function test_cacheTwap_freezedReason_is_NoRoundId() public {
        _mock_call_latestRoundData(0, int256(_price), _timestamp);

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(_prefilledPrice, _prefilledTimestamp, FreezedReason.NoRoundId);
        _getFreezedReason_and_assert_eq(_chainlinkPriceFeedV3, FreezedReason.NoRoundId);
    }

    function test_cacheTwap_freezedReason_is_InvalidTimestamp_with_zero_timestamp() public {
        // zero timestamp
        _mock_call_latestRoundData(_roundId, int256(_price), 0);

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(_prefilledPrice, _prefilledTimestamp, FreezedReason.InvalidTimestamp);
        _getFreezedReason_and_assert_eq(_chainlinkPriceFeedV3, FreezedReason.InvalidTimestamp);
    }

    function test_cacheTwap_freezedReason_is_InvalidTimestamp_with_future_timestamp() public {
        // future
        _mock_call_latestRoundData(_roundId, int256(_price), _timestamp + 1);

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(_prefilledPrice, _prefilledTimestamp, FreezedReason.InvalidTimestamp);

        _getFreezedReason_and_assert_eq(_chainlinkPriceFeedV3, FreezedReason.InvalidTimestamp);
    }

    function test_cacheTwap_freezedReason_is_InvalidTimestamp_with_past_timestamp() public {
        _chainlinkPriceFeedV3.cacheTwap(0);

        // < _lastValidTimestamp
        _mock_call_latestRoundData(_roundId, int256(_price), _timestamp - 1);
        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(_price, _timestamp, FreezedReason.InvalidTimestamp);
        _chainlinkPriceFeedV3.cacheTwap(_twapInterval);

        _getFreezedReason_and_assert_eq(_chainlinkPriceFeedV3, FreezedReason.InvalidTimestamp);
    }

    function test_cacheTwap_freezedReason_is_NonPositiveAnswer() public {
        _mock_call_latestRoundData(_roundId, -1, _timestamp);

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(_prefilledPrice, _prefilledTimestamp, FreezedReason.NonPositiveAnswer);
        _getFreezedReason_and_assert_eq(_chainlinkPriceFeedV3, FreezedReason.NonPositiveAnswer);
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
        assertEq(_chainlinkPriceFeedV3.getCachedTwap(_twapInterval), 995.02777777 * 1e8);
        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(uint256(price1), timestamp1, FreezedReason.NotFreezed);
        _chainlinkPriceFeedV3_cacheTwap_and_assert_eq(_twapInterval, 995.02777777 * 1e8);
        _getFreezedReason_and_assert_eq(_chainlinkPriceFeedV3, FreezedReason.NotFreezed);

        int256 price2 = 920 * 1e8;
        uint256 timestamp2 = timestamp1 + 20;
        _mock_call_latestRoundData(_roundId + 2, price2, timestamp2);
        vm.warp(timestamp2);
        // check interval = 0 is still cacheable
        // (995*1770+1000*10+960*20)/1800=994.6448087432
        assertEq(_chainlinkPriceFeedV3.getCachedTwap(_twapInterval), 994.63888888 * 1e8);
        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(uint256(price2), timestamp2, FreezedReason.NotFreezed);
        _chainlinkPriceFeedV3_cacheTwap_and_assert_eq(0, uint256(price2));
        _getFreezedReason_and_assert_eq(_chainlinkPriceFeedV3, FreezedReason.NotFreezed);
        // and twap still calculable as the same as above one
        assertEq(_chainlinkPriceFeedV3.getCachedTwap(_twapInterval), 994.63888888 * 1e8);
        vm.warp(timestamp2 + 10);
        // twap (by using latest price) = (995 * 1760 + 1000 * 10 + 960 * 20 + 920 * 10) / 1800 = 994.2222222222
        assertEq(_chainlinkPriceFeedV3.getCachedTwap(_twapInterval), 994.22222222 * 1e8);

        int256 price3 = 900 * 1e8;
        uint256 timestamp3 = timestamp2 + 20;
        _mock_call_latestRoundData(_roundId + 3, price3, timestamp3);
        vm.warp(timestamp3);
        // twap = (995 * 1750 + 1000 * 10 + 960 * 20 + 920 * 20) / 1800 = 993.80555555
        assertEq(_chainlinkPriceFeedV3.getCachedTwap(_twapInterval), 993.80555555 * 1e8);
        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(uint256(price3), timestamp3, FreezedReason.NotFreezed);
        _chainlinkPriceFeedV3_cacheTwap_and_assert_eq(_twapInterval, 993.80555555 * 1e8);
        _getFreezedReason_and_assert_eq(_chainlinkPriceFeedV3, FreezedReason.NotFreezed);

        uint256 timestamp4 = timestamp3 + _timeout;
        vm.warp(timestamp4);
        assertEq(_chainlinkPriceFeedV3.isTimedOut(), false);

        uint256 timestamp5 = timestamp4 + 1;
        vm.warp(timestamp5);
        assertEq(_chainlinkPriceFeedV3.isTimedOut(), true);
    }
}
