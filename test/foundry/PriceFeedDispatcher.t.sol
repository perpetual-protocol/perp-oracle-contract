pragma solidity 0.7.6;

import "forge-std/Test.sol";
import { UniswapV3Pool } from "@uniswap/v3-core/contracts/UniswapV3Pool.sol";
import { UniswapV3PriceFeed } from "../../contracts/UniswapV3PriceFeed.sol";
import { TestAggregatorV3 } from "../../contracts/test/TestAggregatorV3.sol";
import { ChainlinkPriceFeedV3 } from "../../contracts/ChainlinkPriceFeedV3.sol";
import { PriceFeedDispatcher } from "../../contracts/PriceFeedDispatcher.sol";

contract PriceFeedDispatcherSetup is Test {
    UniswapV3PriceFeed internal _uniswapV3PriceFeed;
    ChainlinkPriceFeedV3 internal _chainlinkPriceFeed;
    PriceFeedDispatcher internal _priceFeedDispatcher;

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
        return new PriceFeedDispatcher(address(_uniswapV3PriceFeed), address(_chainlinkPriceFeed));
    }
}

contract PriceFeedDispatcherConstructorTest is PriceFeedDispatcherSetup {
    function test_UniswapV3PriceFeed_can_be_zero_address() public {
        _priceFeedDispatcher = new PriceFeedDispatcher(address(0), address(_chainlinkPriceFeed));
    }

    function test_CPF_UECOU() public {
        vm.expectRevert(bytes("CPF_UECOU"));
        _priceFeedDispatcher = new PriceFeedDispatcher(makeAddr("HA"), address(_chainlinkPriceFeed));
    }

    function test_CPF_CNC() public {
        vm.expectRevert(bytes("CPF_CNC"));
        _priceFeedDispatcher = new PriceFeedDispatcher(address(_uniswapV3PriceFeed), address(0));
    }
}

contract PriceFeedDispatcherTest is PriceFeedDispatcherSetup {
    address public nonOwnerAddress = makeAddr("nonOwnerAddress");

    function setUp() public virtual override {
        PriceFeedDispatcherSetup.setUp();
        _priceFeedDispatcher = _create_PriceFeedDispatcher();
    }

    function test_setPriceFeedStatus() public {
        _priceFeedDispatcher.setPriceFeedStatus(PriceFeedDispatcher.Status.Chainlink);
        _priceFeedDispatcher.setPriceFeedStatus(PriceFeedDispatcher.Status.UniswapV3);
    }

    function test_cannot_setPriceFeedStatus_by_nonOwnerAddress() public {
        vm.expectRevert(bytes("Ownable: caller is not the owner"));
        vm.prank(nonOwnerAddress);
        _priceFeedDispatcher.setPriceFeedStatus(PriceFeedDispatcher.Status.Chainlink);
    }
}
