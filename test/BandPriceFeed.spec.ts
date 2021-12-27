import { MockContract, smock } from "@defi-wonderland/smock"
import { expect } from "chai"
import { parseEther } from "ethers/lib/utils"
import { ethers, waffle } from "hardhat"
import { BandPriceFeed, TestStdReference, TestStdReference__factory } from "../typechain"

interface ChainlinkPriceFeedFixture {
    bandPriceFeed: BandPriceFeed
    bandReference: MockContract<TestStdReference>
    baseAsset: string
}

async function bandPriceFeedFixture(): Promise<ChainlinkPriceFeedFixture> {
    const testStdReferenceFactory = await smock.mock<TestStdReference__factory>("TestStdReference")
    const testStdReference = await testStdReferenceFactory.deploy()

    const baseAsset = "ETH"
    const bandPriceFeedFactory = await ethers.getContractFactory("BandPriceFeed")
    const bandPriceFeed = (await bandPriceFeedFactory.deploy(testStdReference.address, baseAsset)) as BandPriceFeed

    return { bandPriceFeed, bandReference: testStdReference, baseAsset }
}

describe("BandPriceFeed Spec", () => {
    const [admin] = waffle.provider.getWallets()
    const loadFixture: ReturnType<typeof waffle.createFixtureLoader> = waffle.createFixtureLoader([admin])
    let bandPriceFeed: BandPriceFeed
    let bandReference: MockContract<TestStdReference>
    let currentTime: number
    let roundData: any[]

    async function updatePrice(price: number, forward: boolean = true): Promise<void> {
        roundData.push([parseEther(price.toString()), currentTime, currentTime])
        bandReference.getReferenceData.returns(() => {
            return roundData[roundData.length - 1]
        })
        await bandPriceFeed.update()

        if (forward) {
            currentTime += 15
            await ethers.provider.send("evm_setNextBlockTimestamp", [currentTime])
            await ethers.provider.send("evm_mine", [])
        }
    }

    beforeEach(async () => {
        const _fixture = await loadFixture(bandPriceFeedFixture)
        bandReference = _fixture.bandReference
        bandPriceFeed = _fixture.bandPriceFeed
        roundData = []
    })

    describe("update", () => {
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
                .withArgs("ETH", parseEther("400"), currentTime, 0)

            const observation = await bandPriceFeed.observations(0)
            const round = roundData[0]
            expect(observation.price).to.eq(round[0])
            expect(observation.timestamp).to.eq(round[1])
            expect(observation.priceCumulative).to.eq(0)
        })

        it("update price twice", async () => {
            await updatePrice(400, false)

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
            await updatePrice(400, false)

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

            await updatePrice(400)
            await updatePrice(405)
            await updatePrice(410)
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
                await updatePrice(415)

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
    })

    describe("circular observations", () => {
        let currentTimeBefore: number
        let beginPrice = 400

        beforeEach(async () => {
            currentTimeBefore = currentTime = (await waffle.provider.getBlock("latest")).timestamp

            // fill up 255 observations and the final price will be observations[254] = 624,
            // and observations[255] is empty
            for (let i = 0; i < 255; i++) {
                await updatePrice(beginPrice + i)
            }
        })

        it("verify status", async () => {
            expect(await bandPriceFeed.currentObservationIndex()).to.eq(254)

            // observations[255] shouldn't be updated since we only run 255 times in for loop
            const observation255 = await bandPriceFeed.observations(255)
            expect(observation255.price).to.eq(0)
            expect(observation255.priceCumulative).to.eq(0)
            expect(observation255.timestamp).to.eq(0)

            const observation254 = await bandPriceFeed.observations(254)
            expect(observation254.price).to.eq(parseEther("654"))
            expect(observation254.timestamp).to.eq(currentTimeBefore + 15 * 254)

            // (654 * 15 + 653 * 15 + 652 * 15) / 45 = 653
            const price = await bandPriceFeed.getPrice(45)
            expect(price).to.eq(parseEther("653"))
        })

        it("get price after currentObservationIndex is rotated to 0", async () => {
            // update 2 more times to rotate currentObservationIndex to 0
            // currentObservationIndex = 255
            await updatePrice(beginPrice + 255)
            // this one will override the first observation which is observations[0]
            // currentObservationIndex = 0
            await updatePrice(beginPrice + 256)

            expect(await bandPriceFeed.currentObservationIndex()).to.eq(0)

            // (656 * 15 + 655 * 15 + 654 * 15) / 45 = 655
            const price = await bandPriceFeed.getPrice(45)
            expect(price).to.eq(parseEther("655"))
        })

        it("get price after currentObservationIndex is rotated to 10", async () => {
            await updatePrice(beginPrice + 255)
            for (let i = 0; i < 10; i++) {
                await updatePrice(beginPrice + 256 + i)
            }

            expect(await bandPriceFeed.currentObservationIndex()).to.eq(9)

            // (665 * 15 + 664 * 15 + 663 * 15) / 45 = 664
            const price = await bandPriceFeed.getPrice(45)
            expect(price).to.eq(parseEther("664"))
        })

        it("asking interval is exact the same as max allowable interval", async () => {
            // update 2 more times to rotate currentObservationIndex to 0
            await updatePrice(beginPrice + 255)

            // this one will override the first observation which is observations[0]
            await updatePrice(beginPrice + 256, false)

            expect(await bandPriceFeed.currentObservationIndex()).to.eq(0)

            // (((401 + 655) / 2) * 3825 + 656 * 1 ) / 3,826 = 528.0334553058
            const price = await bandPriceFeed.getPrice(255 * 15 + 1)
            expect(price).to.eq("528033455305802404600")
        })

        it("force error, asking interval more than observation has", async () => {
            // update 2 more times to rotate currentObservationIndex to 0
            await updatePrice(beginPrice + 255)

            // this one will override the first observation which is observations[0]
            await updatePrice(beginPrice + 256, false)

            expect(await bandPriceFeed.currentObservationIndex()).to.eq(0)

            // the longest interval = 255 * 15 = 3825, it should be revert when interval > 3826
            // here, we set interval to 3827 because hardhat increases the timestamp by 1 when any tx happens
            await expect(bandPriceFeed.getPrice(255 * 15 + 2)).to.be.revertedWith("BPF_NEH")
        })
    })

    describe("price is not updated yet", () => {
        it("get spot price", async () => {
            await expect(bandPriceFeed.getPrice(900)).to.be.revertedWith("BPF_ND")
        })

        it("force error, get twap price", async () => {
            await expect(bandPriceFeed.getPrice(900)).to.be.revertedWith("BPF_ND")
        })
    })
})
