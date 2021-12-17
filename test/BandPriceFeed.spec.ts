import { FakeContract, smock } from "@defi-wonderland/smock"
import { expect } from "chai"
import { parseEther } from "ethers/lib/utils"
import { ethers, waffle } from "hardhat"
import { BandPriceFeed, TestStdReference } from "../typechain"

interface ChainlinkPriceFeedFixture {
    bandPriceFeed: BandPriceFeed
    bandReference: FakeContract<TestStdReference>
    baseAsset: string
}

async function bandPriceFeedFixture(): Promise<ChainlinkPriceFeedFixture> {
    const bandReference = await smock.fake<TestStdReference>("TestStdReference")

    const baseAsset = "ETH"
    const bandPriceFeedFactory = await ethers.getContractFactory("BandPriceFeed")
    const bandPriceFeed = (await bandPriceFeedFactory.deploy(bandReference.address, baseAsset)) as BandPriceFeed

    return { bandPriceFeed, bandReference, baseAsset }
}

describe.only("BandPriceFeed Spec", () => {
    const [admin] = waffle.provider.getWallets()
    const loadFixture: ReturnType<typeof waffle.createFixtureLoader> = waffle.createFixtureLoader([admin])
    let bandPriceFeed: BandPriceFeed
    let bandReference: FakeContract<TestStdReference>
    let currentTime: number
    let roundData: any[]

    beforeEach(async () => {
        const _fixture = await loadFixture(bandPriceFeedFixture)
        bandReference = _fixture.bandReference
        bandPriceFeed = _fixture.bandPriceFeed
    })

    describe.only("update", () => {
        let currentTime
        let roundData = [
            // [rate, lastUpdatedBase, lastUpdatedQuote]
        ]
        beforeEach(async () => {
            currentTime = (await waffle.provider.getBlock("latest")).timestamp
        })

        it("update price once", async () => {
            roundData.push([parseEther("400"), currentTime, currentTime])
            bandReference.getReferenceData.returns(() => {
                return roundData[roundData.length - 1]
            })

            expect(await bandPriceFeed.update())
                .to.be.emit(bandPriceFeed, "PriceUpdated")
                .withArgs("ETH", parseEther("400"), currentTime)

            const observation = await bandPriceFeed.observations(0)
            const round = roundData[0]
            expect(observation.price).to.eq(round[0])
            expect(observation.timestamp).to.eq(round[1])
            expect(observation.priceCumulative).to.eq(0)
        })

        it("update price twice", async () => {
            roundData.push([parseEther("400"), currentTime, currentTime])
            bandReference.getReferenceData.returns(() => {
                return roundData[roundData.length - 1]
            })
            await bandPriceFeed.update()

            roundData.push([parseEther("440"), currentTime + 15, currentTime + 15])
            bandReference.getReferenceData.returns(() => {
                return roundData[roundData.length - 1]
            })
            await bandPriceFeed.update()

            const observation = await bandPriceFeed.observations(1)
            const round = roundData[1]
            expect(observation.price).to.eq(round[0])
            expect(observation.timestamp).to.eq(round[1])
            expect(observation.priceCumulative).to.eq(6000)
        })
    })

    describe("twap", () => {
        beforeEach(async () => {
            // `base` = now - _interval
            // bandReference's answer
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
                // [rate, lastUpdatedBase, lastUpdatedQuote]
            ]

            roundData.push([parseEther("400"), currentTime, currentTime])
            bandReference.getReferenceData.returns(() => {
                return roundData[roundData.length - 1]
            })
            await bandPriceFeed.update()

            roundData.push([parseEther("405"), currentTime + 15, currentTime + 15])
            bandReference.getReferenceData.returns(() => {
                return roundData[roundData.length - 1]
            })
            await bandPriceFeed.update()

            roundData.push([parseEther("410"), currentTime + 30, currentTime + 30])
            bandReference.getReferenceData.returns(() => {
                return roundData[roundData.length - 1]
            })
            await bandPriceFeed.update()

            // 400 * 15 + 405 * 15 + 410 * 15 = 18,225
            // 18,225 / 45 = 405

            // 400 * 15 + 405 * 15 = 12,075
            // 12,075 / 30 = 402.5

            //        XXXXXXXXX
            //   -- 30 -------- 45
            //
            //   -- 30 -- 40 -- 45
            //     obs   band   now
            // roundData.push([parseEther("410"), currentTime + 45, currentTime + 45])
            // bandReference.getReferenceData.returns(() => {
            //     return roundData[roundData.length - 1]
            // })
            // await bandPriceFeed.update()

            currentTime += 45
            await ethers.provider.send("evm_setNextBlockTimestamp", [currentTime])
            await ethers.provider.send("evm_mine", [])
        })

        it("return latest price if interval is zero", async () => {
            const price = await bandPriceFeed.getPrice(0)
            expect(price).to.eq(parseEther("410"))
        })

        it("twap price", async () => {
            const price = await bandPriceFeed.getPrice(45)
            expect(price).to.eq(parseEther("405"))
        })

        it("asking interval more than bandReference has", async () => {
            const price = await bandPriceFeed.getPrice(46)
            expect(price).to.eq(parseEther("405"))
        })

        it("asking interval less than bandReference has", async () => {
            const price = await bandPriceFeed.getPrice(44)
            expect(price).to.eq("405113636363636363636")
        })

        it("given variant price period", async () => {
            roundData.push([parseEther("420"), currentTime + 30, currentTime + 30])
            await ethers.provider.send("evm_setNextBlockTimestamp", [currentTime + 50])
            await ethers.provider.send("evm_mine", [])
            // twap price should be ((400 * 15) + (405 * 15) + (410 * 45) + (420 * 20)) / 95 = 409.736
            const price = await bandPriceFeed.getPrice(95)
            expect(price).to.eq("409736842105263157894")
        })

        it("latest price update time is earlier than the request, return the latest price", async () => {
            await ethers.provider.send("evm_setNextBlockTimestamp", [currentTime + 100])
            await ethers.provider.send("evm_mine", [])

            // latest update time is base + 30, but now is base + 145 and asking for (now - 45)
            // should return the latest price directly
            const price = await bandPriceFeed.getPrice(45)
            expect(price).to.eq(parseEther("410"))
        })
    })

    describe("edge cases, have the same timestamp for several rounds", () => {
        beforeEach(async () => {
            // `base` = now - _interval
            // bandReference's answer
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
                // [rate, lastUpdatedBase, lastUpdatedQuote]
            ]

            // have the same timestamp for rounds
            roundData.push([parseEther("400"), currentTime, currentTime])
            bandReference.getReferenceData.returns(() => {
                return roundData[roundData.length - 1]
            })
            await bandPriceFeed.update()

            roundData.push([parseEther("405"), currentTime, currentTime])
            bandReference.getReferenceData.returns(() => {
                return roundData[roundData.length - 1]
            })
            await bandPriceFeed.update()

            roundData.push([parseEther("410"), currentTime, currentTime])
            bandReference.getReferenceData.returns(() => {
                return roundData[roundData.length - 1]
            })
            await bandPriceFeed.update()

            currentTime += 15
            await ethers.provider.send("evm_setNextBlockTimestamp", [currentTime])
            await ethers.provider.send("evm_mine", [])
        })

        it("get the latest price ", async () => {
            const price = await bandPriceFeed.getPrice(45)
            expect(price).to.eq(parseEther("410"))
        })

        it("asking interval more than bandReference has", async () => {
            const price = await bandPriceFeed.getPrice(46)
            expect(price).to.eq(parseEther("410"))
        })
    })
})
