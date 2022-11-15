/** @type import('hardhat/config').HardhatUserConfig */
import * as dotenv from 'dotenv'
dotenv.config()
import '@nomiclabs/hardhat-ethers'

const MNEMONIC = process.env.MNEMONIC

module.exports = {
    solidity: '0.8.17',
    mocha: {
        timeout: 100000000,
    },
    networks: {
        fantom_testnet: {
            url: `https://rpc.testnet.fantom.network/`,
            accounts: {
                mnemonic: MNEMONIC,
            },
            chainId: 4002,
        },
        matic_testnet: {
            url: `https://matic-mumbai.chainstacklabs.com`,
            /*accounts: {
                mnemonic: MNEMONIC,
            },*/
            chainId: 80001,
        },
        nova_network: {
            url: `https://dev.rpc.novanetwork.io/`,
            accounts: {
                mnemonic: MNEMONIC,
            },
            chainId: 87,
        },
    },
    settings: {
        optimizer: {
            enabled: true,
            runs: 200,
        },
    },
}
