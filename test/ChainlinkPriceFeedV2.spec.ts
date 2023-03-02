import { MockContract, smock } from "@defi-wonderland/smock"
import { expect } from "chai"
import { BigNumber } from "ethers"
import { parseEther, parseUnits } from "ethers/lib/utils"
import { ethers, waffle } from "hardhat"
import { ChainlinkPriceFeedV2, TestAggregatorV3, TestAggregatorV3__factory } from "../typechain"
import { computeRoundId } from "./shared/chainlink"

interface ChainlinkPriceFeedFixture {
    chainlinkPriceFeed: ChainlinkPriceFeedV2
    aggregator: MockContract<TestAggregatorV3>
    chainlinkPriceFeed2: ChainlinkPriceFeedV2
    aggregator2: MockContract<TestAggregatorV3>
}

async function chainlinkPriceFeedFixture(): Promise<ChainlinkPriceFeedFixture> {
    const [admin] = await ethers.getSigners()
    const aggregatorFactory = await smock.mock<TestAggregatorV3__factory>("TestAggregatorV3", admin)
    const aggregator = await aggregatorFactory.deploy()
    aggregator.decimals.returns(() => 18)

    const chainlinkPriceFeedFactory = await ethers.getContractFactory("ChainlinkPriceFeedV2")
    const chainlinkPriceFeed = (await chainlinkPriceFeedFactory.deploy(aggregator.address, 900)) as ChainlinkPriceFeedV2

    const aggregatorFactory2 = await smock.mock<TestAggregatorV3__factory>("TestAggregatorV3", admin)
    const aggregator2 = await aggregatorFactory2.deploy()
    aggregator2.decimals.returns(() => 8)

    const chainlinkPriceFeedFactory2 = await ethers.getContractFactory("ChainlinkPriceFeedV2")
    const chainlinkPriceFeed2 = (await chainlinkPriceFeedFactory2.deploy(
        aggregator2.address,
        900,
    )) as ChainlinkPriceFeedV2

    return { chainlinkPriceFeed, aggregator, chainlinkPriceFeed2, aggregator2 }
}

describe("ChainlinkPriceFeedV2 Spec", () => {
    const [admin] = waffle.provider.getWallets()
    const loadFixture: ReturnType<typeof waffle.createFixtureLoader> = waffle.createFixtureLoader([admin])
    let chainlinkPriceFeed: ChainlinkPriceFeedV2
    let aggregator: MockContract<TestAggregatorV3>
    let priceFeedDecimals: number
    let chainlinkPriceFeed2: ChainlinkPriceFeedV2
    let aggregator2: MockContract<TestAggregatorV3>
    let priceFeedDecimals2: number

    beforeEach(async () => {
        const _fixture = await loadFixture(chainlinkPriceFeedFixture)
        chainlinkPriceFeed = _fixture.chainlinkPriceFeed
        aggregator = _fixture.aggregator
        priceFeedDecimals = await chainlinkPriceFeed.decimals()
        chainlinkPriceFeed2 = _fixture.chainlinkPriceFeed2
        aggregator2 = _fixture.aggregator2
        priceFeedDecimals2 = await chainlinkPriceFeed2.decimals()
    })

    describe("edge cases, have the same timestamp for several rounds", () => {
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
            await expect(chainlinkPriceFeed.update()).to.be.revertedWith("CPF_NU")
        })
    })

    describe("getRoundData", async () => {
        let currentTime: number

        beforeEach(async () => {
            currentTime = (await waffle.provider.getBlock("latest")).timestamp

            await aggregator2.setRoundData(
                computeRoundId(1, 1),
                parseUnits("1800", priceFeedDecimals2),
                BigNumber.from(currentTime),
                BigNumber.from(currentTime),
                computeRoundId(1, 1),
            )
            await aggregator2.setRoundData(
                computeRoundId(1, 2),
                parseUnits("1900", priceFeedDecimals2),
                BigNumber.from(currentTime + 15),
                BigNumber.from(currentTime + 15),
                computeRoundId(1, 2),
            )
            await aggregator2.setRoundData(
                computeRoundId(2, 10000),
                parseUnits("1700", priceFeedDecimals2),
                BigNumber.from(currentTime + 30),
                BigNumber.from(currentTime + 30),
                computeRoundId(2, 10000),
            )

            // updatedAt is 0 means the round is not complete and should not be used
            await aggregator2.setRoundData(
                computeRoundId(2, 20000),
                parseUnits("-0.1", priceFeedDecimals2),
                BigNumber.from(currentTime + 45),
                BigNumber.from(0),
                computeRoundId(2, 20000),
            )

            // updatedAt is 0 means the round is not complete and should not be used
            await aggregator2.setRoundData(
                computeRoundId(2, 20001),
                parseUnits("5000", priceFeedDecimals2),
                BigNumber.from(currentTime + 45),
                BigNumber.from(0),
                computeRoundId(2, 20001),
            )
        })

        it("computeRoundId", async () => {
            expect(computeRoundId(1, 1)).to.be.eq(await aggregator2.computeRoundId(1, 1))
            expect(computeRoundId(1, 2)).to.be.eq(await aggregator2.computeRoundId(1, 2))
            expect(computeRoundId(2, 10000)).to.be.eq(await aggregator2.computeRoundId(2, 10000))
        })

        it("getRoundData with valid roundId", async () => {
            expect(await chainlinkPriceFeed2.getRoundData(computeRoundId(1, 1))).to.be.deep.eq([
                parseUnits("1800", priceFeedDecimals2),
                BigNumber.from(currentTime),
            ])

            expect(await chainlinkPriceFeed2.getRoundData(computeRoundId(1, 2))).to.be.deep.eq([
                parseUnits("1900", priceFeedDecimals2),
                BigNumber.from(currentTime + 15),
            ])

            expect(await chainlinkPriceFeed2.getRoundData(computeRoundId(2, 10000))).to.be.deep.eq([
                parseUnits("1700", priceFeedDecimals2),
                BigNumber.from(currentTime + 30),
            ])
        })

        it("force error, getRoundData when price <= 0", async () => {
            // price < 0
            await expect(chainlinkPriceFeed2.getRoundData(computeRoundId(2, 20000))).to.be.revertedWith("CPF_IP")

            // price = 0
            await expect(chainlinkPriceFeed2.getRoundData("123")).to.be.revertedWith("CPF_IP")
        })

        it("force error, getRoundData when round is not complete", async () => {
            await expect(chainlinkPriceFeed2.getRoundData(computeRoundId(2, 20001))).to.be.revertedWith("CPF_RINC")
        })
    })

    it("getAggregator", async () => {
        expect(await chainlinkPriceFeed2.getAggregator()).to.be.eq(aggregator2.address)
    })
})
