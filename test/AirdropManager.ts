import { expect } from 'chai'
import { Contract } from 'ethers'
import { ethers } from 'hardhat'
import '@nomicfoundation/hardhat-chai-matchers'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'


// to do refactor all this
describe('AirdropManager', function () {

    const totalToken = 10000000000000000000n
    let instanceCount = 0  // helper number
    let Token

    before("give some test tokens first", async function () {
        const [ alice, bob, dana, maria ] = await ethers.getSigners()

        const tokenFactory = await ethers.getContractFactory('HTA1')
        Token = await tokenFactory.deploy(
            totalToken,
            'MockERC20',
            'MTKN'
        )
        await Token.deployed()
        expect(await Token.balanceOf(alice.address)).to.equal(
            totalToken
        )

        for (let thisUser of [ bob, dana, maria ]) {
            await expect(Token.connect(alice).transfer(thisUser.address, totalToken/BigInt(5))).
            to.changeTokenBalances(
                Token,   
                [alice, thisUser],
                [-totalToken/BigInt(5), totalToken/BigInt(5)]
            )
        }

        return Token
    })

    async function deployAMFixture() {
        const [ alice ] = await ethers.getSigners()
        const TestValue = ethers.utils.parseEther('0.0001')

        const airmanAPFactory = await ethers.getContractFactory('AdminPanel')
        const AdminPanel = await airmanAPFactory.deploy(TestValue)
        await AdminPanel.deployed()
        expect(await AdminPanel.owner()).to.equal(alice.address)

        return { AdminPanel, TestValue }
    }

    async function deployNewAirmanInstance(owner: SignerWithAddress, AdminPanel: Contract) {
        const TestValue = ethers.utils.parseEther('0.0001')

        // owner needs to approve some tokens to create a new AirManInstance
        await Token.connect(owner).approve(AdminPanel.address, totalToken/BigInt(5))
        
        // Time related code
        const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms))
        await delay(3500)
        expect(await Token.allowance(owner.address, AdminPanel.address)).
        to.equal(totalToken/BigInt(5))

        // owner creates a new AirManInstance
        await expect(AdminPanel.connect(owner).newAirdropManagerInstance(
            Token.address, 
            50000000000000000n,
            {
            value: TestValue,
            })
        ).to.emit(
            AdminPanel, 'NewAirdropManagerDeployed'
        )

        // Connecting to the new AirMan instance address
        const newInstanceData = await AdminPanel.deployedManagers(instanceCount)
        const AirManFactory = await ethers.getContractFactory('AirdropManager')
        const AirManInstance = await AirManFactory.attach(
            `${newInstanceData[1]}`
        )
        // Verify it exists through its token balance
        expect(await Token.balanceOf(AirManInstance.address)).to.equal(
            50000000000000000n
        )

        return AirManInstance
    }
