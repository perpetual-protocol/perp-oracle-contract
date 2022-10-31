import { parseEther } from "ethers/lib/utils"
import { ethers, waffle } from "hardhat"
import {
    BandPriceFeed,
    ChainlinkPriceFeed,
    ChainlinkPriceFeedV2,
    TestAggregatorV3,
    TestPriceFeed,
    TestStdReference,
} from "../typechain"

const twapInterval = 900

interface PriceFeedFixture {
    bandPriceFeed: BandPriceFeed
    bandReference: TestStdReference
    baseAsset: string

    // chainlinik
    chainlinkPriceFeed: ChainlinkPriceFeedV2
    chainlinkPriceFeedV1: ChainlinkPriceFeed
    aggregator: TestAggregatorV3
}

async function priceFeedFixture(): Promise<PriceFeedFixture> {
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

    const chainlinkPriceFeedFactoryV1 = await ethers.getContractFactory("ChainlinkPriceFeed")
    const chainlinkPriceFeedV1 = (await chainlinkPriceFeedFactoryV1.deploy(
        testAggregator.address,
    )) as ChainlinkPriceFeed

    return {
        bandPriceFeed,
        bandReference: testStdReference,
        baseAsset,
        chainlinkPriceFeed,
        chainlinkPriceFeedV1,
        aggregator: testAggregator,
    }
}

describe("Price feed gas test", () => {
    const [admin] = waffle.provider.getWallets()
    const loadFixture: ReturnType<typeof waffle.createFixtureLoader> = waffle.createFixtureLoader([admin])
    let bandPriceFeed: BandPriceFeed
    let bandReference: TestStdReference
    let chainlinkPriceFeed: ChainlinkPriceFeedV2
    let chainlinkPriceFeedV1: ChainlinkPriceFeed
    let aggregator: TestAggregatorV3
    let currentTime: number
    let testPriceFeed: TestPriceFeed
    let beginPrice = 400
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
            // assume that every 10s price get updated
            currentTime += 10
            await ethers.provider.send("evm_setNextBlockTimestamp", [currentTime])
            await ethers.provider.send("evm_mine", [])
        }
    }

    before(async () => {
        const _fixture = await loadFixture(priceFeedFixture)
        bandReference = _fixture.bandReference
        bandPriceFeed = _fixture.bandPriceFeed
        chainlinkPriceFeed = _fixture.chainlinkPriceFeed
        chainlinkPriceFeedV1 = _fixture.chainlinkPriceFeedV1
        aggregator = _fixture.aggregator
        round = 0

        const TestPriceFeedFactory = await ethers.getContractFactory("TestPriceFeed")
        testPriceFeed = (await TestPriceFeedFactory.deploy(
            chainlinkPriceFeedV1.address,
            chainlinkPriceFeed.address,
            bandPriceFeed.address,
        )) as TestPriceFeed

        currentTime = (await waffle.provider.getBlock("latest")).timestamp
        for (let i = 0; i < 255; i++) {
            round = i
            await updatePrice(beginPrice + i)
        }
    })

    describe.skip("900 seconds twapInterval", () => {
        it.skip("band protocol ", async () => {
            await testPriceFeed.fetchBandProtocolPrice(twapInterval)
        })

        it.skip("band protocol - cached", async () => {
            await testPriceFeed.cachedBandProtocolPrice(twapInterval)
        })

        it("chainlink", async () => {
            await testPriceFeed.fetchChainlinkV2Price(twapInterval)
        })

        it("chainlinkv1", async () => {
            await testPriceFeed.fetchChainlinkV1Price(twapInterval)
        })

        it("chainlink - cached", async () => {
            await aggregator.setRoundData(round, parseEther("400"), currentTime, currentTime, ++round)
            await ethers.provider.send("evm_setNextBlockTimestamp", [currentTime + 15])
            await ethers.provider.send("evm_mine", [currentTime + 15])
            await testPriceFeed.cachedChainlinkV2PriceWithoutTry(twapInterval)
            await testPriceFeed.cachedChainlinkV2Price(twapInterval)
        })
    })
})
