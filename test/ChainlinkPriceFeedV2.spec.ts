import { MockContract, smock } from "@defi-wonderland/smock"
import { expect } from "chai"
import { parseEther } from "ethers/lib/utils"
import { ethers, waffle } from "hardhat"
import { ChainlinkPriceFeedV2, TestAggregatorV3, TestAggregatorV3__factory } from "../typechain"

interface ChainlinkPriceFeedFixture {
    chainlinkPriceFeed: ChainlinkPriceFeedV2
    aggregator: MockContract<TestAggregatorV3>
}

async function chainlinkPriceFeedFixture(): Promise<ChainlinkPriceFeedFixture> {
    const aggregatorFactory = await smock.mock<TestAggregatorV3__factory>("TestAggregatorV3")
    const aggregator = await aggregatorFactory.deploy()
    aggregator.decimals.returns(() => 18)

    const chainlinkPriceFeedFactory = await ethers.getContractFactory("ChainlinkPriceFeedV2")
    const chainlinkPriceFeed = (await chainlinkPriceFeedFactory.deploy(aggregator.address, 900)) as ChainlinkPriceFeedV2

    return { chainlinkPriceFeed, aggregator }
}

describe("ChainlinkPriceFeedV2 Spec", () => {
    const [admin] = waffle.provider.getWallets()
    const loadFixture: ReturnType<typeof waffle.createFixtureLoader> = waffle.createFixtureLoader([admin])
    let chainlinkPriceFeed: ChainlinkPriceFeedV2
    let aggregator: MockContract<TestAggregatorV3>
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

            // update without forward timestamp
            await updatePrice(0, 400, false)
            await expect(chainlinkPriceFeed.update()).to.be.revertedWith("CT_IT")
        })
    })
})
