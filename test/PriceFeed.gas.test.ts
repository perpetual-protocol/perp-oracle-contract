import { parseEther } from "ethers/lib/utils"
import { ethers, waffle } from "hardhat"
import { BandPriceFeed, ChainlinkPriceFeedV2, TestAggregatorV3, TestPriceFeedV2, TestStdReference } from "../typechain"

const twapInterval = 900
interface PriceFeedFixture {
    bandPriceFeed: BandPriceFeed
    bandReference: TestStdReference
    baseAsset: string

    chainlinkPriceFeed: ChainlinkPriceFeedV2
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

    return { bandPriceFeed, bandReference: testStdReference, baseAsset, chainlinkPriceFeed, aggregator: testAggregator }
}

describe.skip("Price feed gas test", () => {
    const [admin] = waffle.provider.getWallets()
    const loadFixture: ReturnType<typeof waffle.createFixtureLoader> = waffle.createFixtureLoader([admin])
    let bandPriceFeed: BandPriceFeed
    let bandReference: TestStdReference
    let chainlinkPriceFeed: ChainlinkPriceFeedV2
    let aggregator: TestAggregatorV3
    let currentTime: number
    let testPriceFeed: TestPriceFeedV2
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

        const TestPriceFeedFactory = await ethers.getContractFactory("TestPriceFeedV2")
        testPriceFeed = (await TestPriceFeedFactory.deploy(
            chainlinkPriceFeed.address,
            bandPriceFeed.address,
        )) as TestPriceFeedV2

        currentTime = (await waffle.provider.getBlock("latest")).timestamp
        for (let i = 0; i < 255; i++) {
            round = i
            await updatePrice(beginPrice + i)
        }
    })

    describe("900 seconds twapInterval", () => {
        it("band protocol ", async () => {
            await testPriceFeed.fetchBandProtocolPrice(twapInterval)
        })

        it("band protocol - cached", async () => {
            await testPriceFeed.cachedBandProtocolPrice(twapInterval)
        })

        it("chainlink", async () => {
            await testPriceFeed.fetchChainlinkPrice(twapInterval)
        })

        it("chainlink - cached", async () => {
            await testPriceFeed.cachedChainlinkPrice(twapInterval)
        })
    })
})
