pragma solidity 0.7.6;
pragma abicoder v2;

import "forge-std/Test.sol";

import "@openzeppelin/contracts/math/SafeMath.sol";
import "./BaseSetup.sol";
import "../../contracts/interface/IPriceFeedV3.sol";

contract ChainlinkPriceFeedV3Test is IPriceFeedV3Event, BaseSetup {
    using SafeMath for uint256;

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

    function test_cachePrice_first_call_with_valid_price() public {
        vm.expectEmit(false, false, false, true, address(_chainlinkPriceFeedV3));
        emit PriceUpdated(_price, _timestamp, FreezedReason.NotFreezed);
        assertEq(_chainlinkPriceFeedV3.cachePrice(), _price);
        assertEq(_chainlinkPriceFeedV3.getLastValidPrice(), _price);
    }

    function test_cachePrice_should_return__lastValidPrice_when_new_price_is_the_same() public {
        _chainlinkPriceFeedV3.cachePrice();

        _mock_call_latestRoundData(_roundId, 2000 * 1e8, _timestamp);

        assertEq(_chainlinkPriceFeedV3.cachePrice(), _price);
    }

    function test_cachePrice_freezedReason_is_NoResponse() public {
        // cannot expect event here bc of foundry's bug
        // vm.expectEmit(false, false, false, false, address(_chainlinkPriceFeedV3Broken));
        // emit PriceUpdated(0, 0, FreezedReason.NoResponse);

        assertEq(_chainlinkPriceFeedV3Broken.cachePrice(), 0);
        assertEq(_chainlinkPriceFeedV3Broken.getLastValidTime(), 0);
        assertEq(int256(_chainlinkPriceFeedV3Broken.getFreezedReason()), int256(FreezedReason.NoResponse));
    }

    function test_cachePrice_freezedReason_is_IncorrectDecimals() public {
        vm.mockCall(address(_testAggregator), abi.encodeWithSelector(_testAggregator.decimals.selector), abi.encode(7));

        vm.expectEmit(false, false, false, true, address(_chainlinkPriceFeedV3));
        emit PriceUpdated(0, 0, FreezedReason.IncorrectDecimals);
        _chainlinkPriceFeedV3.cachePrice();
    }

    function test_cachePrice_freezedReason_is_NoRoundId() public {
        _mock_call_latestRoundData(0, int256(_price), _timestamp);

        vm.expectEmit(false, false, false, true, address(_chainlinkPriceFeedV3));
        emit PriceUpdated(0, 0, FreezedReason.NoRoundId);
        _chainlinkPriceFeedV3.cachePrice();
    }

    function test_cachePrice_freezedReason_is_InvalidTimestamp_with_no_time() public {
        // no time
        _mock_call_latestRoundData(_roundId, int256(_price), 0);

        vm.expectEmit(false, false, false, true, address(_chainlinkPriceFeedV3));
        emit PriceUpdated(0, 0, FreezedReason.InvalidTimestamp);
        _chainlinkPriceFeedV3.cachePrice();
    }

    function test_cachePrice_freezedReason_is_InvalidTimestamp_with_future_time() public {
        // future time
        _mock_call_latestRoundData(_roundId, int256(_price), _timestamp + 1);

        vm.expectEmit(false, false, false, true, address(_chainlinkPriceFeedV3));
        emit PriceUpdated(0, 0, FreezedReason.InvalidTimestamp);
        _chainlinkPriceFeedV3.cachePrice();
    }

    function test_cachePrice_freezedReason_is_InvalidTimestamp_with_previous_time() public {
        // <= _lastValidTime
        _chainlinkPriceFeedV3.cachePrice();

        _mock_call_latestRoundData(_roundId, int256(_price), _timestamp - 1);

        vm.expectEmit(false, false, false, true, address(_chainlinkPriceFeedV3));
        emit PriceUpdated(_price, _timestamp, FreezedReason.InvalidTimestamp);
        _chainlinkPriceFeedV3.cachePrice();
    }

    function test_cachePrice_freezedReason_is_NonPositiveAnswer() public {
        _mock_call_latestRoundData(_roundId, -1, _timestamp);

        vm.expectEmit(false, false, false, true, address(_chainlinkPriceFeedV3));
        emit PriceUpdated(0, 0, FreezedReason.NonPositiveAnswer);
        _chainlinkPriceFeedV3.cachePrice();
    }

    function test_cachePrice_freezedReason_is_PotentialOutlier_outlier_larger_than__lastValidPrice() public {
        _chainlinkPriceFeedV3.cachePrice();

        int256 outlier = 2000 * 1e8;
        _mock_call_latestRoundData(_roundId + 1, outlier, _timestampAfterOutlierCoolDownPeriod);
        vm.warp(_timestampAfterOutlierCoolDownPeriod);

        uint256 maxDeviatedPrice = _price.mul(1e6 + _maxOutlierDeviationRatio).div(1e6);
        vm.expectEmit(false, false, false, true, address(_chainlinkPriceFeedV3));
        emit PriceUpdated(maxDeviatedPrice, _timestampAfterOutlierCoolDownPeriod, FreezedReason.PotentialOutlier);
        _chainlinkPriceFeedV3.cachePrice();
    }

    function test_cachePrice_freezedReason_is_PotentialOutlier_outlier_smaller_than__lastValidPrice() public {
        _chainlinkPriceFeedV3.cachePrice();

        int256 outlier = 500 * 1e8;
        _mock_call_latestRoundData(_roundId + 1, outlier, _timestampAfterOutlierCoolDownPeriod);
        vm.warp(_timestampAfterOutlierCoolDownPeriod);

        uint256 maxDeviatedPrice = _price.mul(1e6 - _maxOutlierDeviationRatio).div(1e6);
        vm.expectEmit(false, false, false, true, address(_chainlinkPriceFeedV3));
        emit PriceUpdated(maxDeviatedPrice, _timestampAfterOutlierCoolDownPeriod, FreezedReason.PotentialOutlier);
        _chainlinkPriceFeedV3.cachePrice();
    }

    function test_cachePrice_no_outlier_but_timestamp_is_after__outlierCoolDownPeriod() public {
        _chainlinkPriceFeedV3.cachePrice();

        int256 price = 950 * 1e8;
        _mock_call_latestRoundData(_roundId + 1, price, _timestampAfterOutlierCoolDownPeriod);
        vm.warp(_timestampAfterOutlierCoolDownPeriod);

        vm.expectEmit(false, false, false, true, address(_chainlinkPriceFeedV3));
        emit PriceUpdated(uint256(price), _timestampAfterOutlierCoolDownPeriod, FreezedReason.NotFreezed);
        _chainlinkPriceFeedV3.cachePrice();
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
}
