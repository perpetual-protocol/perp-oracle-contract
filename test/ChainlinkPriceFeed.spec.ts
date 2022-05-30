import { MockContract, smock } from "@defi-wonderland/smock"
import { expect } from "chai"
import { BigNumber } from "ethers"
import { parseEther, parseUnits } from "ethers/lib/utils"
import { ethers, waffle } from "hardhat"
import { ChainlinkPriceFeed, TestAggregatorV3, TestAggregatorV3__factory } from "../typechain"

interface ChainlinkPriceFeedFixture {
    chainlinkPriceFeed: ChainlinkPriceFeed
    aggregator: MockContract<TestAggregatorV3>
}

async function chainlinkPriceFeedFixture(): Promise<ChainlinkPriceFeedFixture> {
    const aggregatorFactory = await smock.mock<TestAggregatorV3__factory>("TestAggregatorV3")
    const aggregator = await aggregatorFactory.deploy()
    aggregator.decimals.returns(() => 18)

    const chainlinkPriceFeedFactory = await ethers.getContractFactory("ChainlinkPriceFeed")
    const chainlinkPriceFeed = (await chainlinkPriceFeedFactory.deploy(aggregator.address)) as ChainlinkPriceFeed

    return { chainlinkPriceFeed, aggregator }
}

function computeRoundId(phaseId: number, aggregatorRoundId: number): string {
    const roundId = (BigInt(phaseId) << BigInt("64")) | BigInt(aggregatorRoundId)
    return roundId.toString()
}

