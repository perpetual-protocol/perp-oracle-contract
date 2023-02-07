pragma solidity 0.7.6;

import "forge-std/Test.sol";
import { CumulativeTwap } from "../../contracts/twap/CumulativeTwap.sol";

contract TestCumulativeTwap is CumulativeTwap {
    function update(uint256 price, uint256 lastUpdatedTimestamp) external returns (bool isUpdated) {
        return _update(price, lastUpdatedTimestamp);
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
        (uint256 priceBefore, uint256 priceCumulativeBefore, uint256 timestampBefore) = _testCumulativeTwap
            .observations(latestObservationIndex);

        // second update won't update
        assertEq(_testCumulativeTwap.update(p1, t1 + 10), false);
        assertEq(_testCumulativeTwap.currentObservationIndex(), latestObservationIndex);

        (uint256 priceAfter, uint256 priceCumulativeAfter, uint256 timestampAfter) = _testCumulativeTwap.observations(
            latestObservationIndex
        );
        assertEq(priceBefore, priceAfter);
        assertEq(priceCumulativeBefore, priceCumulativeAfter);
        assertEq(timestampBefore, timestampAfter);
    }
}
