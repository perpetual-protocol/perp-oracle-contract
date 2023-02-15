import { MockContract, smock } from "@defi-wonderland/smock"
import { expect } from "chai"
import { BigNumber } from "ethers"
import { parseEther, parseUnits } from "ethers/lib/utils"
import { ethers, waffle } from "hardhat"
import { ChainlinkPriceFeedV1R1, TestAggregatorV3, TestAggregatorV3__factory } from "../typechain"
import { computeRoundId } from "./shared/chainlink"

interface ChainlinkPriceFeedFixture {
    chainlinkPriceFeedV1R1: ChainlinkPriceFeedV1R1
    aggregator: MockContract<TestAggregatorV3>
    chainlinkPriceFeedV1R1_2: ChainlinkPriceFeedV1R1
    aggregator2: MockContract<TestAggregatorV3>
    sequencerUptimeFeed: MockContract<TestAggregatorV3>
}

async function chainlinkPriceFeedV1R1Fixture(): Promise<ChainlinkPriceFeedFixture> {
    const [admin] = await ethers.getSigners()
    const aggregatorFactory = await smock.mock<TestAggregatorV3__factory>("TestAggregatorV3", admin)
    const aggregator = await aggregatorFactory.deploy()
    aggregator.decimals.returns(() => 18)

    const sequencerUptimeFeed = await aggregatorFactory.deploy()

    const chainlinkPriceFeedV1R1Factory = await ethers.getContractFactory("ChainlinkPriceFeedV1R1")
    const chainlinkPriceFeedV1R1 = (await chainlinkPriceFeedV1R1Factory.deploy(
        aggregator.address,
        sequencerUptimeFeed.address,
    )) as ChainlinkPriceFeedV1R1

    const aggregatorFactory2 = await smock.mock<TestAggregatorV3__factory>("TestAggregatorV3", admin)
    const aggregator2 = await aggregatorFactory2.deploy()
    aggregator2.decimals.returns(() => 8)

    const chainlinkPriceFeedV1R1Factory2 = await ethers.getContractFactory("ChainlinkPriceFeedV1R1")
    const chainlinkPriceFeedV1R1_2 = (await chainlinkPriceFeedV1R1Factory2.deploy(
        aggregator2.address,
        sequencerUptimeFeed.address,
    )) as ChainlinkPriceFeedV1R1

    return { chainlinkPriceFeedV1R1, aggregator, chainlinkPriceFeedV1R1_2, aggregator2, sequencerUptimeFeed }
}

describe("ChainlinkPriceFeedV1R1 Spec", () => {
    const [admin] = waffle.provider.getWallets()
    const loadFixture: ReturnType<typeof waffle.createFixtureLoader> = waffle.createFixtureLoader([admin])
    let chainlinkPriceFeed: ChainlinkPriceFeedV1R1
    let aggregator: MockContract<TestAggregatorV3>
    let priceFeedDecimals: number
    let chainlinkPriceFeed2: ChainlinkPriceFeedV1R1
    let aggregator2: MockContract<TestAggregatorV3>
    let priceFeedDecimals2: number
    let sequencerUptimeFeed: MockContract<TestAggregatorV3>

    beforeEach(async () => {
        const _fixture = await loadFixture(chainlinkPriceFeedV1R1Fixture)
        chainlinkPriceFeed = _fixture.chainlinkPriceFeedV1R1
        aggregator = _fixture.aggregator
        priceFeedDecimals = await chainlinkPriceFeed.decimals()
        chainlinkPriceFeed2 = _fixture.chainlinkPriceFeedV1R1_2
        aggregator2 = _fixture.aggregator2
        priceFeedDecimals2 = await chainlinkPriceFeed2.decimals()
        sequencerUptimeFeed = _fixture.sequencerUptimeFeed
    })

    describe("twap edge cases, have the same timestamp for several rounds", () => {
        let currentTime: number
        let roundData: any[]

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
            currentTime = (await waffle.provider.getBlock("latest")).timestamp

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

            sequencerUptimeFeed.latestRoundData.returns(() => {
                // [roundId, answer, startedAt, updatedAt, answeredInRound]
                // Set startedAt before current time - GRACE_PERIOD_TIME so it passes the check.
                return [0, 0, currentTime - 4000, currentTime, 0]
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
        let currentTime: number
        let roundData: any[]

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
            currentTime = (await waffle.provider.getBlock("latest")).timestamp

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

            sequencerUptimeFeed.latestRoundData.returns(() => {
                // [roundId, answer, startedAt, updatedAt, answeredInRound]
                // Set startedAt before current time - GRACE_PERIOD_TIME so it passes the check.
                return [0, 0, currentTime - 4000, currentTime, 0]
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

    it("getSequencerUptimeFeed", async () => {
        expect(await chainlinkPriceFeed2.getSequencerUptimeFeed()).to.be.eq(sequencerUptimeFeed.address)
    })

    describe("sequencer status check", async () => {
        let currentTime
        beforeEach(async () => {
            currentTime = (await waffle.provider.getBlock("latest")).timestamp
        })

        it("force error, sequencer status is DOWN", async () => {
            sequencerUptimeFeed.latestRoundData.returns(() => {
                // [roundId, answer, startedAt, updatedAt, answeredInRound]
                return [0, 1, currentTime, currentTime, 0]
            })
            await expect(chainlinkPriceFeed.getPrice(30)).to.be.revertedWith("CPF_SD")
        })

        it("force, error, sequencer uptime duration is less than GRACE_PERIOD_TIME", async () => {
            sequencerUptimeFeed.latestRoundData.returns(() => {
                return [0, 0, currentTime - 1800, currentTime, 0]
            })
            await expect(chainlinkPriceFeed.getPrice(30)).to.be.revertedWith("CPF_GPNO")
        })

        it("return latest price when sequencer is up and ready", async () => {
            aggregator.latestRoundData.returns(() => {
                return [0, parseEther("1000"), currentTime - 50, currentTime - 50, 0]
            })

            sequencerUptimeFeed.latestRoundData.returns(() => {
                // Set startedAt before current time - GRACE_PERIOD_TIME so it passes the check.
                return [0, 0, currentTime - 4000, currentTime, 0]
            })

            expect(await chainlinkPriceFeed.getPrice(30)).to.be.eq(parseEther("1000"))
        })
    })
})
