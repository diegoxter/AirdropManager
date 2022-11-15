import { expect } from 'chai'
import { BigNumber, Contract, Signer } from 'ethers'
import { artifacts, ethers, network } from 'hardhat'
import '@nomicfoundation/hardhat-chai-matchers'
import { SignerWithAddress } from '@nomiclabs/hardhat-ethers/signers'

describe('AirdropManager', function () {

    const totalToken = 10000000000000000000n
    let instanceCount = 0

    async function deployMockToken() {
        const [ alice, bob, dana, maria ] = await ethers.getSigners()

        const tokenFactory = await ethers.getContractFactory('HTA1')
        const Token = await tokenFactory.deploy(
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

    async function deployNewAirmanInstance(owner: SignerWithAddress, token: Contract, AdminPanel: Contract) {
        const TestValue = ethers.utils.parseEther('0.0001')

        // owner needs to approve some tokens to create a new AirManInstance
        await token.connect(owner).approve(AdminPanel.address, 1000000000000000000n)
        
        // Time related code
        const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms))
        await delay(3500)
        expect(await token.allowance(owner.address, AdminPanel.address)).
        to.equal(1000000000000000000n)

        // owner creates a new AirManInstance
        await expect(AdminPanel.connect(owner).newAirdropManagerInstance(
            token.address, 
            1000000000000000000n, 
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
        expect(await token.balanceOf(AirManInstance.address)).to.equal(
            1000000000000000000n
        )

        return AirManInstance
    }

    it('creates new Airdrop Manager instances, respecting ownership (and toggleCampaign)', async function () {
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
            await expect(thisInstance.connect(alice).newAirdropCampaign(120, 500000000000000000n, true, 100000000000000000n)).
            to.be.revertedWith('This can only be done by the owner')

            await expect(thisInstance.connect(random).newAirdropCampaign(120, 500000000000000000n, true, 100000000000000000n)).
            to.be.revertedWith('This can only be done by the owner')
        }

        await expect(bobAirMan.connect(bob).newAirdropCampaign(120, 500000000000000000n, true, 100000000000000000n)).
        to.emit(bobAirMan, 'NewAirdropCampaign')
        await expect(danaAirMan.connect(dana).newAirdropCampaign(120, 500000000000000000n, true, 100000000000000000n)).
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
        expect((await danaAirMan.campaigns(0))[4]).to.be.false

        await expect(mariaAirMan.connect(maria).newAirdropCampaign(120, 500000000000000000n, false, 0)).
        to.emit(mariaAirMan, 'NewAirdropCampaign')
        // Verify the campaign is active
        expect((await mariaAirMan.campaigns(0))[4]).to.be.true

        await expect(mariaAirMan.connect(maria).toggleCampaign(0)).
        to.not.be.reverted

        // Verify the campaign has been paused
        expect((await danaAirMan.campaigns(0))[4]).to.be.false
        expect((await mariaAirMan.campaigns(0))[4]).to.be.false

        // to do verify the hasFixedAmount and amountForEachUser
        expect((await bobAirMan.campaigns(0))[5]).to.be.true
        expect((await danaAirMan.campaigns(0))[5]).to.be.true
        expect((await mariaAirMan.campaigns(0))[5]).to.be.false
        expect((await bobAirMan.campaigns(0))[6]).to.equal(100000000000000000n)
        expect((await danaAirMan.campaigns(0))[6]).to.equal(100000000000000000n)
        expect((await mariaAirMan.campaigns(0))[6]).to.equal(0)

        // Reset the test instance count
        instanceCount = 0
    })

    it('respects whitelist, users can receive their tokens as expected if no hasFixedAmount', async function () {
        const [ alice, bob, dana, maria, random ] = await ethers.getSigners()
        let testTokenValue = 500000000000000000n

        const { AdminPanel } = await deployAMFixture()
        const genericToken = await deployMockToken()

        // Updating the instanceCount after each deploy
        const danaAirMan = await deployNewAirmanInstance(dana, genericToken, AdminPanel)

        await expect(danaAirMan.connect(dana).newAirdropCampaign(15, testTokenValue, false, 0)).
        to.emit(danaAirMan, 'NewAirdropCampaign')

        const danaAirManData = await danaAirMan.campaigns(0)
        const DanaAirdropFactory = await ethers.getContractFactory('AirdropCampaign')
        const danaAirdropInstance = await DanaAirdropFactory.attach(
            `${danaAirManData[2]}`
        )
        
        expect(await genericToken.balanceOf(danaAirdropInstance.address)).to.equal(
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
        to.be.revertedWith('AirdropCampaign: Airdrop still not claimable')

        // Time related code
        const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms))
        await delay(13500)

        // Dana cannot modify Random account's access, the campaign is over
        await expect(danaAirMan.connect(dana).toggleParticipation(0, random.address)).
        to.be.revertedWith('AirdropCampaign.toggleIsActive: Can not modify users, time is up')
        // Dana is not on whitelist / bob is blocked / cannot block as campaign has ended
        await expect(danaAirdropInstance.connect(dana).receiveTokens()).
        to.be.revertedWith('AirdropCampaign: You can not claim this airdrop')
        await expect(danaAirdropInstance.connect(bob).receiveTokens()).
        to.be.revertedWith('AirdropCampaign: You can not claim this airdrop')

        // Claim alice tokens / claim random account tokens and get blocked by the contract 
        let randomOGTokenBalance = await genericToken.balanceOf(random.address)
        let mariaOGTokenBalance = await genericToken.balanceOf(maria.address)
        let aliceOGTokenBalance = await genericToken.balanceOf(alice.address)

        // claiming tokens
        await expect(danaAirdropInstance.connect(random).receiveTokens()).
        to.emit(danaAirdropInstance, 'TokenClaimed')
        await expect(danaAirdropInstance.connect(maria).receiveTokens()).
        to.emit(danaAirdropInstance, 'TokenClaimed')
        await expect(danaAirdropInstance.connect(alice).receiveTokens()).
        to.emit(danaAirdropInstance, 'TokenClaimed')
        // check they received their tokens
        expect(await genericToken.balanceOf(random.address)).to.equal(
            randomOGTokenBalance + (testTokenValue / BigInt(await danaAirdropInstance.participantAmount()))
        )
        expect(await genericToken.balanceOf(maria.address)).to.equal(
            BigInt(mariaOGTokenBalance) + (testTokenValue / BigInt(await danaAirdropInstance.participantAmount()))
        )
        expect(await genericToken.balanceOf(alice.address)).to.equal(
            BigInt(aliceOGTokenBalance) + (testTokenValue / BigInt(await danaAirdropInstance.participantAmount()))
        )
        // already claimed
        await expect(danaAirdropInstance.connect(random).receiveTokens()).
        to.be.revertedWith('AirdropCampaign: You already claimed your tokens')

    })

    it('has paid whitelist, users can receive their tokens as expected if hasFixedAmount', async function () {
        const [ alice, bob, dana, maria, random ] = await ethers.getSigners()
        let testTokenValue = 500000000000000000n
        let testAirdropValue = 100000000000000000n
        const { AdminPanel, TestValue } = await deployAMFixture()
        const bobToken = await deployMockToken()
        
        const bobAirMan = await deployNewAirmanInstance(bob, bobToken, AdminPanel)

        // create new test campaigns
        await expect(bobAirMan.connect(bob).newAirdropCampaign(15, testTokenValue, true, testAirdropValue)).
        to.emit(bobAirMan, 'NewAirdropCampaign')

        // add the instance of the new campaign
        const bobAirManData = await bobAirMan.campaigns(0)
        const BobAirdropFactory = await ethers.getContractFactory('AirdropCampaign')
        const bobAirdropInstance = await BobAirdropFactory.attach(`${bobAirManData[2]}`)
        expect(await bobToken.balanceOf(bobAirdropInstance.address)).to.equal(testTokenValue)
        
        // Checking the status
        expect(await bobAirdropInstance.acceptPayableWhitelist()).to.be.false
        // Let's turn on payableWhitelist 
        await expect(bobAirMan.connect(bob).togglePayableWhitelist(0)).
        to.emit(bobAirdropInstance, 'CampaignStatusToggled')
        // Checking the status
        expect(await bobAirdropInstance.acceptPayableWhitelist()).to.be.true
        // Let's set the maxParticipantAmount
        await expect(bobAirMan.connect(bob).updateMaxParticipantAmount(0, 5)).
        to.emit(bobAirdropInstance, 'NewMaxParticipantAmount')

        // setting the fee
        await expect(bobAirMan.connect(bob).updateWhitelistFee(0, TestValue)).
        to.emit(bobAirdropInstance, 'NewWhitelistFee')

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
        to.be.revertedWith('AirdropCampaign: Airdrop still not claimable')

        // Time related code
        const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms))
        await delay(13500)

        // lets claim the tokens
        for (let thisUser of [ alice, dana, maria, random ]) {
            let thisUserOGTokenBalance = await bobToken.balanceOf(thisUser.address)

            await expect(bobAirdropInstance.connect(thisUser).receiveTokens()).
            to.emit(bobAirdropInstance, 'TokenClaimed')
            
            expect(await bobToken.balanceOf(thisUser.address)).to.equal(
                BigInt(thisUserOGTokenBalance) + (BigInt(await bobAirdropInstance.amountForEachUser()))
            )
        }
    })

    it('rejects users after hasFixedAmount user limit is reached', async function () {
        const [ alice, bob, dana, maria, random ] = await ethers.getSigners()
        let testTokenValue = 500000000000000000n
        let testAirdropValue = 150000000000000000n
        const { AdminPanel, TestValue } = await deployAMFixture()
        const bobToken = await deployMockToken()
        
        const bobAirMan = await deployNewAirmanInstance(bob, bobToken, AdminPanel)

        // create new test campaigns
        await expect(bobAirMan.connect(bob).newAirdropCampaign(15, testTokenValue, true, testAirdropValue)).
        to.emit(bobAirMan, 'NewAirdropCampaign')

        // add the instance of the new campaign
        const bobAirManData = await bobAirMan.campaigns(0)
        const BobAirdropFactory = await ethers.getContractFactory('AirdropCampaign')
        const bobAirdropInstance = await BobAirdropFactory.attach(`${bobAirManData[2]}`)
        expect(await bobToken.balanceOf(bobAirdropInstance.address)).to.equal(testTokenValue)

        // Let's turn on payableWhitelist
        await expect(bobAirMan.connect(bob).togglePayableWhitelist(0)).
        to.emit(bobAirdropInstance, 'CampaignStatusToggled')
        // setting the fee and the max amount of participants
        await expect(bobAirMan.connect(bob).updateWhitelistFee(0, 0)).
        to.emit(bobAirdropInstance, 'NewWhitelistFee')
        await expect(bobAirMan.connect(bob).updateMaxParticipantAmount(0, 3)).
        to.emit(bobAirdropInstance, 'NewMaxParticipantAmount')

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

})