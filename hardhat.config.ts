/** @type import('hardhat/config').HardhatUserConfig */
import '@nomiclabs/hardhat-ethers'
import * as dotenv from 'dotenv'
import { task } from "hardhat/config"
import './scripts/networkTest'

dotenv.config()

const MNEMONIC = process.env.MNEMONIC

export default {
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
