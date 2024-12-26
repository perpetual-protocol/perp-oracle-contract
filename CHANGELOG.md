# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [unreleased]

## [0.6.8] - 2024-12-25
- check `startedAt > 0` in `ChainlinkPriceFeedV1R1.getPrice`

## [0.6.7] - 2023-05-05
- Add `IPriceFeedDispatcher.decimals` back for backward compatible.

## [0.6.6] - 2023-05-05
- Add `PriceFeedDispatcher.getPrice` for backward compatible.

## [0.6.5] - 2023-03-31
- Refine natspec

## [0.6.4] - 2023-03-30
- Rename `ChainlinkPriceFeedV3.getCachedTwap` to `ChainlinkPriceFeedV3.getPrice`.
- Rename `ChainlinkPriceFeedV3.getCachedPrice` to `ChainlinkPriceFeedV3.getLatestOrCachedPrice`.

## [0.6.3] - 2023-03-14
- Add `ChainlinkPriceFeedV3.getCachePrice` to fetch the latest valid price and updated timestamp.
- Add `ChainlinkPriceFeedV3.getTimeout` to get timeout config of ChainlinkPriceFeedV3.

## [0.6.2] - 2023-03-01
- `observations` extends to `1800` at `CumulativeTwap.sol` to support extreme circumstance.
- To better enhance above performance, we introduce binary search mimicked from https://github.com/Uniswap/v3-core/blob/05c10bf/contracts/libraries/Oracle.sol#L153.
- Remove `CT_NEH` from `CumulativeTwap.sol`. Won't be calculated if so. Simply return latest price at `CachedTwap.sol`.
- Fix imprecise TWAP calculation when historical data is not enough at `CumulativeTwap.sol`. Won't be calculated if so.

## [0.6.1] - 2023-03-01
- Fix cachedTwap won't be updated when latest updated timestamp not changed

## [0.6.0] - 2023-03-01
### Added
- Add `ChainlinkPriceFeedV3.sol` with better error handling when Chainlink is broken.
- Add `PriceFeedDispatcher.sol`, a proxy layer to fetch Chainlink or Uniswap's price.
- Add `UniswapV3PriceFeed.sol` to fetch a market TWAP with a hard coded time period.
- Update `CachedTwap.sol` and `CumulativeTwap.sol` to better support above fallbackable oracle

## [0.5.1] - 2023-02-07

- Add `ChainlinkPriceFeedV1R1`

## [0.5.0] - 2022-08-23

- Add `PriceFeedUpdater`

## [0.4.2] - 2022-06-08

- Add `ChainlinkPriceFeed.getRoundData()`

## [0.4.1] - 2022-05-24

- Fix `npm pack`

## [0.4.0] - 2022-05-24

- Add `ChainlinkPriceFeedV2`, which calculates the TWAP by cached TWAP
- Add the origin `ChainlinkPriceFeed` back, which calculates the TWAP by round data instead of cached TWAP

## [0.3.4] - 2022-04-01

- Add `cacheTwap(uint256)` to `IPriceFeed.sol` and `EmergencyPriceFeed.sol`
- Remove `ICachedTwap.sol`

## [0.3.3] - 2022-03-18

- Refactor `ChainlinkPriceFeed`, `BandPriceFeed`, and `EmergencyPriceFeed` with efficient TWAP calculation.
- Change the license to `GPL-3.0-or-later`.

## [0.3.2] - 2022-03-04

- Using cumulative twap in Chainlink price feed

## [0.3.0] - 2022-02-07

- Add `EmergencyPriceFeed`

## [0.2.2] - 2021-12-28

- `BandPriceFeed` will revert if price not updated yet

## [0.2.1] - 2021-12-24

- Fix `BandPriceFeed` when the price feed haven't updated

## [0.2.0] - 2021-12-21

- Add `BandPriceFeed`
