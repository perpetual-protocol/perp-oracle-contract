import { FakeContract, smock } from "@defi-wonderland/smock"
import { expect } from "chai"
import { parseEther } from "ethers/lib/utils"
import { ethers, waffle } from "hardhat"
import { ChainlinkPriceFeed, TestAggregatorV3 } from "../typechain"

interface ChainlinkPriceFeedFixture {
    chainlinkPriceFeed: ChainlinkPriceFeed
    aggregator: FakeContract<TestAggregatorV3>
}

async function chainlinkPriceFeedFixture(): Promise<ChainlinkPriceFeedFixture> {
    const aggregator = await smock.fake<TestAggregatorV3>("TestAggregatorV3")
    aggregator.decimals.returns(() => 18)

    const chainlinkPriceFeedFactory = await ethers.getContractFactory("ChainlinkPriceFeed")
    const chainlinkPriceFeed = (await chainlinkPriceFeedFactory.deploy(aggregator.address, 900)) as ChainlinkPriceFeed

    return { chainlinkPriceFeed, aggregator }
}

describe("ChainlinkPriceFeed Spec", () => {
    const [admin] = waffle.provider.getWallets()
    const loadFixture: ReturnType<typeof waffle.createFixtureLoader> = waffle.createFixtureLoader([admin])
    let chainlinkPriceFeed: ChainlinkPriceFeed
    let aggregator: FakeContract<TestAggregatorV3>
    let currentTime: number
    let roundData: any[]

    async function updatePrice(index: number, price: number, forward: boolean = true): Promise<void> {
        roundData.push([index, parseEther(price.toString()), currentTime, currentTime, index])
        aggregator.latestRoundData.returns(() => {
            return roundData[roundData.length - 1]
        })
        await chainlinkPriceFeed.update()

        if (forward) {
            currentTime += 15
            await ethers.provider.send("evm_setNextBlockTimestamp", [currentTime])
            await ethers.provider.send("evm_mine", [])
        }
    }

    beforeEach(async () => {
        const _fixture = await loadFixture(chainlinkPriceFeedFixture)
        chainlinkPriceFeed = _fixture.chainlinkPriceFeed
        aggregator = _fixture.aggregator
    })

    describe("edge cases, have the same timestamp for several rounds", () => {
        it("force error, can't update if timestamp is the same", async () => {
            currentTime = (await waffle.provider.getBlock("latest")).timestamp
            roundData = [
                // [roundId, answer, startedAt, updatedAt, answeredInRound]
            ]
            // set first round data
            roundData.push([0, parseEther("399"), currentTime, currentTime, 0])
            aggregator.latestRoundData.returns(() => {
                return roundData[roundData.length - 1]
            })
            expect(await chainlinkPriceFeed.isUpdatable()).to.be.eq(true)

            // update without forward timestamp
            await updatePrice(0, 400, false)
            await expect(await chainlinkPriceFeed.isUpdatable()).to.be.eq(false)
            await expect(chainlinkPriceFeed.update()).to.be.revertedWith("CT_IT")
        })
    })
})
