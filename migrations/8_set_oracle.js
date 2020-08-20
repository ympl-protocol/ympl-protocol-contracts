require('dotenv').config()

const UFragmentsPolicy = artifacts.require('UFragmentsPolicy')
const UniswapOracle = artifacts.require('UniswapOracle')

module.exports = async function (deployer) { 
    deployer.then(async () => {
        const UFragmentsPolicyContract = await UFragmentsPolicy.deployed()
        const UniswapOracleContract = await UniswapOracle.deployed()
        UFragmentsPolicyContract.setMarketOracle(UniswapOracleContract.address)
        UniswapOracleContract.setPolicy(UFragmentsPolicyContract.address)
    })
}