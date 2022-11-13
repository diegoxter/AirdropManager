const { expect } = require('chai')
const { BigNumber } = require('ethers')
const { artifacts, contract, ethers, network } = require('hardhat')
require('@nomicfoundation/hardhat-chai-matchers')

describe('AirdropManager', function () {

    let instanceCount = 0

    async function deployMockToken() {
        const [ alice, bob, dana, maria ] = await ethers.getSigners()

        const tokenFactory = await ethers.getContractFactory('HTA1')
        const Token = await tokenFactory.deploy(
            10000000000000000000n,
            'MockERC20',
            'MTKN'
        )
        await Token.deployed()
        expect(await Token.balanceOf(alice.address)).to.equal(
            10000000000000000000n
        )

        for (let thisUser of [ bob, dana, maria ]) {
            await expect(Token.connect(alice).transfer(thisUser.address, 2000000000000000000n)).
            to.changeTokenBalances(
                Token,   
                [alice, thisUser],
                [-2000000000000000000n, 2000000000000000000n]
            )
        }

        return Token 
    }

    async function deployAMFixture() {
        const [ alice ] = await ethers.getSigners()
        const TestValue = ethers.utils.parseEther('0.0001')

        const airmanAPFactory = await ethers.getContractFactory('AdminPanel')
        const AdminPanel = await airmanAPFactory.deploy(TestValue)
        await AdminPanel.deployed()
        expect(await AdminPanel.owner()).to.equal(alice.address)

        return { AdminPanel, TestValue }
    }

    async function deployNewAirmanInstance(owner, token, AdminPanel) {
        const TestValue = ethers.utils.parseEther('0.0001')

        // owner needs to approve some tokens to create a new AirManInstance
        await token.connect(owner).approve(AdminPanel.address, 1000000000000000000n)
        expect(await token.allowance(owner.address, AdminPanel.address)).
        to.equal(1000000000000000000n)

        // owner creates a new AirManInstance
        await expect(AdminPanel.connect(owner).newAirdropManagerInstance(token.address, 1000000000000000000n, {
            value: TestValue,
        })).to.emit(
            AdminPanel, 'NewAirdropManagerDeployed'
        )

        // Connecting to the new AirMan instance address
        const newInstanceData = await AdminPanel.deployedManagers(instanceCount)
        const AirManFactory = await ethers.getContractFactory('AirdropManager')
        const AirManInstance = await AirManFactory.attach(
            `${newInstanceData[1]}`
        )
        // Verify it exists through its token balance
        expect(await token.balanceOf(AirManInstance.address)).to.equal(
            1000000000000000000n
        )

        return AirManInstance
    }

    it('creates new Airdrop Manager instances, respecting ownership', async function () {
        const [ alice, bob, dana, maria, random ] = await ethers.getSigners()

        const { AdminPanel } = await deployAMFixture()
        const bobToken = await deployMockToken()
        const genericToken = await deployMockToken()

        // Updating the instanceCount after each deploy
        const bobAirMan = await deployNewAirmanInstance(bob, bobToken, AdminPanel)
        instanceCount += 1
        const danaAirMan = await deployNewAirmanInstance(dana, genericToken, AdminPanel)
        instanceCount += 1
        const mariaAirMan = await deployNewAirmanInstance(maria, genericToken, AdminPanel)
        instanceCount += 1

        for (let thisInstance of [ bobAirMan, danaAirMan, mariaAirMan ]) {
            await expect(thisInstance.connect(alice).newAirdropCampaign(120, 500000000000000000n)).
            to.be.revertedWith('This can only be done by the owner')

            await expect(thisInstance.connect(random).newAirdropCampaign(120, 500000000000000000n)).
            to.be.revertedWith('This can only be done by the owner')
        }

        await expect(bobAirMan.connect(bob).newAirdropCampaign(120, 500000000000000000n)).
        to.emit(bobAirMan, 'NewAirdropCampaign')
        await expect(danaAirMan.connect(dana).newAirdropCampaign(120, 500000000000000000n)).
        to.emit(danaAirMan, 'NewAirdropCampaign')

        for (let thisInstance of [ bobAirMan, danaAirMan, mariaAirMan ]) {
            await expect(thisInstance.connect(alice).toggleCampaign(0)).
            to.be.revertedWith('This can only be done by the owner')

            await expect(thisInstance.connect(random).toggleCampaign(0)).
            to.be.revertedWith('This can only be done by the owner')
        }

        // Verify the campaign is active
        expect((await danaAirMan.campaigns(0))[4]).to.be.true

        await expect(danaAirMan.connect(dana).toggleCampaign(0)).
        to.not.be.reverted
        await expect(mariaAirMan.connect(maria).newAirdropCampaign(120, 500000000000000000n)).
        to.emit(mariaAirMan, 'NewAirdropCampaign')
        // Verify the campaign is active
        expect((await mariaAirMan.campaigns(0))[4]).to.be.true

        await expect(mariaAirMan.connect(maria).toggleCampaign(0)).
        to.not.be.reverted

        // Verify the campaign has been paused
        expect((await danaAirMan.campaigns(0))[4]).to.be.false
        expect((await mariaAirMan.campaigns(0))[4]).to.be.false

        // Reset the test instance count
        instanceCount = 0
    })

    it('', async function () {
    })

    it('', async function () {
    })

})