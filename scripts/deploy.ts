import { ethers } from "hardhat";
import { expect } from 'chai'
import '@nomicfoundation/hardhat-chai-matchers'

async function main() {
    // TO DO optimize all this by breaking it into several async functions
    const [ owner ] = await ethers.getSigners()
    const TestValue = ethers.utils.parseEther('0.0001')
    console.log(`Deployer address: ${owner.address}`)

    // Deploying the Test Token
    console.log('Deploying the Test token ...')
    const tokenFactory = await ethers.getContractFactory('HTA1')
    const Token = await tokenFactory.deploy(
        10000000000000000000n,
        'MockERC20',
        'MTKN'
    )

    await Token.deployed()
    console.log(`Test token deployed in ${Token.address}, owner address has ${await Token.balanceOf(owner.address)} tokens`);

    // Deploying the Admin Panel
    console.log('Deploying the Admin Panel ...')
    const AirManAdminPanel = await ethers.getContractFactory("AdminPanel");
    const adminPanel = await AirManAdminPanel.deploy(TestValue);

    await adminPanel.deployed();
        // Time related code
        const delay = (ms) => new Promise((resolve) => setTimeout(resolve, ms));
        await delay(3500);
    
    console.log('Approving tokens to the Admin Panel ...')
    expect(await Token.connect(owner).approve(adminPanel.address, 200000000000000000n)).
        to.emit(Token, 'Approval')
    expect(await Token.allowance(owner.address, adminPanel.address)).
        to.equal(200000000000000000n)
    console.log(await Token.connect(owner).allowance(owner.address, adminPanel.address))
        // Time related code
        await delay(3500)
        console.log(`Admin panel deployed in ${adminPanel.address}`);

    // Deploying an AirdropFactory
    console.log('Deploying the AirdropFactory ...')
    await adminPanel.connect(owner).newAirdropManagerInstance(
        Token.address, 
        20000000000000000n,
        {
        value: TestValue,
        })
    // Connecting to the new AirMan instance address
    console.log('Connecting to the new AirMan instance ...')
    const newInstanceData = await adminPanel.deployedManagers(0)
    console.log('1')
    const AirManFactory = await ethers.getContractFactory('AirdropManager')
    console.log('2')
    const airManInstance = await AirManFactory.attach(
        `${newInstanceData[1]}`
    )
    console.log('3')

    console.log(`New AirMan instance deployed in ${airManInstance.address}`);

}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});