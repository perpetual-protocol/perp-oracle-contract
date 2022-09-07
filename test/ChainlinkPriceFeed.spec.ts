import { MockContract, smock } from "@defi-wonderland/smock"
import { expect } from "chai"
import { BigNumber } from "ethers"
import { parseEther, parseUnits } from "ethers/lib/utils"
import { ethers, waffle } from "hardhat"
import { ChainlinkPriceFeed, TestAggregatorV3, TestAggregatorV3__factory } from "../typechain"
import { computeRoundId } from "./shared/chainlink"

interface ChainlinkPriceFeedFixture {
    chainlinkPriceFeed: ChainlinkPriceFeed
    aggregator: MockContract<TestAggregatorV3>
    chainlinkPriceFeed2: ChainlinkPriceFeed
    aggregator2: MockContract<TestAggregatorV3>
}

async function chainlinkPriceFeedFixture(): Promise<ChainlinkPriceFeedFixture> {
    const [admin] = await ethers.getSigners();
    const aggregatorFactory = await smock.mock<TestAggregatorV3__factory>("TestAggregatorV3", admin)
    const aggregator = await aggregatorFactory.deploy()
    aggregator.decimals.returns(() => 18)

    const chainlinkPriceFeedFactory = await ethers.getContractFactory("ChainlinkPriceFeed")
    const chainlinkPriceFeed = (await chainlinkPriceFeedFactory.deploy(aggregator.address)) as ChainlinkPriceFeed

    const aggregatorFactory2 = await smock.mock<TestAggregatorV3__factory>("TestAggregatorV3", admin)
    const aggregator2 = await aggregatorFactory2.deploy()
    aggregator2.decimals.returns(() => 8)

    const chainlinkPriceFeedFactory2 = await ethers.getContractFactory("ChainlinkPriceFeed")
    const chainlinkPriceFeed2 = (await chainlinkPriceFeedFactory2.deploy(aggregator2.address)) as ChainlinkPriceFeed

    return { chainlinkPriceFeed, aggregator, chainlinkPriceFeed2, aggregator2 }
}

describe("ChainlinkPriceFeed Spec", () => {
    const [admin] = waffle.provider.getWallets()
    const loadFixture: ReturnType<typeof waffle.createFixtureLoader> = waffle.createFixtureLoader([admin])
    let chainlinkPriceFeed: ChainlinkPriceFeed
    let aggregator: MockContract<TestAggregatorV3>
    let priceFeedDecimals: number
    let chainlinkPriceFeed2: ChainlinkPriceFeed
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
})