/*
    it('creates new Airdrop Manager instances, respecting ownership (and toggleCampaign)', async function () {
        const [ alice, bob, dana, maria, random ] = await ethers.getSigners()

        const { AdminPanel } = await deployAMFixture()

        // Updating the instanceCount after each deploy
        const bobAirMan = await deployNewAirmanInstance(bob, AdminPanel)
        instanceCount += 1
        const danaAirMan = await deployNewAirmanInstance(dana, AdminPanel)
        instanceCount += 1
        const mariaAirMan = await deployNewAirmanInstance(maria, AdminPanel)
        instanceCount += 1

        for (let thisInstance of [ bobAirMan, danaAirMan, mariaAirMan ]) {
            await expect(thisInstance.connect(alice).newAirdropCampaign(120, 50000000000000000n, true, 100000000000000000n)).
            to.be.reverted

            await expect(thisInstance.connect(random).newAirdropCampaign(120, 50000000000000000n, true, 100000000000000000n)).
            to.be.reverted
        }

        await expect(bobAirMan.connect(bob).newAirdropCampaign(120, 50000000000000000n, true, 10000000000000000n)).
        to.emit(bobAirMan, 'NewAirdropCampaign')
        await expect(danaAirMan.connect(dana).newAirdropCampaign(120, 50000000000000000n, true, 2000000000000000n)).
        to.emit(danaAirMan, 'NewAirdropCampaign')

        for (let thisInstance of [ bobAirMan, danaAirMan, mariaAirMan ]) {
            await expect(thisInstance.connect(alice).toggleCampaignOption(0, 0)).
            to.be.reverted

            await expect(thisInstance.connect(random).toggleCampaignOption(0, 0)).
            to.be.reverted
        }

        // Verify the campaign is active
        expect((await danaAirMan.campaigns(0))[4]).to.be.true

        await expect(danaAirMan.connect(dana).toggleCampaignOption(0, 0)).
        to.not.be.reverted
        expect((await danaAirMan.campaigns(0))[4]).to.be.false

        await expect(mariaAirMan.connect(maria).newAirdropCampaign(120, 50000000000000000n, false, 0)).
        to.emit(mariaAirMan, 'NewAirdropCampaign')
        // Verify the campaign is active
        expect((await mariaAirMan.campaigns(0))[4]).to.be.true

        await expect(mariaAirMan.connect(maria).toggleCampaignOption(0, 0)).
        to.not.be.reverted

        // Verify the campaign has been paused
        expect((await danaAirMan.campaigns(0))[4]).to.be.false
        expect((await mariaAirMan.campaigns(0))[4]).to.be.false

        // to do verify the hasFixedAmount and amountForEachUser
        expect((await bobAirMan.campaigns(0))[5]).to.be.true
        expect((await danaAirMan.campaigns(0))[5]).to.be.true
        expect((await mariaAirMan.campaigns(0))[5]).to.be.false
        expect((await bobAirMan.campaigns(0))[6]).to.equal(10000000000000000n)
        expect((await danaAirMan.campaigns(0))[6]).to.equal(2000000000000000n)
        expect((await mariaAirMan.campaigns(0))[6]).to.equal(0)

        // Reset the test instance count
        instanceCount = 0
    })

    it('respects whitelist, users can receive their tokens as expected if no hasFixedAmount', async function () {
        const [ alice, bob, dana, maria, random ] = await ethers.getSigners()
        let testTokenValue = 50000000000000000n

        const { AdminPanel } = await deployAMFixture()

        // Updating the instanceCount after each deploy
        const danaAirMan = await deployNewAirmanInstance(dana, AdminPanel)

        await expect(danaAirMan.connect(dana).newAirdropCampaign(15, testTokenValue, false, 0)).
        to.emit(danaAirMan, 'NewAirdropCampaign')

        const danaAirManData = await danaAirMan.campaigns(0)
        const DanaAirdropFactory = await ethers.getContractFactory('AirdropCampaign')
        const danaAirdropInstance = await DanaAirdropFactory.attach(
            `${danaAirManData[2]}`
        )
        
        expect(await Token.balanceOf(danaAirdropInstance.address)).to.equal(
            await danaAirdropInstance.tokenBalance()
        )

        // add users to Dana's campaign
        await expect(danaAirMan.connect(dana).batchAddToWhitelist(0, [alice.address, maria.address, bob.address, random.address])).
        to.emit(danaAirdropInstance, 'NewParticipant')
        // verify these people got added
        for (let thisUser of [ alice, maria, bob, random ]) {
           expect((await danaAirdropInstance.participantInfo(thisUser.address))[1]).to.be.true
        }
        // Let's block Bob
        await expect(danaAirMan.connect(dana).toggleParticipation(0, bob.address)).
        to.emit(danaAirdropInstance, 'UserParticipationToggled')
        expect((await danaAirdropInstance.participantInfo(bob.address))[1]).to.be.false
        expect(await danaAirdropInstance.participantAmount()).to.equal(3)


        // Not claimable yet
        await expect(danaAirdropInstance.connect(random).receiveTokens()).
        to.be.revertedWith('Airdrop not claimable yet')

        // Time related code
        const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms))
        await delay(13500)

        // Dana cannot modify Random account's access, the campaign is over
        await expect(danaAirMan.connect(dana).toggleParticipation(0, random.address)).
        to.be.revertedWith("AirdropCampaign.toggleIsActive: Can't modify users, time is up")
        // Dana is not on whitelist / bob is blocked / cannot block as campaign has ended
        await expect(danaAirdropInstance.connect(dana).receiveTokens()).
        to.be.revertedWith("You can't claim this airdrop")
        await expect(danaAirdropInstance.connect(bob).receiveTokens()).
        to.be.revertedWith("You can't claim this airdrop")

        // Claim alice tokens / claim random account tokens and get blocked by the contract 
        let randomOGTokenBalance = await Token.balanceOf(random.address)
        let mariaOGTokenBalance = await Token.balanceOf(maria.address)
        let aliceOGTokenBalance = await Token.balanceOf(alice.address)

        // claiming tokens
        await expect(danaAirdropInstance.connect(random).receiveTokens()).
        to.emit(danaAirdropInstance, 'TokenClaimed')
        await expect(danaAirdropInstance.connect(maria).receiveTokens()).
        to.emit(danaAirdropInstance, 'TokenClaimed')
        await expect(danaAirdropInstance.connect(alice).receiveTokens()).
        to.emit(danaAirdropInstance, 'TokenClaimed')
        // check they received their tokens
        expect(await Token.balanceOf(random.address)).to.equal(
            randomOGTokenBalance + (testTokenValue / BigInt(await danaAirdropInstance.participantAmount()))
        )
        expect(await Token.balanceOf(maria.address)).to.equal(
            BigInt(mariaOGTokenBalance) + (testTokenValue / BigInt(await danaAirdropInstance.participantAmount()))
        )
        expect(await Token.balanceOf(alice.address)).to.equal(
            BigInt(aliceOGTokenBalance) + (testTokenValue / BigInt(await danaAirdropInstance.participantAmount()))
        )
        // already claimed
        await expect(danaAirdropInstance.connect(random).receiveTokens()).
        to.be.revertedWith('You already claimed')

    })

    it('has paid whitelist, users can receive their tokens as expected if hasFixedAmount', async function () {
        const [ alice, bob, dana, maria, random ] = await ethers.getSigners()
        let testTokenValue = 50000000000000000n
        let testAirdropValue = 10000000000000000n
        const { AdminPanel, TestValue } = await deployAMFixture()
        
        const bobAirMan = await deployNewAirmanInstance(bob, AdminPanel)

        // create new test campaigns
        await expect(bobAirMan.connect(bob).newAirdropCampaign(15, testTokenValue, true, testAirdropValue)).
        to.emit(bobAirMan, 'NewAirdropCampaign')

        // add the instance of the new campaign
        const bobAirManData = await bobAirMan.campaigns(0)
        const BobAirdropFactory = await ethers.getContractFactory('AirdropCampaign')
        const bobAirdropInstance = await BobAirdropFactory.attach(`${bobAirManData[2]}`)
        expect(await Token.balanceOf(bobAirdropInstance.address)).to.equal(testTokenValue)
        
        // Checking the status
        expect(await bobAirdropInstance.acceptPayableWhitelist()).to.be.false
        // Let's turn on payableWhitelist 
        await expect(bobAirMan.connect(bob).toggleCampaignOption(0, 1)).
        to.emit(bobAirdropInstance, 'CampaignStatusToggled')
        // Checking the status
        expect(await bobAirdropInstance.acceptPayableWhitelist()).to.be.true
        // Let's set the maxParticipantAmount
        await expect(bobAirMan.connect(bob).updateCampaignValue(0, 1, 5)).
        to.emit(bobAirdropInstance, 'ModifiedValue')

        // setting the fee
        await expect(bobAirMan.connect(bob).updateCampaignValue(0, 0, TestValue)).
        to.emit(bobAirdropInstance, 'ModifiedValue')

        for (let thisUser of [ alice, bob, dana, maria, random ]) {
            // Verify they can't reclaim, add them, verify they got enabled
            expect((await bobAirdropInstance.participantInfo(thisUser.address))[1]).to.be.false
            await expect(bobAirdropInstance.connect(thisUser).addToPayableWhitelist({
                value: TestValue,
            })).
            to.emit(bobAirdropInstance, 'NewParticipant')

            expect((await bobAirdropInstance.participantInfo(thisUser.address))[1]).to.be.true
        }

        // Not claimable yet
        await expect(bobAirdropInstance.connect(random).receiveTokens()).
        to.be.revertedWith('Airdrop not claimable yet')

        // Time related code
        const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms))
        await delay(13500)

        // lets claim the tokens
        for (let thisUser of [ alice, dana, maria, random ]) {
            let thisUserOGTokenBalance = await Token.balanceOf(thisUser.address)

            await expect(bobAirdropInstance.connect(thisUser).receiveTokens()).
            to.emit(bobAirdropInstance, 'TokenClaimed')
            
            expect(await Token.balanceOf(thisUser.address)).to.equal(
                BigInt(thisUserOGTokenBalance) + (BigInt(await bobAirdropInstance.amountForEachUser()))
            )
        }
    })

    it('rejects users after hasFixedAmount user limit is reached', async function () {
        const [ alice, bob, dana, maria, random ] = await ethers.getSigners()
        let testTokenValue = 50000000000000000n
        let testAirdropValue = 15000000000000000n
        const { AdminPanel, TestValue } = await deployAMFixture()
        
        const bobAirMan = await deployNewAirmanInstance(bob, AdminPanel)

        // create new test campaigns
        await expect(bobAirMan.connect(bob).newAirdropCampaign(15, testTokenValue, true, testAirdropValue)).
        to.emit(bobAirMan, 'NewAirdropCampaign')

        // add the instance of the new campaign
        const bobAirManData = await bobAirMan.campaigns(0)
        const BobAirdropFactory = await ethers.getContractFactory('AirdropCampaign')
        const bobAirdropInstance = await BobAirdropFactory.attach(`${bobAirManData[2]}`)
        expect(await Token.balanceOf(bobAirdropInstance.address)).to.equal(testTokenValue)

        // Let's turn on payableWhitelist
        await expect(bobAirMan.connect(bob).toggleCampaignOption(0, 1)).
        to.emit(bobAirdropInstance, 'CampaignStatusToggled')
        // setting the fee and the max amount of participants
        await expect(bobAirMan.connect(bob).updateCampaignValue(0, 0, 0)).
        to.emit(bobAirdropInstance, 'ModifiedValue')
        await expect(bobAirMan.connect(bob).updateCampaignValue(0, 1, 3)).
        to.emit(bobAirdropInstance, 'ModifiedValue')

        for (let thisUser of [ dana, maria, random ]) {
            // Verify they can't reclaim, add them, verify they got enabled
            await expect(bobAirdropInstance.connect(thisUser).addToPayableWhitelist({
                value: 0,
                })).
            to.emit(bobAirdropInstance, 'NewParticipant')
        }

        await expect(bobAirdropInstance.connect(alice).addToPayableWhitelist({
            value: 0,
            })).
        to.be.revertedWith('AirdropCampaign._addToWhitelist.hasFixedAmount: Can not join, whitelist is full')
    })
*/
    it('allows to withdraw the AirMan, individual AirCampaigns tokens and Ether', async function () {
        const [ alice, bob, dana, maria, random ] = await ethers.getSigners()
        let testTokenValue = 50000000000000000n
        let testAirdropValue = 15000000000000000n
        const { AdminPanel, TestValue } = await deployAMFixture()
        
        const mariaAirMan = await deployNewAirmanInstance(maria, AdminPanel)

        // create new test campaigns
        await expect(mariaAirMan.connect(maria).newAirdropCampaign(15, testTokenValue, true, testAirdropValue)).
        to.emit(mariaAirMan, 'NewAirdropCampaign')

        // add the instance of the new campaign
        const mariaAirManData = await mariaAirMan.campaigns(0)
        const MariaAirdropFactory = await ethers.getContractFactory('AirdropCampaign')
        const mariaAirdropInstance = await MariaAirdropFactory.attach(`${mariaAirManData[2]}`)

        // to do all of the rest

    })

})