pragma solidity 0.7.6;

import "forge-std/Test.sol";
import { CumulativeTwap } from "../../contracts/twap/CumulativeTwap.sol";

contract TestCumulativeTwap is CumulativeTwap {
    function update(uint256 price, uint256 lastUpdatedTimestamp) external returns (bool isUpdated) {
        return _update(price, lastUpdatedTimestamp);
    }

    function calculateTwap(
        uint256 interval,
        uint256 price,
        uint256 latestUpdatedTimestamp
    ) external returns (uint256 twap) {
        return _calculateTwap(interval, price, latestUpdatedTimestamp);
    }

    function getObservationLength() external returns (uint256) {
        return MAX_OBSERVATION;
    }
}

contract CumulativeTwapSetup is Test {
    TestCumulativeTwap internal _testCumulativeTwap;

    struct Observation {
        uint256 price;
        uint256 priceCumulative;
        uint256 timestamp;
    }

    function _updatePrice(uint256 price, bool forward) internal {
        _testCumulativeTwap.update(price, block.timestamp);

        if (forward) {
            vm.warp(block.timestamp + 15);
            vm.roll(block.number + 1);
        }
    }

    function _isObservationEqualTo(
        uint256 index,
        uint256 expectedPrice,
        uint256 expectedPriceCumulative,
        uint256 expectedTimestamp
    ) internal {
        (uint256 _price, uint256 _priceCumulative, uint256 _timestamp) = _testCumulativeTwap.observations(index);
        assertEq(_price, expectedPrice);
        assertEq(_priceCumulative, expectedPriceCumulative);
        assertEq(_timestamp, expectedTimestamp);
    }

    function _getTwap(uint256 interval) internal returns (uint256) {
        uint256 currentIndex = _testCumulativeTwap.currentObservationIndex();
        (uint256 price, uint256 _, uint256 time) = _testCumulativeTwap.observations(currentIndex);
        return _testCumulativeTwap.calculateTwap(interval, price, time);
    }

    function setUp() public virtual {
        _testCumulativeTwap = new TestCumulativeTwap();
    }
}

contract CumulativeTwapUpdateTest is CumulativeTwapSetup {
    uint256 internal constant _INIT_BLOCK_TIMESTAMP = 1000;

    function setUp() public virtual override {
        vm.warp(_INIT_BLOCK_TIMESTAMP);

        CumulativeTwapSetup.setUp();
    }

    function test_update_correctly() public {
        uint256 t1 = _INIT_BLOCK_TIMESTAMP;
        uint256 p1 = 100 * 1e8;

        bool result1 = _testCumulativeTwap.update(p1, t1);

        uint256 observationIndex1 = _testCumulativeTwap.currentObservationIndex();

        (uint256 price1, uint256 priceCumulative1, uint256 timestamp1) =
            _testCumulativeTwap.observations(observationIndex1);

        assertTrue(result1);
        assertEq(observationIndex1, 0);
        assertEq(price1, p1);
        assertEq(priceCumulative1, 0);
        assertEq(timestamp1, t1);

        uint256 t2 = _INIT_BLOCK_TIMESTAMP + 10;
        uint256 p2 = 110 * 1e8;
        vm.warp(t2);

        bool result2 = _testCumulativeTwap.update(p2, t2);

        uint256 observationIndex2 = _testCumulativeTwap.currentObservationIndex();

        (uint256 price2, uint256 priceCumulative2, uint256 timestamp2) =
            _testCumulativeTwap.observations(observationIndex2);

        assertTrue(result2);
        assertEq(observationIndex2, 1);
        assertEq(price2, p2);
        assertEq(priceCumulative2, 1000 * 1e8); // 10 * 100 * 1e8
        assertEq(timestamp2, t2);
    }

    function test_revert_update_when_timestamp_is_less_than_last_observation() public {
        uint256 t1 = _INIT_BLOCK_TIMESTAMP;
        uint256 p1 = 100 * 1e8;
        assertEq(_testCumulativeTwap.update(p1, t1), true);

        vm.expectRevert(bytes("CT_IT"));
        assertEq(_testCumulativeTwap.update(p1, t1 - 10), false);
    }

    function test_update_when_price_is_the_same_as_last_opservation() public {
        uint256 t1 = _INIT_BLOCK_TIMESTAMP;
        uint256 p1 = 100 * 1e8;

        // first update
        assertEq(_testCumulativeTwap.update(p1, t1), true);

        uint256 latestObservationIndex = _testCumulativeTwap.currentObservationIndex();
        (uint256 priceBefore, uint256 priceCumulativeBefore, uint256 timestampBefore) =
            _testCumulativeTwap.observations(latestObservationIndex);

        // second update won't update
        assertEq(_testCumulativeTwap.update(p1, t1 + 10), false);
        assertEq(_testCumulativeTwap.currentObservationIndex(), latestObservationIndex);

        (uint256 priceAfter, uint256 priceCumulativeAfter, uint256 timestampAfter) =
            _testCumulativeTwap.observations(latestObservationIndex);
        assertEq(priceBefore, priceAfter);
        assertEq(priceCumulativeBefore, priceCumulativeAfter);
        assertEq(timestampBefore, timestampAfter);
    }

    function test_update_when_timestamp_and_price_is_the_same_as_last_opservation() public {
        uint256 t1 = _INIT_BLOCK_TIMESTAMP;
        uint256 p1 = 100 * 1e8;

        // first update
        assertEq(_testCumulativeTwap.update(p1, t1), true);

        uint256 latestObservationIndex = _testCumulativeTwap.currentObservationIndex();
        (uint256 priceBefore, uint256 priceCumulativeBefore, uint256 timestampBefore) =
            _testCumulativeTwap.observations(latestObservationIndex);

        // second update won't update
        assertEq(_testCumulativeTwap.update(p1, t1), false);
        assertEq(_testCumulativeTwap.currentObservationIndex(), latestObservationIndex);

        (uint256 priceAfter, uint256 priceCumulativeAfter, uint256 timestampAfter) =
            _testCumulativeTwap.observations(latestObservationIndex);
        assertEq(priceBefore, priceAfter);
        assertEq(priceCumulativeBefore, priceCumulativeAfter);
        assertEq(timestampBefore, timestampAfter);
    }
}

