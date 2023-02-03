import { MockContract, smock } from "@defi-wonderland/smock"
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers"
import chai, { expect } from "chai"
import { parseEther } from "ethers/lib/utils"
import { ethers, waffle } from "hardhat"
import {
    ChainlinkPriceFeedV3,
    ChainlinkPriceFeedV3__factory,
    PriceFeedUpdater,
    TestAggregatorV3__factory,
} from "../typechain"

chai.use(smock.matchers)

interface PriceFeedUpdaterFixture {
    ethPriceFeed: MockContract<ChainlinkPriceFeedV3>
    btcPriceFeed: MockContract<ChainlinkPriceFeedV3>
    priceFeedUpdater: PriceFeedUpdater
    admin: SignerWithAddress
    alice: SignerWithAddress
}

describe("PriceFeedUpdater Spec", () => {
    const loadFixture: ReturnType<typeof waffle.createFixtureLoader> = waffle.createFixtureLoader()
    let fixture: PriceFeedUpdaterFixture

    beforeEach(async () => {
        fixture = await loadFixture(createFixture)
    })
    afterEach(async () => {
        fixture.btcPriceFeed.update.reset()
        fixture.ethPriceFeed.update.reset()
    })

    async function executeFallback(priceFeedUpdater: PriceFeedUpdater) {
        const { alice } = fixture
        await alice.sendTransaction({
            to: priceFeedUpdater.address,
            value: 0,
            gasLimit: 150000, // Give gas limit to force run transaction without dry run
        })
    }

    async function createFixture(): Promise<PriceFeedUpdaterFixture> {
        const [admin, alice] = await ethers.getSigners()

        const aggregatorFactory = await smock.mock<TestAggregatorV3__factory>("TestAggregatorV3", admin)
        const aggregator = await aggregatorFactory.deploy()

        const chainlinkPriceFeedV2Factory = await smock.mock<ChainlinkPriceFeedV3__factory>(
            "ChainlinkPriceFeedV3",
            admin,
        )
        const ethPriceFeed = await chainlinkPriceFeedV2Factory.deploy(aggregator.address, 40 * 60, 30 * 60)
        const btcPriceFeed = await chainlinkPriceFeedV2Factory.deploy(aggregator.address, 40 * 60, 30 * 60)

        await ethPriceFeed.deployed()
        await btcPriceFeed.deployed()

        const priceFeedUpdaterFactory = await ethers.getContractFactory("PriceFeedUpdater")
        const priceFeedUpdater = (await priceFeedUpdaterFactory.deploy([
            ethPriceFeed.address,
            btcPriceFeed.address,
        ])) as PriceFeedUpdater

        return { ethPriceFeed, btcPriceFeed, priceFeedUpdater, admin, alice }
    }
    it("the result of getPriceFeeds should be same as priceFeeds given when deployment", async () => {
        const { ethPriceFeed, btcPriceFeed, priceFeedUpdater } = fixture
        const priceFeeds = await priceFeedUpdater.getPriceFeeds()
        expect(priceFeeds).deep.equals([ethPriceFeed.address, btcPriceFeed.address])
    })

    it("force error, when someone sent eth to contract", async () => {
        const { alice, priceFeedUpdater } = fixture
        const tx = alice.sendTransaction({
            to: priceFeedUpdater.address,
            value: parseEther("0.1"),
            gasLimit: 150000, // Give gas limit to force run transaction without dry run
        })
        await expect(tx).to.be.reverted
    })

    describe("When priceFeedUpdater fallback execute", () => {
        it("should success if all priceFeed are updated successfully", async () => {
            const { ethPriceFeed, btcPriceFeed, priceFeedUpdater } = fixture

            await executeFallback(priceFeedUpdater)

            expect(ethPriceFeed.update).to.have.been.calledOnce
            expect(btcPriceFeed.update).to.have.been.calledOnce
        })
        it("should still success if any one of priceFeed is updated fail", async () => {
            const { ethPriceFeed, btcPriceFeed, priceFeedUpdater } = fixture

            ethPriceFeed.update.reverts()
            await executeFallback(priceFeedUpdater)

            expect(ethPriceFeed.update).to.have.been.calledOnce
            expect(btcPriceFeed.update).to.have.been.calledOnce
        })
    })
})
