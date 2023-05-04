pragma solidity 0.7.6;

import "forge-std/Test.sol";
import { IUniswapV3PriceFeed } from "../../contracts/interface/IUniswapV3PriceFeed.sol";
import { UniswapV3Pool } from "@uniswap/v3-core/contracts/UniswapV3Pool.sol";
import { UniswapV3PriceFeed } from "../../contracts/UniswapV3PriceFeed.sol";
import { TestAggregatorV3 } from "../../contracts/test/TestAggregatorV3.sol";
import { ChainlinkPriceFeedV3 } from "../../contracts/ChainlinkPriceFeedV3.sol";
import { PriceFeedDispatcher } from "../../contracts/PriceFeedDispatcher.sol";
import { IPriceFeedDispatcherEvent } from "../../contracts/interface/IPriceFeedDispatcher.sol";

contract PriceFeedDispatcherMocked is PriceFeedDispatcher {
    constructor(address chainlinkPriceFeedV3) PriceFeedDispatcher(chainlinkPriceFeedV3) {}

    function setPriceFeedStatus(Status status) external {
        _status = status;
    }

    function getStatus() external view returns (Status) {
        return _status;
    }
}

contract PriceFeedDispatcherSetup is Test {
    UniswapV3PriceFeed internal _uniswapV3PriceFeed;
    ChainlinkPriceFeedV3 internal _chainlinkPriceFeed;
    PriceFeedDispatcherMocked internal _priceFeedDispatcher;
    PriceFeedDispatcherMocked internal _priceFeedDispatcherWithUniswapV3PriceFeedUninitialized;

    function setUp() public virtual {
        _uniswapV3PriceFeed = _create_uniswapV3PriceFeed();
        _chainlinkPriceFeed = _create_ChainlinkPriceFeedV3();
    }

    function _create_uniswapV3PriceFeed() internal returns (UniswapV3PriceFeed) {
        TestAggregatorV3 aggregator = new TestAggregatorV3();
        // UniswapV3PriceFeed needs only a contract address
        return new UniswapV3PriceFeed(address(aggregator));
    }

    function _create_ChainlinkPriceFeedV3() internal returns (ChainlinkPriceFeedV3) {
        TestAggregatorV3 aggregator = new TestAggregatorV3();
        vm.mockCall(address(aggregator), abi.encodeWithSelector(aggregator.decimals.selector), abi.encode(8));

        return new ChainlinkPriceFeedV3(aggregator, 1, 1);
    }

    function _create_PriceFeedDispatcher() internal returns (PriceFeedDispatcherMocked) {
        return new PriceFeedDispatcherMocked(address(_chainlinkPriceFeed));
    }

    function _create_PriceFeedDispatcher_and_setUniswapV3PriceFeed() internal returns (PriceFeedDispatcherMocked) {
        PriceFeedDispatcherMocked priceFeedDispatcher = _create_PriceFeedDispatcher();
        priceFeedDispatcher.setUniswapV3PriceFeed(address(_uniswapV3PriceFeed));
        return priceFeedDispatcher;
    }
}

contract PriceFeedDispatcherConstructorAndSetterTest is IPriceFeedDispatcherEvent, PriceFeedDispatcherSetup {
    function test_PFD_CNC() public {
        vm.expectRevert(bytes("PFD_CNC"));
        _priceFeedDispatcher = new PriceFeedDispatcherMocked(address(0));

        vm.expectRevert(bytes("PFD_CNC"));
        _priceFeedDispatcher = new PriceFeedDispatcherMocked(makeAddr("HA"));
    }

    function test_PFD_UCAU() public {
        _priceFeedDispatcher = _create_PriceFeedDispatcher();

        vm.expectRevert(bytes("PFD_UCAU"));
        _priceFeedDispatcher.setUniswapV3PriceFeed(address(0));

        vm.expectRevert(bytes("PFD_UCAU"));
        _priceFeedDispatcher.setUniswapV3PriceFeed(makeAddr("HA"));
    }

    function test_cannot_setUniswapV3PriceFeed_by_non_owner() public {
        _priceFeedDispatcher = _create_PriceFeedDispatcher();

        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(makeAddr("HA"));
        _priceFeedDispatcher.setUniswapV3PriceFeed(address(_uniswapV3PriceFeed));
    }

    function test_setUniswapV3PriceFeed_should_emit_event() public {
        _priceFeedDispatcher = _create_PriceFeedDispatcher();

        vm.expectEmit(false, false, false, true, address(_priceFeedDispatcher));
        emit UniswapV3PriceFeedUpdated(address(_uniswapV3PriceFeed));
        _priceFeedDispatcher.setUniswapV3PriceFeed(address(_uniswapV3PriceFeed));
    }
}

