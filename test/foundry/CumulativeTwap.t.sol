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
}

contract CumulativeTwapTest is Test {
    uint256 internal constant _INIT_BLOCK_TIMESTAMP = 1000;

    TestCumulativeTwap internal _testCumulativeTwap;

    function setUp() public {
        vm.warp(_INIT_BLOCK_TIMESTAMP);

        _testCumulativeTwap = new TestCumulativeTwap();
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

    function test_calculateTwap_when_valid_timestamp_and_price() public {
        uint256 interval = 30;
        uint256 t1 = _INIT_BLOCK_TIMESTAMP;
        uint256 p1 = 100 * 1e8;
        assertEq(_testCumulativeTwap.update(p1, t1), true);

        uint256 t2 = t1 + interval;
        vm.warp(t2);
        assertEq(_testCumulativeTwap.calculateTwap(interval, p1, t1), p1);
    }

    function test_revert_calculateTwap_when_same_timestamp_and_different_price() public {
        uint256 interval = 30;
        uint256 t1 = _INIT_BLOCK_TIMESTAMP;
        uint256 p1 = 100 * 1e8;
        assertEq(_testCumulativeTwap.update(p1, t1), true);

        uint256 t2 = t1 + interval;
        uint256 p2 = 120 * 1e8;
        vm.warp(t2);
        vm.expectRevert(bytes("CT_IPWCT"));
        _testCumulativeTwap.calculateTwap(interval, p2, t1);
    }
}
