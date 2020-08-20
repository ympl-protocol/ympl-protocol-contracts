# YMPL protocol contracts
This is the contract code for Ympl protocol, the contract is based from [Ampleforth](https://github.com/ampleforth/uFragments) with updated solidity version and customized to be Ympl protocol with random algorithm and rework how rebasing works.

# Development
```
npm install
```

you can choose to run the contracts on testnet / granache as you wish. We have pre config for `ropsten` test net. check `truffle.js` for more information.

## Test

This repository is a submodule of [ympl-protocol](https://github.com/ympl-protocol/ympl-protocol) which will run both unit test and e2e test there.


## migrations

```
npm run migrate:ympl
```
This will deploy all contracts and set all owner to the deployer, also config all the owners of each contract correctly.

## License

[GNU General Public License v3.0 (c) 2020 Fragments, Inc.](./LICENSE)
