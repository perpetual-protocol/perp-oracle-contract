// scenario
// only owner call update
/*
*  Spec: Deploy a priceFeedUpdater, should verify a list of priceFeed is same as parameter given from deployment
*
*  Spec: When setPriceFeeds, only the owner is able to call
*  As an owner, call setPriceFeeds, success
*  As a non-owner, call setPriceFeeds, fail
*
* */
import {MockContract, smock} from "@defi-wonderland/smock"
import chai, {expect} from "chai"
import {ethers, waffle} from "hardhat"
import {
    ChainlinkPriceFeedV2,
    ChainlinkPriceFeedV2__factory,
    PriceFeedUpdater,
    TestAggregatorV3,
    TestAggregatorV3__factory
} from "../typechain"
import {Wallet} from "ethers";

chai.use(smock.matchers);

interface PriceFeedUpdaterFixture {
    ethPriceFeed: MockContract<ChainlinkPriceFeedV2>
    btcPriceFeed: MockContract<ChainlinkPriceFeedV2>
    solPriceFeed: MockContract<ChainlinkPriceFeedV2>
    priceFeedUpdater: PriceFeedUpdater
    admin: Wallet
    alice: Wallet
}

describe.only("PriceFeedUpdater Spec", () => {
    const loadFixture: ReturnType<typeof waffle.createFixtureLoader> = waffle.createFixtureLoader()
    let fixture: PriceFeedUpdaterFixture;

    beforeEach(async () => {
        fixture = await loadFixture(createFixture)
    })
    afterEach(async () => {
        fixture.btcPriceFeed.update.reset();
        fixture.ethPriceFeed.update.reset();
    })

    async function executeFallback(priceFeedUpdater: PriceFeedUpdater) {
        const { alice, } = fixture;
        await alice.sendTransaction({
            to: priceFeedUpdater.address,
            value: 0,
            gasLimit: 150000  // Give gas limit to force run transaction without dry run
        })
    }

    async function createFixture(): Promise<PriceFeedUpdaterFixture> {
        const [admin, alice, ] = waffle.provider.getWallets()

        const aggregatorFactory = await smock.mock<TestAggregatorV3__factory>("TestAggregatorV3")
        const aggregator = await aggregatorFactory.deploy()

        const chainlinkPriceFeedV2Factory = await smock.mock<ChainlinkPriceFeedV2__factory>("ChainlinkPriceFeedV2")
        const ethPriceFeed = (await chainlinkPriceFeedV2Factory.deploy(aggregator.address, 900))
        const btcPriceFeed = (await chainlinkPriceFeedV2Factory.deploy(aggregator.address, 900))
        const solPriceFeed = (await chainlinkPriceFeedV2Factory.deploy(aggregator.address, 900))

        await ethPriceFeed.deployed()
        await btcPriceFeed.deployed()
        await solPriceFeed.deployed()

        const priceFeedUpdaterFactory = await ethers.getContractFactory("PriceFeedUpdater");
        const priceFeedUpdater = (await priceFeedUpdaterFactory.deploy(
            [ethPriceFeed.address, btcPriceFeed.address],
        )) as PriceFeedUpdater;

        return {ethPriceFeed, btcPriceFeed, solPriceFeed, priceFeedUpdater, admin, alice};
    }
    it("the result of getPriceFeeds should be same as priceFeeds given when deployment", async () => {
        const {ethPriceFeed, btcPriceFeed, priceFeedUpdater} = fixture;
        const priceFeeds = await priceFeedUpdater.getPriceFeeds();
        expect(priceFeeds).deep.equals([ethPriceFeed.address, btcPriceFeed.address])
    })

    describe("When setPriceFeed", () => {
        it("should success when called by owner", async () => {
            const {solPriceFeed, priceFeedUpdater, admin: owner} = fixture;
            await priceFeedUpdater.connect(owner).setPriceFeeds([solPriceFeed.address])
            const priceFeeds = await priceFeedUpdater.getPriceFeeds();
            expect(priceFeeds).deep.equals([solPriceFeed.address])
        })
        it("force error, when called by non-owner", async () => {
            const {solPriceFeed, priceFeedUpdater, alice} = fixture;
            let tx = priceFeedUpdater.connect(alice).setPriceFeeds([solPriceFeed.address]);
            await expect(tx).to.be.revertedWith("SO_CNO")
        })
    })

    describe("When priceFeedUpdater fallback execute", () => {
        it("should success if all priceFeed are updated successfully", async () => {
            const {ethPriceFeed, btcPriceFeed, priceFeedUpdater} = fixture;

            await executeFallback(priceFeedUpdater);

            expect(ethPriceFeed.update).to.have.been.calledOnce;
            expect(btcPriceFeed.update).to.have.been.calledOnce;
        })
        it("should still success if any one of priceFeed is updated fail", async () => {
            const {ethPriceFeed, btcPriceFeed, priceFeedUpdater} = fixture

            ethPriceFeed.update.reverts();
            await executeFallback(priceFeedUpdater);

            expect(ethPriceFeed.update).to.have.been.calledOnce;
            expect(btcPriceFeed.update).to.have.been.calledOnce;
        })
    })
})

