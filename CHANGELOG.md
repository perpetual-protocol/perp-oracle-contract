# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [unreleased]
- Fix cachedTwap won't be updated when latest updated timestamp not changed

## [0.6.0] - TBD
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
