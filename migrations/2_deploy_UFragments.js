require('dotenv').config()
const UFragments = artifacts.require('UFragments')

module.exports = async function (deployer) {
  await deployer.deploy(UFragments)
   UFragments.deployed()
}