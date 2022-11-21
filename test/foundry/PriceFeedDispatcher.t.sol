pragma solidity 0.7.6;

import "forge-std/Test.sol";
import { UniswapV3Pool } from "@uniswap/v3-core/contracts/UniswapV3Pool.sol";
import { UniswapV3PriceFeed } from "../../contracts/UniswapV3PriceFeed.sol";
import { TestAggregatorV3 } from "../../contracts/test/TestAggregatorV3.sol";
import { ChainlinkPriceFeedV3 } from "../../contracts/ChainlinkPriceFeedV3.sol";
import { PriceFeedDispatcher } from "../../contracts/PriceFeedDispatcher.sol";
import { IPriceFeedDispatcherEvent } from "../../contracts/interface/IPriceFeedDispatcher.sol";

contract PriceFeedDispatcherSetup is Test {
    UniswapV3PriceFeed internal _uniswapV3PriceFeed;
    ChainlinkPriceFeedV3 internal _chainlinkPriceFeed;
    PriceFeedDispatcher internal _priceFeedDispatcher;
    PriceFeedDispatcher internal _priceFeedDispatcherUniswapV3PriceFeedNotExist;

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

        return new ChainlinkPriceFeedV3(aggregator, 1, 1, 1, 1);
    }

    function _create_PriceFeedDispatcher() internal returns (PriceFeedDispatcher) {
        return new PriceFeedDispatcher(_uniswapV3PriceFeed, _chainlinkPriceFeed);
    }

    function _create_PriceFeedDispatcherUniswapV3PriceFeedNotExist() internal returns (PriceFeedDispatcher) {
        return new PriceFeedDispatcher(UniswapV3PriceFeed(0), _chainlinkPriceFeed);
    }
}

contract PriceFeedDispatcherConstructorTest is PriceFeedDispatcherSetup {
    function test_UniswapV3PriceFeed_can_be_zero_address() public {
        _priceFeedDispatcher = _create_PriceFeedDispatcherUniswapV3PriceFeedNotExist();
    }

    function test_PFD_UECOU() public {
        vm.expectRevert(bytes("PFD_UECOU"));
        _priceFeedDispatcher = new PriceFeedDispatcher(UniswapV3PriceFeed(makeAddr("HA")), _chainlinkPriceFeed);
    }

    function test_PFD_CNC() public {
        vm.expectRevert(bytes("PFD_CNC"));
        _priceFeedDispatcher = new PriceFeedDispatcher(_uniswapV3PriceFeed, ChainlinkPriceFeedV3(0));
    }
}

contract PriceFeedDispatcherTest is IPriceFeedDispatcherEvent, PriceFeedDispatcherSetup {
    address public nonOwnerAddress = makeAddr("nonOwnerAddress");
    uint256 internal _chainlinkPrice = 100 * 1e18;
    uint256 internal _uniswapPrice = 50 * 1e18;

    function setUp() public virtual override {
        PriceFeedDispatcherSetup.setUp();
        _priceFeedDispatcher = _create_PriceFeedDispatcher();
        _priceFeedDispatcherUniswapV3PriceFeedNotExist = _create_PriceFeedDispatcherUniswapV3PriceFeedNotExist();

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
            abi.encodeWithSelector(_chainlinkPriceFeed.getCachedTwap.selector),
            abi.encode(100 * 1e8)
        );
    }

    function test_setPriceFeedStatus() public {
        _expect_emit_event_from_PriceFeedDispatcher();
        emit StatusUpdated(Status.Chainlink);
        _priceFeedDispatcher.setPriceFeedStatus(Status.Chainlink);
        assertEq(uint256(_priceFeedDispatcher.getStatus()), uint256(Status.Chainlink));

        emit StatusUpdated(Status.UniswapV3);
        _priceFeedDispatcher.setPriceFeedStatus(Status.UniswapV3);
        assertEq(uint256(_priceFeedDispatcher.getStatus()), uint256(Status.UniswapV3));
    }

    function test_cannot_setPriceFeedStatus_by_nonOwnerAddress() public {
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(nonOwnerAddress);
        _priceFeedDispatcher.setPriceFeedStatus(Status.UniswapV3);
    }

    function test_cannot_setPriceFeedStatus_when__uniswapV3PriceFeed_not_exist() public {
        vm.expectRevert(bytes("PFD_UU"));
        _priceFeedDispatcherUniswapV3PriceFeedNotExist.setPriceFeedStatus(Status.UniswapV3);
    }

    function test_dispatchPrice_not__isToUseUniswapV3PriceFeed() public {
        assertEq(uint256(_priceFeedDispatcher.getStatus()), uint256(Status.Chainlink));
        _dispatchPrice_and_assertEq_getDispatchedPrice(_chainlinkPrice);
    }

    function test_dispatchPrice__isToUseUniswapV3PriceFeed_when__chainlinkPriceFeed_isTimedOut() public {
        vm.mockCall(
            address(_chainlinkPriceFeed),
            abi.encodeWithSelector(_chainlinkPriceFeed.isTimedOut.selector),
            abi.encode(true)
        );

        _expect_emit_event_from_PriceFeedDispatcher();
        emit StatusUpdated(Status.UniswapV3);
        _dispatchPrice_and_assertEq_getDispatchedPrice(_uniswapPrice);
        assertEq(uint256(_priceFeedDispatcher.getStatus()), uint256(Status.UniswapV3));
    }

    function test_dispatchPrice__isToUseUniswapV3PriceFeed_when__status_is_already_UniswapV3() public {
        _priceFeedDispatcher.setPriceFeedStatus(Status.UniswapV3);

        _dispatchPrice_and_assertEq_getDispatchedPrice(_uniswapPrice);
        assertEq(uint256(_priceFeedDispatcher.getStatus()), uint256(Status.UniswapV3));
    }

    function test_dispatchPrice_not__isToUseUniswapV3PriceFeed_when__uniswapV3PriceFeed_not_exist() public {
        _priceFeedDispatcherUniswapV3PriceFeedNotExist.dispatchPrice(0);
        assertEq(_priceFeedDispatcherUniswapV3PriceFeedNotExist.getDispatchedPrice(0), _chainlinkPrice);
        assertEq(uint256(_priceFeedDispatcherUniswapV3PriceFeedNotExist.getStatus()), uint256(Status.Chainlink));

        vm.mockCall(
            address(_chainlinkPriceFeed),
            abi.encodeWithSelector(_chainlinkPriceFeed.isTimedOut.selector),
            abi.encode(true)
        );
        assertEq(_priceFeedDispatcherUniswapV3PriceFeedNotExist.getDispatchedPrice(0), _chainlinkPrice);
    }

    function _dispatchPrice_and_assertEq_getDispatchedPrice(uint256 price) internal {
        _priceFeedDispatcher.dispatchPrice(0);
        assertEq(_priceFeedDispatcher.getDispatchedPrice(0), price);
    }

    function _expect_emit_event_from_PriceFeedDispatcher() internal {
        vm.expectEmit(false, false, false, true, address(_priceFeedDispatcher));
    }
}
