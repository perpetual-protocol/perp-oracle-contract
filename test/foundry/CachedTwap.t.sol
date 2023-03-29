pragma solidity 0.7.6;

import "forge-std/Test.sol";
import { CachedTwap } from "../../contracts/twap/CachedTwap.sol";

contract TestCachedTwap is CachedTwap {
    constructor(uint80 interval) CachedTwap(interval) {}

    function cacheTwap(
        uint256 interval,
        uint256 latestPrice,
        uint256 latestUpdatedTimestamp
    ) external returns (uint256 cachedTwap) {
        return _cacheTwap(interval, latestPrice, latestUpdatedTimestamp);
    }
}

contract CachedTwapTest is Test {
    uint80 internal constant _INTERVAL = 900;

    uint256 internal constant _INIT_BLOCK_TIMESTAMP = 1000;

    TestCachedTwap internal _testCachedTwap;

    function setUp() public {
        vm.warp(_INIT_BLOCK_TIMESTAMP);

        _testCachedTwap = new TestCachedTwap(_INTERVAL);
    }

    function test_cacheTwap_will_update_latestPrice_and_cachedTwap_when_valid_timestamp_and_price() public {
        //           t1       t2     t3
        //      -----+--------+--------+
        //              1200s    1200s
        // price:   100      120      140
        uint256 cachedTwap;

        uint256 t1 = _INIT_BLOCK_TIMESTAMP;
        uint256 p1 = 100 * 1e8;

        cachedTwap = _testCachedTwap.cacheTwap(_INTERVAL, p1, t1);
        assertEq(cachedTwap, p1);

        uint256 t2 = t1 + 1200;
        uint256 p2 = 120 * 1e8;
        vm.warp(t2);

        cachedTwap = _testCachedTwap.cacheTwap(_INTERVAL, p2, t2);
        assertEq(cachedTwap, p1);

        uint256 t3 = t2 + 1200;
        uint256 p3 = 140 * 1e8;
        vm.warp(t3);

        cachedTwap = _testCachedTwap.cacheTwap(_INTERVAL, p3, t3);
        assertEq(cachedTwap, p2);
    }

    function test_cacheTwap_wont_update_latestPrice_but_update_cachedTwap_when_same_timestamp_and_price() public {
        //           t1      t2
        //      -----+--------+------
        //              1200s
        // price:   100      120
        uint256 cachedTwap;

        uint256 t1 = _INIT_BLOCK_TIMESTAMP;
        uint256 p1 = 100 * 1e8;

        cachedTwap = _testCachedTwap.cacheTwap(_INTERVAL, p1, t1);
        assertEq(cachedTwap, p1);

        uint256 t2 = t1 + 1200;
        uint256 p2 = 120 * 1e8;
        vm.warp(t2);

        cachedTwap = _testCachedTwap.cacheTwap(_INTERVAL, p2, t2);
        assertEq(cachedTwap, p1);

        vm.warp(t2 + 1200);

        cachedTwap = _testCachedTwap.cacheTwap(_INTERVAL, p2, t2);
        assertEq(cachedTwap, p2);
    }

    function test_revert_cacheTwap_when_same_timestamp_and_different_price() public {
        //           t1      t2
        //      -----+--------+------
        //              1200s
        // price:   100      120
        uint256 cachedTwap;

        uint256 t1 = _INIT_BLOCK_TIMESTAMP;
        uint256 p1 = 100 * 1e8;

        cachedTwap = _testCachedTwap.cacheTwap(_INTERVAL, p1, t1);
        assertEq(cachedTwap, p1);

        uint256 t2 = t1 + 1200;
        uint256 p2 = 120 * 1e8;
        vm.warp(t2);

        cachedTwap = _testCachedTwap.cacheTwap(_INTERVAL, p2, t2);
        assertEq(cachedTwap, p1);

        uint256 p3 = 140 * 1e8;
        vm.warp(t2 + 1200);

        vm.expectRevert(bytes("CT_IPWU"));
        _testCachedTwap.cacheTwap(_INTERVAL, p3, t2);
    }
}
