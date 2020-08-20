require('dotenv').config()

const UniswapOracle = artifacts.require('UniswapOracle')

const UFragments = artifacts.require('UFragments')

const uniswapContracts = {
    ropsten: {
        factory: '0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f',
        weth: '0xc778417E063141139Fce010982780140Aa0cD5Ab'
    }
}

module.exports = async function (deployer, network) {  
    const UFragmentsContract = await UFragments.deployed()
    await deployer.deploy(
        UniswapOracle,
        uniswapContracts[network].factory,
        uniswapContracts[network].weth,
        UFragmentsContract.address
        )
    const UniswapOracleContract = await UniswapOracle.deployed()
    console.log(`Deploy Uniswap UniswapOracle ${UniswapOracleContract.address}`)
}