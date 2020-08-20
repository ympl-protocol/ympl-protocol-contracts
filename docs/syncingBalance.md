### syncing

If you plan to add this token to uniswap / balancer, you need to call `addTransaction` function to sync the rebased balance to the protocol. Otherwise user won't be able to trade and liquidity can't be withdraw.

1) enocde function as follow

```
# Sync tx uniswap mainnet
web3.eth.abi.encodeFunctionCall({
  name: 'sync',
  type: 'function',
  inputs: [],
}, []);

0xfff6cae9

# Gulp tx
web3.eth.abi.encodeFunctionCall({
  name: 'gulp',
  type: 'function',
  inputs: [{
      type: 'address',
      name: 'token'
  }],
}, ['0xD46bA6D942050d489DBd938a2C909A5d5039A161']);
```

2) Admin invokes `addTransaction` with the destination contract address and `bytes`
as encoded from step 1.