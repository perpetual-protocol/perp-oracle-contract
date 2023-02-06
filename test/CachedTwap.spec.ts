import { expect } from "chai"
import { parseEther } from "ethers/lib/utils"
import { ethers, waffle } from "hardhat"
import { BandPriceFeed, ChainlinkPriceFeedV2, TestAggregatorV3, TestPriceFeedV2, TestStdReference } from "../typechain"

interface PriceFeedFixture {
    bandPriceFeed: BandPriceFeed
    bandReference: TestStdReference
    baseAsset: string

    chainlinkPriceFeed: ChainlinkPriceFeedV2
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

    const chainlinkPriceFeedFactory = await ethers.getContractFactory("ChainlinkPriceFeedV2")
    const chainlinkPriceFeed = (await chainlinkPriceFeedFactory.deploy(
        testAggregator.address,
        twapInterval,
    )) as ChainlinkPriceFeedV2

    return { bandPriceFeed, bandReference: testStdReference, baseAsset, chainlinkPriceFeed, aggregator: testAggregator }
}

describe("Cached Twap Spec", () => {
    const [admin] = waffle.provider.getWallets()
    const loadFixture: ReturnType<typeof waffle.createFixtureLoader> = waffle.createFixtureLoader([admin])
    let bandPriceFeed: BandPriceFeed
    let bandReference: TestStdReference
    let chainlinkPriceFeed: ChainlinkPriceFeedV2
    let aggregator: TestAggregatorV3
    let currentTime: number
    let testPriceFeed: TestPriceFeedV2
    let round: number

    async function setNextBlockTimestamp(timestamp: number) {
        await ethers.provider.send("evm_setNextBlockTimestamp", [timestamp])
        await ethers.provider.send("evm_mine", [])
    }

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
            await setNextBlockTimestamp(currentTime)
        }
    }

    beforeEach(async () => {
        const _fixture = await loadFixture(priceFeedFixture)
        bandReference = _fixture.bandReference
        bandPriceFeed = _fixture.bandPriceFeed
        chainlinkPriceFeed = _fixture.chainlinkPriceFeed
        aggregator = _fixture.aggregator
        round = 0

        const TestPriceFeedFactory = await ethers.getContractFactory("TestPriceFeedV2")
        testPriceFeed = (await TestPriceFeedFactory.deploy(
            chainlinkPriceFeed.address,
            bandPriceFeed.address,
        )) as TestPriceFeedV2

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
            // timestamp changes due to cacheTwap()
            await testPriceFeed.getPrice(45)

            const price2 = await chainlinkPriceFeed.callStatic.getPrice(45)
            expect(price1.cachedTwap).to.not.eq(price2)
        })

        it("re-calculate twap if block timestamp is different from last cached twap timestamp", async () => {
            const price1 = await testPriceFeed.callStatic.getPrice(45)
            await testPriceFeed.getPrice(45)

            // forword block timestamp 15sec
            currentTime += 15
            await setNextBlockTimestamp(currentTime)

            const price2 = await bandPriceFeed.getPrice(45)
            expect(price2).to.not.eq(price1.twap)
        })

        it("re-calculate twap if interval is different from interval of cached twap", async () => {
            await bandPriceFeed.cacheTwap(45)
            const price1 = await bandPriceFeed.getPrice(45)
            const price2 = await bandPriceFeed.getPrice(15)
            // shoule re-calculate twap
            expect(price2).to.not.eq(price1)
        })

        it("re-calculate twap if timestamp doesn't change", async () => {
            const price1 = await testPriceFeed.getPrice(45)

            // forword block timestamp 15sec
            currentTime += 15
            await setNextBlockTimestamp(currentTime)

            const price2 = await testPriceFeed.getPrice(45)
            expect(price2).to.not.eq(price1)
        })
    })
})
