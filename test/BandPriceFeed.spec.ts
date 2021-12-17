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

    describe("update", () => {
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
            const round = roundData[roundData.length - 1]
            expect(observation.price).to.eq(round[0])
            expect(observation.timestamp).to.eq(round[1])
            expect(observation.priceCumulative).to.eq(parseEther("6000"))
        })

        it("force error, the second update is the same timestamp", async () => {
            roundData.push([parseEther("400"), currentTime, currentTime])
            bandReference.getReferenceData.returns(() => {
                return roundData[roundData.length - 1]
            })
            await bandPriceFeed.update()

            roundData.push([parseEther("440"), currentTime, currentTime])
            bandReference.getReferenceData.returns(() => {
                return roundData[roundData.length - 1]
            })
            await expect(bandPriceFeed.update()).to.be.revertedWith("BPF_IT")
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

            currentTime += 45
            await ethers.provider.send("evm_setNextBlockTimestamp", [currentTime])
            await ethers.provider.send("evm_mine", [])
        })

        describe("getPrice", () => {
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

            it("asking interval less the timestamp of the latest observation", async () => {
                const price = await bandPriceFeed.getPrice(14)
                expect(price).to.eq(parseEther("410"))
            })

            it("the latest band reference data is not being updated to observation", async () => {
                currentTime += 15
                roundData.push([parseEther("415"), currentTime, currentTime])
                bandReference.getReferenceData.returns(() => {
                    return roundData[roundData.length - 1]
                })

                currentTime += 15
                await ethers.provider.send("evm_setNextBlockTimestamp", [currentTime])
                await ethers.provider.send("evm_mine", [])

                // (415 * 15 + 410 * 30) / 45 = 411.666666
                const price = await bandPriceFeed.getPrice(45)
                expect(price).to.eq("411666666666666666666")
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

        describe("cachePrice", () => {
            beforeEach(async () => {
                currentTime += 14
                await ethers.provider.send("evm_setNextBlockTimestamp", [currentTime])
                await ethers.provider.send("evm_mine", [])
                // cache the twap first
                await bandPriceFeed.cachePrice(900)
                currentTime = (await waffle.provider.getBlock("latest")).timestamp
            })

            it("verify cache", async () => {
                const cachedTimestamp = await bandPriceFeed.latestUpdatedTimestamp()
                const cachedTwap = await bandPriceFeed.latestUpdated15MinsTwap()

                // verify the cache
                expect(cachedTimestamp).to.eq(currentTime)
                // (400 * 15 + 405 * 15 + 410 * 30 ) / 60 = 406.25
                expect(cachedTwap).to.eq(parseEther("406.25"))
            })

            it("return latest price if interval is zero and cache is not being updated", async () => {
                const cachedTimestamp = await bandPriceFeed.latestUpdatedTimestamp()
                const cachedTwap = await bandPriceFeed.latestUpdated15MinsTwap()

                const price = await bandPriceFeed.callStatic.cachePrice(0)
                expect(price).to.eq(parseEther("410"))
                await bandPriceFeed.cachePrice(0)

                expect(await bandPriceFeed.latestUpdatedTimestamp()).to.eq(cachedTimestamp)
                expect(await bandPriceFeed.latestUpdated15MinsTwap()).to.eq(cachedTwap)
            })

            // hardhat increase timestamp by 1 if any tx happens
            it.skip("return cached twap if timestamp is the same", async () => {
                const cachedTimestamp = await bandPriceFeed.latestUpdatedTimestamp()
                const cachedTwap = await bandPriceFeed.latestUpdated15MinsTwap()

                const price = await bandPriceFeed.callStatic.cachePrice(900)
                expect(price).to.eq(parseEther("406.25"))

                await bandPriceFeed.cachePrice(900)

                // the cache should not be updated
                expect(await bandPriceFeed.latestUpdatedTimestamp()).to.eq(cachedTimestamp)
                expect(await bandPriceFeed.latestUpdated15MinsTwap()).to.eq(cachedTwap)
            })

            it("return new twap and cache it if timestamp is different", async () => {
                currentTime += 14
                await ethers.provider.send("evm_setNextBlockTimestamp", [currentTime])
                await ethers.provider.send("evm_mine", [])

                await bandPriceFeed.cachePrice(900)

                // (400 * 15 + 405 * 15 + 410 * 45 ) / 75 = 406.25
                expect(await bandPriceFeed.latestUpdatedTimestamp()).to.eq(currentTime + 1)
                expect(await bandPriceFeed.latestUpdated15MinsTwap()).to.eq(parseEther("407"))
            })
        })
    })

    describe("circular observations", () => {
        let currentTime
        let roundData = [
            // [rate, lastUpdatedBase, lastUpdatedQuote]
        ]
        beforeEach(async () => {
            currentTime = (await waffle.provider.getBlock("latest")).timestamp

            const beginPrice: number = 400
            for (let i = 0; i < 256; i++) {
                roundData.push([parseEther((beginPrice + i).toString()), currentTime, currentTime])
                bandReference.getReferenceData.returns(() => {
                    return roundData[roundData.length - 1]
                })
                await bandPriceFeed.update()

                currentTime += 15
                await ethers.provider.send("evm_setNextBlockTimestamp", [currentTime])
                await ethers.provider.send("evm_mine", [])
            }
        })

        it("get price", async () => {})
    })
})