contract CumulativeTwapCalculateTwapBase is CumulativeTwapSetup {
    uint256 internal constant _BEGIN_PRICE = 400;
    uint256 internal _BEGIN_TIME = block.timestamp;
    uint256 internal observationLength;

    function setUp() public virtual override {
        vm.warp(_BEGIN_TIME);

        CumulativeTwapSetup.setUp();

        observationLength = _testCumulativeTwap.getObservationLength();
    }
}

contract CumulativeTwapCalculateTwapTestWithoutObservation is CumulativeTwapCalculateTwapBase {
    function test_calculateTwap_should_return_0_when_observations_is_empty() public {
        assertEq(_testCumulativeTwap.currentObservationIndex(), uint256(0));

        assertEq(_getTwap(45), uint256(0));
    }
}

contract CumulativeTwapCalculateTwapTest is CumulativeTwapCalculateTwapBase {
    function setUp() public virtual override {
        CumulativeTwapCalculateTwapBase.setUp();

        // timestamp(_BEGIN_TIME + 0)  : 400
        // timestamp(_BEGIN_TIME + 15) : 405
        // timestamp(_BEGIN_TIME + 30) : 410
        // now = _BEGIN_TIME + 45

        _updatePrice(400, true);
        _updatePrice(405, true);
        _updatePrice(410, true);
    }

    function test_calculateTwap_when_interval_is_0() public {
        assertEq(_getTwap(0), 0);
    }

    function test_calculateTwap_when_given_a_valid_interval() public {
        // (410*15+405*15+400*5)/35=406.4
        assertEq(_getTwap(35), 406); // case 3: in the mid
        // (410*15+405*15)/30=407.5
        assertEq(_getTwap(30), 407); // case 1: left bound

        _updatePrice(415, false);
        // (410*15+405*15)/30=407.5
        assertEq(_getTwap(30), 407); // case 2: right bound
    }

    function test_calculateTwap_when_given_a_valid_interval_and_hasnt_beenn_updated_for_a_while() public {
        uint256 t = block.timestamp + 10;
        vm.warp(t);
        vm.roll(block.number + 1);
        // (410*25+405*5)/30=409.1
        assertEq(_testCumulativeTwap.calculateTwap(30, 415, t), 409);

        // (415*5+410*20)/25=411
        assertEq(_testCumulativeTwap.calculateTwap(25, 415, t - 5), 411);
    }

    function test_calculateTwap_when_given_a_interval_less_than_latest_observation() public {
        // (410*14)/14=410
        assertEq(_getTwap(14), 410);
    }

    function test_calculateTwap_when_given_interval_exceeds_observations() public {
        assertEq(_getTwap(46), 0);
    }

    function test_calculateTwap_when_valid_timestamp_and_price() public {
        uint256 interval = 30;
        uint256 t1 = 1000;
        uint256 p1 = 100 * 1e8;
        assertEq(_testCumulativeTwap.update(p1, t1), true);

        uint256 t2 = t1 + interval;
        vm.warp(t2);
        assertEq(_testCumulativeTwap.calculateTwap(interval, p1, t1), p1);
    }

    function test_revert_calculateTwap_when_same_timestamp_and_different_price() public {
        uint256 interval = 30;
        uint256 t1 = 1000;
        uint256 p1 = 100 * 1e8;
        assertEq(_testCumulativeTwap.update(p1, t1), true);

        uint256 t2 = t1 + interval;
        uint256 p2 = 120 * 1e8;
        vm.warp(t2);
        vm.expectRevert(bytes("CT_IPWCT"));
        _testCumulativeTwap.calculateTwap(interval, p2, t1);
    }
}

