require('dotenv').config()

const UFragmentsPolicy = artifacts.require('UFragmentsPolicy')
const Orchestrator = artifacts.require('Orchestrator')

module.exports = async function (deployer) {  
  const UFragmentsPolicyContract = await UFragmentsPolicy.deployed()
  await deployer.deploy(Orchestrator, UFragmentsPolicyContract.address)
  console.log(`Deployed Orchestrator with UFragmentsPolicyContract:${UFragmentsPolicyContract.address}`)
}