require('dotenv').config()

const UFragmentsPolicy = artifacts.require('UFragmentsPolicy')
const UFragments = artifacts.require('UFragments')

module.exports = async function (deployer) {  
  const UFragmentsContract = await UFragments.deployed()
  const UFragmentsPolicyContract = await deployer.deploy(UFragmentsPolicy, UFragmentsContract.address)
  console.log(
    `Initializing UFragmentsPolicyContract with
      uFragmentsContact:${UFragmentsPolicyContract.address}
    `
  )
}