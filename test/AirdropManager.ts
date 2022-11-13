const { expect } = require('chai')
const { BigNumber } = require('ethers')
const { artifacts, contract, ethers, network } = require('hardhat')
require('@nomicfoundation/hardhat-chai-matchers')

describe('AirdropManager', function () {

    async function deployMockToken() {
        const [alice] = await ethers.getSigners()

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

        return { Token }
    }

    async function deployAMFixture() {

    }

    it('', async function () {
    })

    it('', async function () {
    })

    it('', async function () {
    })

})