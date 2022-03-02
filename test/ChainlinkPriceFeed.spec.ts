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
    const chainlinkPriceFeed = (await chainlinkPriceFeedFactory.deploy(aggregator.address)) as ChainlinkPriceFeed

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
        beforeEach(async () => {
            // `base` = now - _interval
            // aggregator's answer
            // timestamp(base + 0)  : 400
            // timestamp(base + 15) : 405
            // timestamp(base + 30) : 410
            // now = base + 45
            //
            //  --+------+-----+-----+-----+-----+-----+
            //          base                          now
            const latestTimestamp = (await waffle.provider.getBlock("latest")).timestamp
            currentTime = latestTimestamp
            roundData = [
                // [roundId, answer, startedAt, updatedAt, answeredInRound]
            ]

            await updatePrice(0, 400, false)
            await updatePrice(1, 405, false)
            await updatePrice(2, 410, false)
            // // have the same timestamp for rounds
            // roundData.push([0, parseEther("400"), currentTime, currentTime, 0])
            // roundData.push([1, parseEther("405"), currentTime, currentTime, 1])
            // roundData.push([2, parseEther("410"), currentTime, currentTime, 2])

            // aggregator.latestRoundData.returns(() => {
            //     return roundData[roundData.length - 1]
            // })
            // aggregator.getRoundData.returns(round => {
            //     return roundData[round]
            // })

            currentTime += 15
            await ethers.provider.send("evm_setNextBlockTimestamp", [currentTime])
            await ethers.provider.send("evm_mine", [])
        })

        it("get the latest price", async () => {
            const price = await chainlinkPriceFeed.getPrice(45)
            expect(price).to.eq(parseEther("410"))
        })

        it("asking interval more than aggregator has", async () => {
            const price = await chainlinkPriceFeed.getPrice(46)
            expect(price).to.eq(parseEther("410"))
        })
    })
})
