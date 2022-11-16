pragma solidity 0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "./Setup.sol";
import "../../contracts/interface/IPriceFeedV3.sol";
import "../../contracts/test/TestAggregatorV3.sol";

contract ChainlinkPriceFeedV3ConstructorTest is BaseSetup {
    function test_CPF_ANC() public {
        vm.expectRevert(bytes("CPF_ANC"));
        _chainlinkPriceFeedV3 = new ChainlinkPriceFeedV3(
            TestAggregatorV3(0),
            _timeout,
            _maxOutlierDeviationRatio,
            _outlierCoolDownPeriod,
            _twapInterval
        );
    }

    function test_CPF_IMODR() public {
        vm.expectRevert(bytes("CPF_IMODR"));
        _chainlinkPriceFeedV3 = new ChainlinkPriceFeedV3(
            _testAggregator,
            _timeout,
            1e7,
            _outlierCoolDownPeriod,
            _twapInterval
        );
    }
}

contract ChainlinkPriceFeedV3Common is IPriceFeedV3Event, BaseSetup {
    uint24 internal constant _ONE_HUNDRED_PERCENT_RATIO = 1e6;
    uint256 internal _timestamp = 10000000;
    uint256 internal _price = 1000 * 1e8;
    uint256 internal _roundId = 1;
    uint256 internal _timestampAfterOutlierCoolDownPeriod = _timestamp + _outlierCoolDownPeriod + 1;

    function setUp() public virtual override {
        BaseSetup.setUp();
        // we need Aggregator's decimals() function in the constructor of ChainlinkPriceFeedV3
        vm.mockCall(address(_testAggregator), abi.encodeWithSelector(_testAggregator.decimals.selector), abi.encode(8));
        _chainlinkPriceFeedV3 = _create_ChainlinkPriceFeedV3();

        vm.warp(_timestamp);
        _mock_call_latestRoundData(_roundId, int256(_price), _timestamp);
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
}

contract ChainlinkPriceFeedV3IntervalIsZeroTest is ChainlinkPriceFeedV3Common {
    using SafeMath for uint256;

    function test_cacheTwap_first_time_caching_with_valid_price() public {
        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(_price, _timestamp, FreezedReason.NotFreezed);

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
        // note that it's _chainlinkPriceFeedV3Broken here, not _chainlinkPriceFeedV3
        vm.expectEmit(false, false, false, true, address(_chainlinkPriceFeedV3Broken));
        emit ChainlinkPriceUpdated(0, 0, FreezedReason.NoResponse);

        assertEq(_chainlinkPriceFeedV3Broken.cacheTwap(0), 0);
        assertEq(_chainlinkPriceFeedV3Broken.getLastValidTime(), 0);
        assertEq(int256(_chainlinkPriceFeedV3Broken.getFreezedReason()), int256(FreezedReason.NoResponse));
    }

    function test_cacheTwap_freezedReason_is_IncorrectDecimals() public {
        vm.mockCall(address(_testAggregator), abi.encodeWithSelector(_testAggregator.decimals.selector), abi.encode(7));

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(0, 0, FreezedReason.IncorrectDecimals);
        _chainlinkPriceFeedV3.cacheTwap(0);
    }

    function test_cacheTwap_freezedReason_is_NoRoundId() public {
        _mock_call_latestRoundData(0, int256(_price), _timestamp);

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(0, 0, FreezedReason.NoRoundId);
        _chainlinkPriceFeedV3.cacheTwap(0);
    }

    function test_cacheTwap_freezedReason_is_InvalidTimestamp_with_zero_timestamp() public {
        // zero timestamp
        _mock_call_latestRoundData(_roundId, int256(_price), 0);

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(0, 0, FreezedReason.InvalidTimestamp);
        _chainlinkPriceFeedV3.cacheTwap(0);
    }

    function test_cacheTwap_freezedReason_is_InvalidTimestamp_with_future_timestamp() public {
        // future
        _mock_call_latestRoundData(_roundId, int256(_price), _timestamp + 1);

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(0, 0, FreezedReason.InvalidTimestamp);
        _chainlinkPriceFeedV3.cacheTwap(0);
    }

    function test_cacheTwap_freezedReason_is_InvalidTimestamp_with_past_timestamp() public {
        _chainlinkPriceFeedV3.cacheTwap(0);

        // < _lastValidTime
        _mock_call_latestRoundData(_roundId, int256(_price), _timestamp - 1);

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(_price, _timestamp, FreezedReason.InvalidTimestamp);
        _chainlinkPriceFeedV3.cacheTwap(0);
    }

    function test_cacheTwap_freezedReason_is_NonPositiveAnswer() public {
        _mock_call_latestRoundData(_roundId, -1, _timestamp);

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(0, 0, FreezedReason.NonPositiveAnswer);
        _chainlinkPriceFeedV3.cacheTwap(0);
    }

    function test_cacheTwap_freezedReason_is_AnswerIsOutlier_outlier_larger_than__lastValidPrice() public {
        _chainlinkPriceFeedV3.cacheTwap(0);

        int256 outlier = 2000 * 1e8;
        _mock_call_latestRoundData(_roundId + 1, outlier, _timestampAfterOutlierCoolDownPeriod);
        vm.warp(_timestampAfterOutlierCoolDownPeriod);

        uint256 maxDeviatedPrice =
            _price.mul(_ONE_HUNDRED_PERCENT_RATIO + _maxOutlierDeviationRatio).div(_ONE_HUNDRED_PERCENT_RATIO);
        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(
            maxDeviatedPrice,
            _timestampAfterOutlierCoolDownPeriod,
            FreezedReason.AnswerIsOutlier
        );
        _chainlinkPriceFeedV3.cacheTwap(0);
    }

    function test_cacheTwap_freezedReason_is_AnswerIsOutlier_outlier_smaller_than__lastValidPrice() public {
        _chainlinkPriceFeedV3.cacheTwap(0);

        int256 outlier = 500 * 1e8;
        _mock_call_latestRoundData(_roundId + 1, outlier, _timestampAfterOutlierCoolDownPeriod);
        vm.warp(_timestampAfterOutlierCoolDownPeriod);

        uint256 maxDeviatedPrice =
            _price.mul(_ONE_HUNDRED_PERCENT_RATIO - _maxOutlierDeviationRatio).div(_ONE_HUNDRED_PERCENT_RATIO);
        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(
            maxDeviatedPrice,
            _timestampAfterOutlierCoolDownPeriod,
            FreezedReason.AnswerIsOutlier
        );
        _chainlinkPriceFeedV3.cacheTwap(0);
    }

    function test_cacheTwap_freezedReason_is_AnswerIsOutlier_but_before__outlierCoolDownPeriod() public {
        _chainlinkPriceFeedV3.cacheTwap(0);

        uint256 timestampBeforeOutlierCoolDownPeriod = _timestampAfterOutlierCoolDownPeriod - 2;
        _mock_call_latestRoundData(_roundId + 1, 500 * 1e8, timestampBeforeOutlierCoolDownPeriod);
        vm.warp(timestampBeforeOutlierCoolDownPeriod);

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        // FreezedReason will be emitted while price & timestamp remain as _lastValidPrice & _lastValidTime
        emit ChainlinkPriceUpdated(_price, _timestamp, FreezedReason.AnswerIsOutlier);
        _chainlinkPriceFeedV3.cacheTwap(0);
    }

    function test_cacheTwap_no_outlier_but_timestamp_is_after__outlierCoolDownPeriod() public {
        _chainlinkPriceFeedV3.cacheTwap(0);

        int256 price = 950 * 1e8;
        _mock_call_latestRoundData(_roundId + 1, price, _timestampAfterOutlierCoolDownPeriod);
        vm.warp(_timestampAfterOutlierCoolDownPeriod);

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(uint256(price), _timestampAfterOutlierCoolDownPeriod, FreezedReason.NotFreezed);
        _chainlinkPriceFeedV3.cacheTwap(0);
    }
}

contract ChainlinkPriceFeedV3IntervalIsNotZeroTest is ChainlinkPriceFeedV3Common {
    using SafeMath for uint256;

    function test_cacheTwap_first_time_caching_with_valid_price() public {
        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(_price, _timestamp, FreezedReason.NotFreezed);

        assertEq(_chainlinkPriceFeedV3.cacheTwap(_twapInterval), 0);
    }

    function test_cacheTwap_wont_update_when_the_new_timestamp_is_the_same() public {
        assertEq(_chainlinkPriceFeedV3.cacheTwap(_twapInterval), 0);

        // giving a different price but the same timestamp
        _mock_call_latestRoundData(_roundId, 2000 * 1e8, _timestamp);

        // price won't get cached
        assertEq(_chainlinkPriceFeedV3.cacheTwap(_twapInterval), 0);
    }

    function test_cacheTwap_freezedReason_is_NoResponse() public {
        // note that it's _chainlinkPriceFeedV3Broken here, not _chainlinkPriceFeedV3
        vm.expectEmit(false, false, false, true, address(_chainlinkPriceFeedV3Broken));
        emit ChainlinkPriceUpdated(0, 0, FreezedReason.NoResponse);

        assertEq(_chainlinkPriceFeedV3Broken.cacheTwap(_twapInterval), 0);
        assertEq(_chainlinkPriceFeedV3Broken.getLastValidTime(), 0);
        assertEq(int256(_chainlinkPriceFeedV3Broken.getFreezedReason()), int256(FreezedReason.NoResponse));
    }

    function test_cacheTwap_freezedReason_is_IncorrectDecimals() public {
        vm.mockCall(address(_testAggregator), abi.encodeWithSelector(_testAggregator.decimals.selector), abi.encode(7));

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(0, 0, FreezedReason.IncorrectDecimals);
        assertEq(_chainlinkPriceFeedV3.cacheTwap(_twapInterval), 0);
    }

    function test_cacheTwap_freezedReason_is_NoRoundId() public {
        _mock_call_latestRoundData(0, int256(_price), _timestamp);

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(0, 0, FreezedReason.NoRoundId);
        assertEq(_chainlinkPriceFeedV3.cacheTwap(_twapInterval), 0);
    }

    function test_cacheTwap_freezedReason_is_InvalidTimestamp_with_zero_timestamp() public {
        // zero timestamp
        _mock_call_latestRoundData(_roundId, int256(_price), 0);

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(0, 0, FreezedReason.InvalidTimestamp);
        assertEq(_chainlinkPriceFeedV3.cacheTwap(_twapInterval), 0);
    }

    function test_cacheTwap_freezedReason_is_InvalidTimestamp_with_future_timestamp() public {
        // future
        _mock_call_latestRoundData(_roundId, int256(_price), _timestamp + 1);

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(0, 0, FreezedReason.InvalidTimestamp);
        assertEq(_chainlinkPriceFeedV3.cacheTwap(_twapInterval), 0);
    }

    function test_cacheTwap_freezedReason_is_InvalidTimestamp_with_past_timestamp() public {
        _chainlinkPriceFeedV3.cacheTwap(0);

        // < _lastValidTime
        _mock_call_latestRoundData(_roundId, int256(_price), _timestamp - 1);

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(_price, _timestamp, FreezedReason.InvalidTimestamp);
        assertEq(_chainlinkPriceFeedV3.cacheTwap(_twapInterval), 0);
    }

    function test_cacheTwap_freezedReason_is_NonPositiveAnswer() public {
        _mock_call_latestRoundData(_roundId, -1, _timestamp);

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(0, 0, FreezedReason.NonPositiveAnswer);
        assertEq(_chainlinkPriceFeedV3.cacheTwap(_twapInterval), 0);
    }

    function test_cacheTwap_freezedReason_is_AnswerIsOutlier_outlier_larger_than__lastValidPrice() public {
        _chainlinkPriceFeedV3.cacheTwap(_twapInterval);

        int256 outlier = 2000 * 1e8;
        _mock_call_latestRoundData(_roundId + 1, outlier, _timestampAfterOutlierCoolDownPeriod);
        vm.warp(_timestampAfterOutlierCoolDownPeriod);

        uint256 maxDeviatedPrice =
            _price.mul(_ONE_HUNDRED_PERCENT_RATIO + _maxOutlierDeviationRatio).div(_ONE_HUNDRED_PERCENT_RATIO);
        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(
            maxDeviatedPrice,
            _timestampAfterOutlierCoolDownPeriod,
            FreezedReason.AnswerIsOutlier
        );
        assertEq(_chainlinkPriceFeedV3.cacheTwap(_twapInterval), _price);
    }

    function test_cacheTwap_freezedReason_is_AnswerIsOutlier_outlier_smaller_than__lastValidPrice() public {
        _chainlinkPriceFeedV3.cacheTwap(_twapInterval);

        int256 outlier = 500 * 1e8;
        _mock_call_latestRoundData(_roundId + 1, outlier, _timestampAfterOutlierCoolDownPeriod);
        vm.warp(_timestampAfterOutlierCoolDownPeriod);

        uint256 maxDeviatedPrice =
            _price.mul(_ONE_HUNDRED_PERCENT_RATIO - _maxOutlierDeviationRatio).div(_ONE_HUNDRED_PERCENT_RATIO);
        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(
            maxDeviatedPrice,
            _timestampAfterOutlierCoolDownPeriod,
            FreezedReason.AnswerIsOutlier
        );
        assertEq(_chainlinkPriceFeedV3.cacheTwap(_twapInterval), _price);
    }

    function test_cacheTwap_freezedReason_is_AnswerIsOutlier_but_before__outlierCoolDownPeriod() public {
        _chainlinkPriceFeedV3.cacheTwap(_twapInterval);

        uint256 timestampBeforeOutlierCoolDownPeriod = _timestampAfterOutlierCoolDownPeriod - 2;
        _mock_call_latestRoundData(_roundId + 1, 500 * 1e8, timestampBeforeOutlierCoolDownPeriod);
        vm.warp(timestampBeforeOutlierCoolDownPeriod);

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        // FreezedReason will be emitted while price & timestamp remain as _lastValidPrice & _lastValidTime
        emit ChainlinkPriceUpdated(_price, _timestamp, FreezedReason.AnswerIsOutlier);

        vm.expectRevert(bytes("CT_IT"));
        _chainlinkPriceFeedV3.cacheTwap(_twapInterval);
    }

    function test_cacheTwap_no_outlier_but_timestamp_is_after__outlierCoolDownPeriod() public {
        _chainlinkPriceFeedV3.cacheTwap(_twapInterval);

        int256 price = 950 * 1e8;
        _mock_call_latestRoundData(_roundId + 1, price, _timestampAfterOutlierCoolDownPeriod);
        vm.warp(_timestampAfterOutlierCoolDownPeriod);

        _expect_emit_event_from_ChainlinkPriceFeedV3();
        emit ChainlinkPriceUpdated(uint256(price), _timestampAfterOutlierCoolDownPeriod, FreezedReason.NotFreezed);
        assertEq(_chainlinkPriceFeedV3.cacheTwap(_twapInterval), _price);
    }
}
