require('dotenv').config()

const UFragmentsPolicy = artifacts.require('UFragmentsPolicy')
const UFragments = artifacts.require('UFragments')

module.exports = async function (deployer) {  
  deployer.then(async () => {
    const UFragmentsPolicyContract = await UFragmentsPolicy.deployed()
    const UFragmentsContract = await UFragments.deployed()
    await UFragmentsContract.setMonetaryPolicy(UFragmentsPolicyContract.address)
    console.log(`Set MonetaryPolicy on UFragmentsContract:${UFragmentsPolicyContract.address}`)
  })
}