contract PriceFeedDispatcherTest is IPriceFeedDispatcherEvent, PriceFeedDispatcherSetup {
    address public nonOwnerAddress = makeAddr("nonOwnerAddress");
    uint256 internal _chainlinkPrice = 100 * 1e18;
    uint256 internal _uniswapPrice = 50 * 1e18;

    function setUp() public virtual override {
        PriceFeedDispatcherSetup.setUp();
        _priceFeedDispatcher = _create_PriceFeedDispatcher_and_setUniswapV3PriceFeed();
        _priceFeedDispatcherWithUniswapV3PriceFeedUninitialized = _create_PriceFeedDispatcher();

        vm.mockCall(
            address(_uniswapV3PriceFeed),
            abi.encodeWithSelector(_uniswapV3PriceFeed.getPrice.selector),
            abi.encode(50 * 1e8)
        );

        vm.mockCall(
            address(_uniswapV3PriceFeed),
            abi.encodeWithSelector(_uniswapV3PriceFeed.decimals.selector),
            abi.encode(8)
        );

        vm.mockCall(
            address(_chainlinkPriceFeed),
            abi.encodeWithSelector(_chainlinkPriceFeed.getPrice.selector),
            abi.encode(100 * 1e8)
        );
    }

    function test_dispatchPrice_not_isToUseUniswapV3PriceFeed() public {
        assertEq(uint256(_priceFeedDispatcher.getStatus()), uint256(Status.Chainlink));
        assertEq(_priceFeedDispatcher.isToUseUniswapV3PriceFeed(), false);
        _dispatchPrice_and_assertEq_getDispatchedPrice(_chainlinkPrice);
    }

    function test_dispatchPrice_isToUseUniswapV3PriceFeed_when__status_is_already_UniswapV3() public {
        _priceFeedDispatcher.setPriceFeedStatus(Status.UniswapV3);

        _dispatchPrice_and_assertEq_getDispatchedPrice(_uniswapPrice);
        assertEq(uint256(_priceFeedDispatcher.getStatus()), uint256(Status.UniswapV3));
    }

    function test_dispatchPrice_isToUseUniswapV3PriceFeed_when_different__chainlinkPriceFeed_isTimedOut() public {
        vm.mockCall(
            address(_chainlinkPriceFeed),
            abi.encodeWithSelector(_chainlinkPriceFeed.isTimedOut.selector),
            abi.encode(true)
        );
        assertEq(_priceFeedDispatcher.isToUseUniswapV3PriceFeed(), true);

        _expect_emit_event_from_PriceFeedDispatcher();
        emit StatusUpdated(Status.UniswapV3);
        _dispatchPrice_and_assertEq_getDispatchedPrice(_uniswapPrice);
        assertEq(uint256(_priceFeedDispatcher.getStatus()), uint256(Status.UniswapV3));
        assertEq(_priceFeedDispatcher.isToUseUniswapV3PriceFeed(), true);

        // similar to the above case, if the status is already UniswapV3, then even if ChainlinkPriceFeed !isTimedOut,
        // isToUseUniswapV3PriceFeed() will still be true
        vm.mockCall(
            address(_chainlinkPriceFeed),
            abi.encodeWithSelector(_chainlinkPriceFeed.isTimedOut.selector),
            abi.encode(false)
        );
        assertEq(_priceFeedDispatcher.isToUseUniswapV3PriceFeed(), true);
    }

    function test_dispatchPrice_not_isToUseUniswapV3PriceFeed_when__uniswapV3PriceFeed_uninitialized() public {
        _priceFeedDispatcherWithUniswapV3PriceFeedUninitialized.dispatchPrice(0);
        assertEq(_priceFeedDispatcherWithUniswapV3PriceFeedUninitialized.getDispatchedPrice(0), _chainlinkPrice);
        assertEq(
            uint256(_priceFeedDispatcherWithUniswapV3PriceFeedUninitialized.getStatus()),
            uint256(Status.Chainlink)
        );
        assertEq(_priceFeedDispatcherWithUniswapV3PriceFeedUninitialized.isToUseUniswapV3PriceFeed(), false);

        vm.mockCall(
            address(_chainlinkPriceFeed),
            abi.encodeWithSelector(_chainlinkPriceFeed.isTimedOut.selector),
            abi.encode(true)
        );
        assertEq(_priceFeedDispatcherWithUniswapV3PriceFeedUninitialized.getDispatchedPrice(0), _chainlinkPrice);
        assertEq(_priceFeedDispatcherWithUniswapV3PriceFeedUninitialized.isToUseUniswapV3PriceFeed(), false);
    }

    function _dispatchPrice_and_assertEq_getDispatchedPrice(uint256 price) internal {
        _priceFeedDispatcher.dispatchPrice(0);
        assertEq(_priceFeedDispatcher.getDispatchedPrice(0), price);
        assertEq(_priceFeedDispatcher.getPrice(0), price);
    }

    function _expect_emit_event_from_PriceFeedDispatcher() internal {
        vm.expectEmit(false, false, false, true, address(_priceFeedDispatcher));
    }
}