contract CumulativeTwapRingBufferTest is CumulativeTwapCalculateTwapBase {
    function setUp() public virtual override {
        CumulativeTwapCalculateTwapBase.setUp();

        // fill up observations[] excludes the last one
        for (uint256 i = 0; i < observationLength - 1; i++) {
            _updatePrice(_BEGIN_PRICE + i, true);
        }
    }

    function test_calculateTwap_when_index_hasnt_get_rotated() public {
        // last filled up index
        assertEq(_testCumulativeTwap.currentObservationIndex(), observationLength - 2);
        (uint256 pricePrev, uint256 priceCumulativePrev, uint256 _) =
            _testCumulativeTwap.observations(observationLength - 3);
        _isObservationEqualTo(
            observationLength - 2,
            2198, // _BEGIN_PRICE + observationLength - 2 = 400 + 1798
            priceCumulativePrev + pricePrev * 15, // 1797's cumulative price + 1797 * 15
            26971 // _BEGIN_TIME + (observationLength - 2) * 15 = 1 + 1798 * 15
        );

        // last observation hasn't been filled up yet
        _isObservationEqualTo(observationLength - 1, 0, 0, 0);

        // (2196 * 15 + 2197 * 15 + 2198 * 15) / 45 = 2197
        assertEq(_getTwap(45), 2197);
    }

    function test_calculateTwap_when_index_has_rotated_to_0() public {
        _updatePrice(_BEGIN_PRICE + observationLength - 1, true); // currentObservationIndex=1799, price=400+1799
        _updatePrice(_BEGIN_PRICE + observationLength, true); // currentObservationIndex=0, price=400+1800

        assertEq(_testCumulativeTwap.currentObservationIndex(), uint256(0));

        // (2200 * 15 + 2199 * 15 + 2198 * 15) / 45 = 2199
        assertEq(_getTwap(45), 2199);
    }

    function test_calculateTwap_when_index_has_rotated_to_9() public {
        _updatePrice(_BEGIN_PRICE + observationLength - 1, true); // currentObservationIndex=1799, price=400+1799
        for (uint256 i; i < 10; i++) {
            _updatePrice(_BEGIN_PRICE + observationLength + i, true);
        }

        assertEq(_testCumulativeTwap.currentObservationIndex(), uint256(9));

        // (2207 * 15 + 2208 * 15 + 2209 * 15) / 45 = 2208
        assertEq(_getTwap(45), 2208);
    }

    function test_calculateTwap_when_twap_interval_is_exact_the_maximum_limitation() public {
        _updatePrice(_BEGIN_PRICE + observationLength - 1, true); // currentObservationIndex=1799, price=400+1799
        _updatePrice(_BEGIN_PRICE + observationLength, false); // currentObservationIndex=0, price=400+1800

        assertEq(_testCumulativeTwap.currentObservationIndex(), uint256(0));

        // (((401 + 2199) / 2) * (26986-1) + 2200 * 1) / 26986 = 1300.0333506263
        assertEq(_getTwap(1799 * 15), 1300);
    }

    function test_calculateTwap_should_return_0_when_twap_interval_exceeds_maximum_limitation() public {
        _updatePrice(_BEGIN_PRICE + observationLength - 1, true); // currentObservationIndex=1799, price=400+1799
        _updatePrice(_BEGIN_PRICE + observationLength, false); // currentObservationIndex=0, price=400+1800

        assertEq(_testCumulativeTwap.currentObservationIndex(), uint256(0));

        assertEq(_getTwap(1799 * 15 + 1), uint256(0));
    }
}
