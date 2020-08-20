require('dotenv').config()

const UFragmentsPolicy = artifacts.require('UFragmentsPolicy')
const Orchestrator = artifacts.require('Orchestrator')

module.exports = async function (deployer) {  
  deployer.then(async () => {
    const UFragmentsPolicyContract = await UFragmentsPolicy.deployed()
    const OrchestratorContract = await Orchestrator.deployed()
    await UFragmentsPolicyContract.setOrchestrator(OrchestratorContract.address)
    console.log(`Set Orchestrator on UFragmentsPolicyContract:${OrchestratorContract.address}`)
  })
}