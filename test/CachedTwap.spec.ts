import { expect } from "chai"
import { parseEther } from "ethers/lib/utils"
import { ethers, waffle } from "hardhat"
import {
    BandPriceFeed,
    ChainlinkPriceFeedWithCachedTwap,
    TestAggregatorV3,
    TestPriceFeed,
    TestStdReference,
} from "../typechain"

interface PriceFeedFixture {
    bandPriceFeed: BandPriceFeed
    bandReference: TestStdReference
    baseAsset: string

    // chainlinik
    chainlinkPriceFeed: ChainlinkPriceFeedWithCachedTwap
    aggregator: TestAggregatorV3
}
async function priceFeedFixture(): Promise<PriceFeedFixture> {
    const twapInterval = 45
    // band protocol
    const testStdReferenceFactory = await ethers.getContractFactory("TestStdReference")
    const testStdReference = await testStdReferenceFactory.deploy()

    const baseAsset = "ETH"
    const bandPriceFeedFactory = await ethers.getContractFactory("BandPriceFeed")
    const bandPriceFeed = (await bandPriceFeedFactory.deploy(
        testStdReference.address,
        baseAsset,
        twapInterval,
    )) as BandPriceFeed

    // chainlink
    const testAggregatorFactory = await ethers.getContractFactory("TestAggregatorV3")
    const testAggregator = await testAggregatorFactory.deploy()

    const chainlinkPriceFeedFactory = await ethers.getContractFactory("ChainlinkPriceFeedWithCachedTwap")
    const chainlinkPriceFeed = (await chainlinkPriceFeedFactory.deploy(
        testAggregator.address,
        twapInterval,
    )) as ChainlinkPriceFeedWithCachedTwap

    return { bandPriceFeed, bandReference: testStdReference, baseAsset, chainlinkPriceFeed, aggregator: testAggregator }
}

describe("Cached Twap Spec", () => {
    const [admin] = waffle.provider.getWallets()
    const loadFixture: ReturnType<typeof waffle.createFixtureLoader> = waffle.createFixtureLoader([admin])
    let bandPriceFeed: BandPriceFeed
    let bandReference: TestStdReference
    let chainlinkPriceFeed: ChainlinkPriceFeedWithCachedTwap
    let aggregator: TestAggregatorV3
    let currentTime: number
    let testPriceFeed: TestPriceFeed
    let round: number

    async function updatePrice(price: number, forward: boolean = true): Promise<void> {
        await bandReference.setReferenceData({
            rate: parseEther(price.toString()),
            lastUpdatedBase: currentTime,
            lastUpdatedQuote: currentTime,
        })
        await bandPriceFeed.update()

        await aggregator.setRoundData(round, parseEther(price.toString()), currentTime, currentTime, round)
        await chainlinkPriceFeed.update()

        if (forward) {
            currentTime += 15
            await ethers.provider.send("evm_setNextBlockTimestamp", [currentTime])
            await ethers.provider.send("evm_mine", [])
        }
    }

    before(async () => {
        const _fixture = await loadFixture(priceFeedFixture)
        bandReference = _fixture.bandReference
        bandPriceFeed = _fixture.bandPriceFeed
        chainlinkPriceFeed = _fixture.chainlinkPriceFeed
        aggregator = _fixture.aggregator
        round = 0

        const TestPriceFeedFactory = await ethers.getContractFactory("TestPriceFeed")
        testPriceFeed = (await TestPriceFeedFactory.deploy(
            chainlinkPriceFeed.address,
            bandPriceFeed.address,
        )) as TestPriceFeed

        currentTime = (await waffle.provider.getBlock("latest")).timestamp
        await updatePrice(400)
        await updatePrice(405)
        await updatePrice(410)

        await bandReference.setReferenceData({
            rate: parseEther("415"),
            lastUpdatedBase: currentTime,
            lastUpdatedQuote: currentTime,
        })
    })

    describe("cacheTwap should be exactly the same getPrice()", () => {
        it("return latest price if interval is zero", async () => {
            const price = await testPriceFeed.callStatic.getPrice(0)
            expect(price.twap).to.eq(price.cachedTwap)
            expect(price.twap).to.eq(await bandPriceFeed.getPrice(0))
        })

        it("if cached twap found, twap price should equal cached twap", async () => {
            const price = await testPriceFeed.callStatic.getPrice(45)
            expect(price.twap).to.eq(price.cachedTwap)
            // `getPrice` here is no a view function, it mocked function in TestPriceFeed
            // and it will update the cache if necessary
            expect(price.twap).to.eq(await bandPriceFeed.getPrice(45))
        })

        it("if no cached twap found, twap price should equal cached twap", async () => {
            const price = await testPriceFeed.callStatic.getPrice(46)
            expect(price.twap).to.eq(price.cachedTwap)
            expect(price.twap).to.eq(await bandPriceFeed.getPrice(46))
        })

        it("re-calculate cached twap if timestamp moves", async () => {
            const price1 = await testPriceFeed.callStatic.getPrice(45)
            await testPriceFeed.getPrice(45)

            const price2 = await testPriceFeed.callStatic.getPrice(45)
            expect(price2.twap).to.eq(price2.cachedTwap)
            // `getPrice` here is no a view function, it mocked function in TestPriceFeed
            // and it will update the cache if necessary
            expect(price2.twap).to.eq(await bandPriceFeed.getPrice(45))

            expect(price1.cachedTwap).to.not.eq(price2.cachedTwap)
        })
    })
})