describe("ChainlinkPriceFeed Spec", () => {
    const [admin] = waffle.provider.getWallets()
    const loadFixture: ReturnType<typeof waffle.createFixtureLoader> = waffle.createFixtureLoader([admin])
    let chainlinkPriceFeed: ChainlinkPriceFeed
    let aggregator: MockContract<TestAggregatorV3>
    let currentTime: number
    let roundData: any[]

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

            // have the same timestamp for rounds
            roundData.push([0, parseEther("400"), currentTime, currentTime, 0])
            roundData.push([1, parseEther("405"), currentTime, currentTime, 1])
            roundData.push([2, parseEther("410"), currentTime, currentTime, 2])

            aggregator.latestRoundData.returns(() => {
                return roundData[roundData.length - 1]
            })
            aggregator.getRoundData.returns(round => {
                return roundData[round]
            })

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

    describe("twap", () => {
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

            currentTime += 0
            roundData.push([0, parseEther("400"), currentTime, currentTime, 0])

            currentTime += 15
            roundData.push([1, parseEther("405"), currentTime, currentTime, 1])

            currentTime += 15
            roundData.push([2, parseEther("410"), currentTime, currentTime, 2])

            aggregator.latestRoundData.returns(() => {
                return roundData[roundData.length - 1]
            })
            aggregator.getRoundData.returns(round => {
                return roundData[round]
            })

            currentTime += 15
            await ethers.provider.send("evm_setNextBlockTimestamp", [currentTime])
            await ethers.provider.send("evm_mine", [])
        })

        it("twap price", async () => {
            const price = await chainlinkPriceFeed.getPrice(45)
            expect(price).to.eq(parseEther("405"))
        })

        it("asking interval more than aggregator has", async () => {
            const price = await chainlinkPriceFeed.getPrice(46)
            expect(price).to.eq(parseEther("405"))
        })

        it("asking interval less than aggregator has", async () => {
            const price = await chainlinkPriceFeed.getPrice(44)
            expect(price).to.eq("405113636363636363636")
        })

        it("given variant price period", async () => {
            roundData.push([4, parseEther("420"), currentTime + 30, currentTime + 30, 4])
            await ethers.provider.send("evm_setNextBlockTimestamp", [currentTime + 50])
            await ethers.provider.send("evm_mine", [])
            // twap price should be ((400 * 15) + (405 * 15) + (410 * 45) + (420 * 20)) / 95 = 409.736
            const price = await chainlinkPriceFeed.getPrice(95)
            expect(price).to.eq("409736842105263157894")
        })

        it("latest price update time is earlier than the request, return the latest price", async () => {
            await ethers.provider.send("evm_setNextBlockTimestamp", [currentTime + 100])
            await ethers.provider.send("evm_mine", [])

            // latest update time is base + 30, but now is base + 145 and asking for (now - 45)
            // should return the latest price directly
            const price = await chainlinkPriceFeed.getPrice(45)
            expect(price).to.eq(parseEther("410"))
        })

        it("if current price < 0, ignore the current price", async () => {
            roundData.push([3, parseEther("-10"), 250, 250, 3])
            const price = await chainlinkPriceFeed.getPrice(45)
            expect(price).to.eq(parseEther("405"))
        })

        it("if there is a negative price in the middle, ignore that price", async () => {
            roundData.push([3, parseEther("-100"), currentTime + 20, currentTime + 20, 3])
            roundData.push([4, parseEther("420"), currentTime + 30, currentTime + 30, 4])
            await ethers.provider.send("evm_setNextBlockTimestamp", [currentTime + 50])
            await ethers.provider.send("evm_mine", [])

            // twap price should be ((400 * 15) + (405 * 15) + (410 * 45) + (420 * 20)) / 95 = 409.736
            const price = await chainlinkPriceFeed.getPrice(95)
            expect(price).to.eq("409736842105263157894")
        })

        it("return latest price if interval is zero", async () => {
            const price = await chainlinkPriceFeed.getPrice(0)
            expect(price).to.eq(parseEther("410"))
        })
    })

    it("getAggregator", async () => {
        expect(await chainlinkPriceFeed.getAggregator()).to.be.eq(aggregator.address)
    })

    describe("getRoundData", async () => {
        let priceFeedDecimals: number
        let timestamp: number
        let roundDataMap: Record<string, any>

        beforeEach(async () => {
            priceFeedDecimals = await chainlinkPriceFeed.decimals()
            timestamp = (await waffle.provider.getBlock("latest")).timestamp

            roundDataMap = {
                // "roundId": [roundId, answer, startedAt, updatedAt, answeredInRound]
                [computeRoundId(1, 1)]: [
                    computeRoundId(1, 1),
                    parseUnits("1800", priceFeedDecimals),
                    BigNumber.from(timestamp),
                    BigNumber.from(timestamp),
                    computeRoundId(1, 1),
                ],
                [computeRoundId(1, 2)]: [
                    computeRoundId(1, 2),
                    parseUnits("1900", priceFeedDecimals),
                    BigNumber.from(timestamp + 15),
                    BigNumber.from(timestamp + 15),
                    computeRoundId(1, 2),
                ],
                [computeRoundId(2, 10000)]: [
                    computeRoundId(2, 10000),
                    parseUnits("1700", priceFeedDecimals),
                    BigNumber.from(timestamp + 30),
                    BigNumber.from(timestamp + 30),
                    computeRoundId(2, 10000),
                ],
            }

            aggregator.getRoundData.returns(roundId => {
                return roundDataMap[roundId]
                    ? roundDataMap[roundId]
                    : [computeRoundId(100, 100), 0, 0, 0, computeRoundId(100, 100)]
            })
        })

        it("computeRoundId", async () => {
            expect(computeRoundId(1, 1)).to.be.eq(await aggregator.computeRoundId(1, 1))
            expect(computeRoundId(1, 2)).to.be.eq(await aggregator.computeRoundId(1, 2))
            expect(computeRoundId(2, 10000)).to.be.eq(await aggregator.computeRoundId(2, 10000))
        })

        it("getRoundData with valid roundId", async () => {
            // TODO: not sure why expect(res).to.be.deep.eq([xxx, xxx]) doesn't work
            const roundId = computeRoundId(1, 1)
            const round = roundDataMap[roundId]
            const res = await chainlinkPriceFeed.getRoundData(roundId)
            expect(res[0]).to.be.deep.eq(round[1])
            expect(res[1]).to.be.deep.eq(round[3])

            const roundId2 = computeRoundId(1, 2)
            const round2 = roundDataMap[roundId2]
            const res2 = await chainlinkPriceFeed.getRoundData(roundId2)
            expect(res2[0]).to.be.deep.eq(round2[1])
            expect(res2[1]).to.be.deep.eq(round2[3])

            const roundId3 = computeRoundId(2, 10000)
            const round3 = roundDataMap[roundId3]
            const res3 = await chainlinkPriceFeed.getRoundData(roundId3)
            expect(res3[0]).to.be.deep.eq(round3[1])
            expect(res3[1]).to.be.deep.eq(round3[3])
        })

        it("force error, getRoundData with invalid roundId", async () => {
            const invalidRoundId = "123"
            await expect(chainlinkPriceFeed.getRoundData(invalidRoundId)).to.be.revertedWith("CPF_IP")
        })
    })
})
