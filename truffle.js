require('dotenv').config()
const HDWalletProvider = require('@truffle/hdwallet-provider')

module.exports = {
  networks: {
    ropsten: {
      provider: () => new HDWalletProvider(
        process.env.DEPLOYER_PRIVATE_KEY, 
        `https://ropsten.infura.io/v3/${process.env.INFURA_KEY}`
      ),
      network_id: 3,
      gas: 2000000,
      skipDryRun: true
    },
    mainnet: {
      provider: () => new HDWalletProvider(
        process.env.DEPLOYER_MAINNET_PRIVATE_KEY, 
        `https://mainnet.infura.io/v3/${process.env.INFURA_KEY}`
      ),
      network_id: 1,
      skipDryRun: false,
      gasPrice: 150000000000
    },
  },
  compilers: {
    solc: {
      version: '0.6.6',
      settings: {
        optimizer: {
          enabled: true,
          runs: 200
        },
      }
    }
  },
  mocha: {
    enableTimeouts: false
  },
  plugins: [
    'truffle-plugin-verify'
  ],
  api_keys: {
    etherscan: process.env.ETHERSCAN_API
  }
}
